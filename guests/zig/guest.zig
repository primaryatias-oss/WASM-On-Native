//! Guest written in Zig, compiled to `wasm32-freestanding` (no libc, no WASI).
//!
//! Contract shared by every guest in this repo (see README, "The guest contract"):
//!   add(a: i32, b: i32) i32   a + b (wrapping)
//!   fib(n: i32) i32           n-th Fibonacci number (wrapping)

export fn add(a: i32, b: i32) i32 {
    return a +% b;
}

export fn fib(n: i32) i32 {
    var a: i32 = 0;
    var b: i32 = 1;
    var i: i32 = 0;
    while (i < n) : (i += 1) {
        const t = a +% b;
        a = b;
        b = t;
    }
    return a;
}
