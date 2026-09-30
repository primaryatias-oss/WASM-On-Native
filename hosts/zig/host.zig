// Native host written in Zig, embedding Wasmtime through its C API.
//
// Usage: zig-host <guest.wasm>
//
// The C API is imported with `zig translate-c` (see build.sh) into c.zig, so the code below
// uses the real Wasmtime types. Only libc is used for I/O, which keeps this file independent of
// the churn in Zig's std.process / std.Io APIs between releases.
//
// Every host in this repo implements the same algorithm (see README, "The host algorithm"):
//   1. Create an engine with the WebAssembly proposals that OCaml/Haskell guests need
//      (GC, exceptions, tail calls, typed function references) and a linker that provides WASI.
//   2. Instantiate the guest.
//   3. If it exports _start it is a WASI *command*: run it; exit status 0 means success.
//   4. Otherwise it is a *reactor* (a library): call _initialize if present, then call
//      add(20, 22) and fib(10) and compare against 42 and 55.
const c = @import("c.zig");

const expect_add: i32 = 42;
const expect_fib: i32 = 55;

fn fail(guest: [*:0]const u8, what: [*:0]const u8, err: ?*c.wasmtime_error_t, trap: ?*c.wasm_trap_t) c_int {
    _ = c.fprintf(c.stderr, "FAIL %s: %s", guest, what);
    var msg: c.wasm_byte_vec_t = .{ .size = 0, .data = null };
    if (err) |e| {
        c.wasmtime_error_message(e, &msg);
        c.wasmtime_error_delete(e);
    } else if (trap) |t| {
        c.wasm_trap_message(t, &msg);
        c.wasm_trap_delete(t);
    }
    if (msg.size > 0) {
        _ = c.fprintf(c.stderr, ": %.*s", @as(c_int, @intCast(msg.size)), msg.data);
        c.wasm_byte_vec_delete(&msg);
    }
    _ = c.fprintf(c.stderr, "\n");
    return 1;
}

// A WASI command finishes by calling proc_exit, which Wasmtime reports as an error carrying an
// exit status. Status 0 is a normal, successful exit.
fn isCleanExit(err: ?*c.wasmtime_error_t) bool {
    const e = err orelse return false;
    var status: c_int = 0;
    return c.wasmtime_error_exit_status(e, &status) and status == 0;
}

fn getFunc(ctx: ?*c.wasmtime_context_t, inst: *c.wasmtime_instance_t, name: [*:0]const u8, out: *c.wasmtime_func_t) bool {
    var item: c.wasmtime_extern_t = undefined;
    if (!c.wasmtime_instance_export_get(ctx, inst, name, c.strlen(name), &item)) return false;
    if (item.kind != c.WASMTIME_EXTERN_FUNC) return false;
    out.* = item.of.func;
    return true;
}

fn callI32(ctx: ?*c.wasmtime_context_t, f: *c.wasmtime_func_t, in: []const i32, out: *i32, guest: [*:0]const u8, name: [*:0]const u8) c_int {
    var args: [2]c.wasmtime_val_t = undefined;
    var result: c.wasmtime_val_t = undefined;
    for (in, 0..) |v, i| {
        args[i].kind = c.WASMTIME_I32;
        args[i].of.i32 = v;
    }
    var trap: ?*c.wasm_trap_t = null;
    const err = c.wasmtime_func_call(ctx, f, &args, in.len, &result, 1, &trap);
    if (err != null or trap != null) return fail(guest, name, err, trap);
    if (result.kind != c.WASMTIME_I32) return fail(guest, "result is not an i32", null, null);
    out.* = result.of.i32;
    return 0;
}

fn readFile(path: [*:0]const u8, size: *usize) ?[*]u8 {
    const fp = c.fopen(path, "rb") orelse return null;
    defer _ = c.fclose(fp);
    _ = c.fseek(fp, 0, c.SEEK_END);
    const n: usize = @intCast(c.ftell(fp));
    _ = c.fseek(fp, 0, c.SEEK_SET);
    const buf: [*]u8 = @ptrCast(c.malloc(n) orelse return null);
    if (c.fread(buf, 1, n, fp) != n) return null;
    size.* = n;
    return buf;
}

// Exported with the C calling convention so no Zig std start code (and no std.process API) is needed.
pub export fn main(argc: c_int, argv: [*c][*c]u8) c_int {
    if (argc != 2) {
        _ = c.fprintf(c.stderr, "usage: zig-host <guest.wasm>\n");
        return 2;
    }
    const guest: [*:0]const u8 = @ptrCast(argv[1]);

    var nbytes: usize = 0;
    const bytes = readFile(guest, &nbytes) orelse return fail(guest, "cannot read file", null, null);

    // 1. engine, store, linker with WASI
    const config = c.wasm_config_new();
    c.wasmtime_config_wasm_function_references_set(config, true);
    c.wasmtime_config_wasm_gc_set(config, true);
    c.wasmtime_config_wasm_exceptions_set(config, true);
    c.wasmtime_config_wasm_tail_call_set(config, true);
    const engine = c.wasm_engine_new_with_config(config); // takes ownership of config

    const store = c.wasmtime_store_new(engine, null, null);
    const ctx = c.wasmtime_store_context(store);

    const wasi = c.wasi_config_new();
    c.wasi_config_inherit_stdout(wasi);
    c.wasi_config_inherit_stderr(wasi);
    if (c.wasmtime_context_set_wasi(ctx, wasi)) |e| return fail(guest, "set_wasi", e, null);

    const linker = c.wasmtime_linker_new(engine);
    if (c.wasmtime_linker_define_wasi(linker)) |e| return fail(guest, "define_wasi", e, null);

    // 2. compile and instantiate
    var module: ?*c.wasmtime_module_t = null;
    if (c.wasmtime_module_new(engine, bytes, nbytes, &module)) |e| return fail(guest, "compile", e, null);
    c.free(@ptrCast(bytes));

    var instance: c.wasmtime_instance_t = undefined;
    var trap: ?*c.wasm_trap_t = null;
    const inst_err = c.wasmtime_linker_instantiate(linker, ctx, module, &instance, &trap);
    if (isCleanExit(inst_err)) {
        _ = c.printf("PASS %s: WASI command exited 0\n", guest);
        return 0;
    }
    if (inst_err != null or trap != null) return fail(guest, "instantiate", inst_err, trap);

    var f: c.wasmtime_func_t = undefined;
    var rc: c_int = 0;

    if (getFunc(ctx, &instance, "_start", &f)) {
        // 3. WASI command
        const err = c.wasmtime_func_call(ctx, &f, null, 0, null, 0, &trap);
        if (isCleanExit(err) or (err == null and trap == null)) {
            if (err) |e| c.wasmtime_error_delete(e);
            _ = c.printf("PASS %s: WASI command exited 0\n", guest);
        } else {
            rc = fail(guest, "_start", err, trap);
        }
    } else {
        // 4. reactor
        if (getFunc(ctx, &instance, "_initialize", &f)) {
            const err = c.wasmtime_func_call(ctx, &f, null, 0, null, 0, &trap);
            if (err != null or trap != null) rc = fail(guest, "_initialize", err, trap);
        }
        var sum: i32 = 0;
        var fib: i32 = 0;
        if (rc == 0) {
            if (!getFunc(ctx, &instance, "add", &f)) {
                rc = fail(guest, "missing export: add", null, null);
            } else {
                rc = callI32(ctx, &f, &[_]i32{ 20, 22 }, &sum, guest, "add");
            }
        }
        if (rc == 0) {
            if (!getFunc(ctx, &instance, "fib", &f)) {
                rc = fail(guest, "missing export: fib", null, null);
            } else {
                rc = callI32(ctx, &f, &[_]i32{10}, &fib, guest, "fib");
            }
        }
        if (rc == 0) {
            if (sum == expect_add and fib == expect_fib) {
                _ = c.printf("PASS %s: add(20,22)=%d fib(10)=%d\n", guest, @as(c_int, sum), @as(c_int, fib));
            } else {
                _ = c.fprintf(c.stderr, "FAIL %s: add(20,22)=%d (want %d) fib(10)=%d (want %d)\n", guest, @as(c_int, sum), @as(c_int, expect_add), @as(c_int, fib), @as(c_int, expect_fib));
                rc = 1;
            }
        }
    }
    return rc;
}
