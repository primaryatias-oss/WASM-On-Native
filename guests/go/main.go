// Guest written in Go, compiled with the standard toolchain (Go >= 1.24).
//
// Contract shared by every guest in this repo (see README, "The guest contract"):
//
//	add(a, b int32) int32  -> a + b (wrapping)
//	fib(n int32) int32     -> n-th Fibonacci number (wrapping)
//
// Built with GOOS=wasip1 GOARCH=wasm and -buildmode=c-shared, which produces a
// WASI *reactor*: the module has no _start, it exports _initialize instead, and
// the //go:wasmexport functions below become wasm exports.
package main

//go:wasmexport add
func add(a, b int32) int32 {
	return a + b
}

//go:wasmexport fib
func fib(n int32) int32 {
	var a, b int32 = 0, 1
	for i := int32(0); i < n; i++ {
		a, b = b, a+b
	}
	return a
}

// main is required by the compiler but never runs in a reactor module.
func main() {}
