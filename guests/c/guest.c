/*
 * Guest written in C, compiled to WebAssembly with plain clang (no libc, no WASI).
 *
 * Contract shared by every guest in this repo (see README, "The guest contract"):
 *   int add(int a, int b)   -> a + b   (wrapping)
 *   int fib(int n)          -> n-th Fibonacci number (wrapping), fib(0)=0, fib(1)=1
 */

#define WASM_EXPORT(name) __attribute__((export_name(#name)))

WASM_EXPORT(add)
int add(int a, int b) {
    /* unsigned arithmetic so overflow wraps instead of being undefined behaviour */
    return (int)((unsigned)a + (unsigned)b);
}

WASM_EXPORT(fib)
int fib(int n) {
    unsigned a = 0, b = 1;
    for (int i = 0; i < n; i++) {
        unsigned t = a + b;
        a = b;
        b = t;
    }
    return (int)a;
}
