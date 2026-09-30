// Native host written in Go, embedding Wasmtime through wasmtime-go (cgo bindings to the C API).
//
// Usage: go-host <guest.wasm>
//
// Every host in this repo implements the same algorithm (see README, "The host algorithm"):
//  1. Create an engine with the WebAssembly proposals that OCaml/Haskell guests need
//     (GC, exceptions, tail calls, typed function references) and a linker that provides WASI.
//  2. Instantiate the guest.
//  3. If it exports _start it is a WASI *command*: run it; exit status 0 means success.
//  4. Otherwise it is a *reactor* (a library): call _initialize if present, then call
//     add(20, 22) and fib(10) and compare against 42 and 55.
package main

import (
	"fmt"
	"os"

	"github.com/bytecodealliance/wasmtime-go/v49"
)

const (
	expectAdd = 42
	expectFib = 55
)

// A WASI command finishes by calling proc_exit, which Wasmtime reports as an error carrying
// an exit status. Status 0 is a normal, successful exit.
func isCleanExit(err error) bool {
	if e, ok := err.(*wasmtime.Error); ok {
		status, has := e.ExitStatus()
		return has && status == 0
	}
	return false
}

func run(guest string) (string, error) {
	// 1. engine, store, linker with WASI
	config := wasmtime.NewConfig()
	config.SetWasmFunctionReferences(true)
	config.SetWasmGC(true)
	config.SetWasmExceptions(true)
	config.SetWasmTailCall(true)
	engine := wasmtime.NewEngineWithConfig(config)

	store := wasmtime.NewStore(engine)
	wasi := wasmtime.NewWasiConfig()
	wasi.InheritStdout()
	wasi.InheritStderr()
	store.SetWasi(wasi)

	linker := wasmtime.NewLinker(engine)
	if err := linker.DefineWasi(); err != nil {
		return "", err
	}

	// 2. compile and instantiate
	module, err := wasmtime.NewModuleFromFile(engine, guest)
	if err != nil {
		return "", err
	}
	instance, err := linker.Instantiate(store, module)
	if err != nil {
		if isCleanExit(err) {
			return "WASI command exited 0", nil
		}
		return "", err
	}

	// 3. WASI command
	if start := instance.GetFunc(store, "_start"); start != nil {
		if _, err := start.Call(store); err != nil && !isCleanExit(err) {
			return "", err
		}
		return "WASI command exited 0", nil
	}

	// 4. reactor
	if init := instance.GetFunc(store, "_initialize"); init != nil {
		if _, err := init.Call(store); err != nil {
			return "", err
		}
	}
	add := instance.GetFunc(store, "add")
	fib := instance.GetFunc(store, "fib")
	if add == nil || fib == nil {
		return "", fmt.Errorf("missing export: add and fib are both required")
	}
	sum, err := add.Call(store, int32(20), int32(22))
	if err != nil {
		return "", err
	}
	fibv, err := fib.Call(store, int32(10))
	if err != nil {
		return "", err
	}
	if sum != int32(expectAdd) || fibv != int32(expectFib) {
		return "", fmt.Errorf("add(20,22)=%v (want %d) fib(10)=%v (want %d)", sum, expectAdd, fibv, expectFib)
	}
	return fmt.Sprintf("add(20,22)=%d fib(10)=%d", sum, fibv), nil
}

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintln(os.Stderr, "usage: go-host <guest.wasm>")
		os.Exit(2)
	}
	guest := os.Args[1]
	msg, err := run(guest)
	if err != nil {
		fmt.Fprintf(os.Stderr, "FAIL %s: %v\n", guest, err)
		os.Exit(1)
	}
	fmt.Printf("PASS %s: %s\n", guest, msg)
}
