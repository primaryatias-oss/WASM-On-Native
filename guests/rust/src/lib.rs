//! Guest written in Rust, compiled to `wasm32-unknown-unknown` (no WASI, no std).
//!
//! Contract shared by every guest in this repo (see README, "The guest contract"):
//!   add(a: i32, b: i32) -> i32   a + b (wrapping)
//!   fib(n: i32) -> i32           n-th Fibonacci number (wrapping)

#![no_std]

#[panic_handler]
fn panic(_info: &core::panic::PanicInfo) -> ! {
    core::arch::wasm32::unreachable()
}

#[no_mangle]
pub extern "C" fn add(a: i32, b: i32) -> i32 {
    a.wrapping_add(b)
}

#[no_mangle]
pub extern "C" fn fib(n: i32) -> i32 {
    let (mut a, mut b) = (0i32, 1i32);
    for _ in 0..n {
        let t = a.wrapping_add(b);
        a = b;
        b = t;
    }
    a
}
