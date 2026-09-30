/*
 * Native host written in C, embedding Wasmtime through its C API.
 *
 * Usage: c-host <guest.wasm>
 *
 * Every host in this repo implements the same algorithm (see README, "The host algorithm"):
 *   1. Create an engine with the WebAssembly proposals that OCaml/Haskell guests need
 *      (GC, exceptions, tail calls, typed function references) and a linker that provides WASI.
 *   2. Instantiate the guest.
 *   3. If it exports _start it is a WASI *command*: run it; exit status 0 means success.
 *   4. Otherwise it is a *reactor* (a library): call _initialize if present, then call
 *      add(20, 22) and fib(10) and compare against 42 and 55.
 */
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <wasm.h>
#include <wasmtime.h>

#define EXPECT_ADD 42
#define EXPECT_FIB 55

static int fail(const char *guest, const char *what, wasmtime_error_t *error, wasm_trap_t *trap) {
    fprintf(stderr, "FAIL %s: %s", guest, what);
    wasm_byte_vec_t msg;
    msg.size = 0;
    msg.data = NULL;
    if (error != NULL) {
        wasmtime_error_message(error, &msg);
        wasmtime_error_delete(error);
    } else if (trap != NULL) {
        wasm_trap_message(trap, &msg);
        wasm_trap_delete(trap);
    }
    if (msg.size > 0) {
        fprintf(stderr, ": %.*s", (int)msg.size, msg.data);
        wasm_byte_vec_delete(&msg);
    }
    fprintf(stderr, "\n");
    return 1;
}

/* A WASI command finishes by calling proc_exit, which Wasmtime reports as an error carrying
 * an exit status. Status 0 is a normal, successful exit. */
static bool is_clean_exit(wasmtime_error_t *error) {
    int status;
    return error != NULL && wasmtime_error_exit_status(error, &status) && status == 0;
}

static bool get_func(wasmtime_context_t *ctx, wasmtime_instance_t *inst, const char *name,
                     wasmtime_func_t *out) {
    wasmtime_extern_t item;
    if (!wasmtime_instance_export_get(ctx, inst, name, strlen(name), &item)) return false;
    if (item.kind != WASMTIME_EXTERN_FUNC) return false;
    *out = item.of.func;
    return true;
}

static int call_i32(wasmtime_context_t *ctx, wasmtime_func_t *f, const int32_t *in, size_t nin,
                    int32_t *out, const char *guest, const char *name) {
    wasmtime_val_t args[2];
    wasmtime_val_t result;
    for (size_t i = 0; i < nin; i++) {
        args[i].kind = WASMTIME_I32;
        args[i].of.i32 = in[i];
    }
    wasm_trap_t *trap = NULL;
    wasmtime_error_t *error = wasmtime_func_call(ctx, f, args, nin, &result, 1, &trap);
    if (error != NULL || trap != NULL) return fail(guest, name, error, trap);
    if (result.kind != WASMTIME_I32) return fail(guest, "result is not an i32", NULL, NULL);
    *out = result.of.i32;
    return 0;
}

static int read_file(const char *path, uint8_t **data, size_t *size) {
    FILE *fp = fopen(path, "rb");
    if (fp == NULL) return 1;
    fseek(fp, 0, SEEK_END);
    long n = ftell(fp);
    fseek(fp, 0, SEEK_SET);
    *data = malloc((size_t)n);
    if (*data == NULL || fread(*data, 1, (size_t)n, fp) != (size_t)n) {
        fclose(fp);
        return 1;
    }
    fclose(fp);
    *size = (size_t)n;
    return 0;
}

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: %s <guest.wasm>\n", argv[0]);
        return 2;
    }
    const char *guest = argv[1];

    uint8_t *bytes = NULL;
    size_t nbytes = 0;
    if (read_file(guest, &bytes, &nbytes) != 0) return fail(guest, "cannot read file", NULL, NULL);

    /* 1. engine, store, linker with WASI */
    wasm_config_t *config = wasm_config_new();
    wasmtime_config_wasm_function_references_set(config, true);
    wasmtime_config_wasm_gc_set(config, true);
    wasmtime_config_wasm_exceptions_set(config, true);
    wasmtime_config_wasm_tail_call_set(config, true);
    wasm_engine_t *engine = wasm_engine_new_with_config(config); /* takes ownership of config */

    wasmtime_store_t *store = wasmtime_store_new(engine, NULL, NULL);
    wasmtime_context_t *ctx = wasmtime_store_context(store);

    wasi_config_t *wasi = wasi_config_new();
    wasi_config_inherit_stdout(wasi);
    wasi_config_inherit_stderr(wasi);
    wasmtime_error_t *error = wasmtime_context_set_wasi(ctx, wasi); /* takes ownership */
    if (error != NULL) return fail(guest, "set_wasi", error, NULL);

    wasmtime_linker_t *linker = wasmtime_linker_new(engine);
    error = wasmtime_linker_define_wasi(linker);
    if (error != NULL) return fail(guest, "define_wasi", error, NULL);

    /* 2. compile and instantiate */
    wasmtime_module_t *module = NULL;
    error = wasmtime_module_new(engine, bytes, nbytes, &module);
    if (error != NULL) return fail(guest, "compile", error, NULL);
    free(bytes);

    wasmtime_instance_t instance;
    wasm_trap_t *trap = NULL;
    error = wasmtime_linker_instantiate(linker, ctx, module, &instance, &trap);
    if (is_clean_exit(error)) {
        printf("PASS %s: WASI command exited 0\n", guest);
        return 0;
    }
    if (error != NULL || trap != NULL) return fail(guest, "instantiate", error, trap);

    int rc = 0;
    wasmtime_func_t f;

    if (get_func(ctx, &instance, "_start", &f)) {
        /* 3. WASI command */
        error = wasmtime_func_call(ctx, &f, NULL, 0, NULL, 0, &trap);
        if (is_clean_exit(error) || (error == NULL && trap == NULL)) {
            if (error != NULL) wasmtime_error_delete(error);
            printf("PASS %s: WASI command exited 0\n", guest);
        } else {
            rc = fail(guest, "_start", error, trap);
        }
    } else {
        /* 4. reactor */
        if (get_func(ctx, &instance, "_initialize", &f)) {
            error = wasmtime_func_call(ctx, &f, NULL, 0, NULL, 0, &trap);
            if (error != NULL || trap != NULL) rc = fail(guest, "_initialize", error, trap);
        }
        int32_t sum = 0, fib = 0;
        if (rc == 0) {
            if (!get_func(ctx, &instance, "add", &f)) {
                rc = fail(guest, "missing export: add", NULL, NULL);
            } else {
                int32_t in[2] = {20, 22};
                rc = call_i32(ctx, &f, in, 2, &sum, guest, "add");
            }
        }
        if (rc == 0) {
            if (!get_func(ctx, &instance, "fib", &f)) {
                rc = fail(guest, "missing export: fib", NULL, NULL);
            } else {
                int32_t in[1] = {10};
                rc = call_i32(ctx, &f, in, 1, &fib, guest, "fib");
            }
        }
        if (rc == 0) {
            if (sum == EXPECT_ADD && fib == EXPECT_FIB) {
                printf("PASS %s: add(20,22)=%d fib(10)=%d\n", guest, sum, fib);
            } else {
                fprintf(stderr, "FAIL %s: add(20,22)=%d (want %d) fib(10)=%d (want %d)\n", guest,
                        sum, EXPECT_ADD, fib, EXPECT_FIB);
                rc = 1;
            }
        }
    }

    wasmtime_module_delete(module);
    wasmtime_linker_delete(linker);
    wasmtime_store_delete(store);
    wasm_engine_delete(engine);
    return rc;
}
