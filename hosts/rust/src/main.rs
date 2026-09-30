//! Native host written in Rust, embedding Wasmtime through the `wasmtime` crate.
//!
//! Usage: rust-host <guest.wasm>
//!
//! Every host in this repo implements the same algorithm (see README, "The host algorithm"):
//!   1. Create an engine with the WebAssembly proposals that OCaml/Haskell guests need
//!      (GC, exceptions, tail calls, typed function references) and a linker that provides WASI.
//!   2. Instantiate the guest.
//!   3. If it exports `_start` it is a WASI *command*: run it; exit status 0 means success.
//!   4. Otherwise it is a *reactor* (a library): call `_initialize` if present, then call
//!      add(20, 22) and fib(10) and compare against 42 and 55.

use std::process::ExitCode;

use wasmtime::{Config, Engine, Linker, Module, Store};
use wasmtime_wasi::p1::{self, WasiP1Ctx};
use wasmtime_wasi::{I32Exit, WasiCtxBuilder};

const EXPECT_ADD: i32 = 42;
const EXPECT_FIB: i32 = 55;

/// A WASI command finishes by calling proc_exit, which surfaces as an `I32Exit` error.
/// Status 0 is a normal, successful exit.
fn is_clean_exit(err: &wasmtime::Error) -> bool {
    err.downcast_ref::<I32Exit>().is_some_and(|e| e.0 == 0)
}

fn run(guest: &str) -> wasmtime::Result<Result<String, String>> {
    // 1. engine, store, linker with WASI
    let mut config = Config::new();
    config.wasm_function_references(true);
    config.wasm_gc(true);
    config.wasm_exceptions(true);
    config.wasm_tail_call(true);
    let engine = Engine::new(&config)?;

    let mut linker: Linker<WasiP1Ctx> = Linker::new(&engine);
    p1::add_to_linker_sync(&mut linker, |ctx| ctx)?;
    let wasi = WasiCtxBuilder::new().inherit_stdio().build_p1();
    let mut store = Store::new(&engine, wasi);

    // 2. compile and instantiate
    let module = Module::from_file(&engine, guest)?;
    let instance = match linker.instantiate(&mut store, &module) {
        Ok(instance) => instance,
        Err(e) if is_clean_exit(&e) => return Ok(Ok("WASI command exited 0".into())),
        Err(e) => return Err(e),
    };

    // 3. WASI command
    if let Some(start) = instance.get_func(&mut store, "_start") {
        return match start.call(&mut store, &mut [], &mut []) {
            Ok(()) => Ok(Ok("WASI command exited 0".into())),
            Err(e) if is_clean_exit(&e) => Ok(Ok("WASI command exited 0".into())),
            Err(e) => Err(e),
        };
    }

    // 4. reactor
    if let Some(init) = instance.get_func(&mut store, "_initialize") {
        init.call(&mut store, &mut [], &mut [])?;
    }
    let Ok(add) = instance.get_typed_func::<(i32, i32), i32>(&mut store, "add") else {
        return Ok(Err("missing or mistyped export: add".into()));
    };
    let Ok(fib) = instance.get_typed_func::<i32, i32>(&mut store, "fib") else {
        return Ok(Err("missing or mistyped export: fib".into()));
    };
    let sum = add.call(&mut store, (20, 22))?;
    let fibv = fib.call(&mut store, 10)?;

    if sum == EXPECT_ADD && fibv == EXPECT_FIB {
        Ok(Ok(format!("add(20,22)={sum} fib(10)={fibv}")))
    } else {
        Ok(Err(format!(
            "add(20,22)={sum} (want {EXPECT_ADD}) fib(10)={fibv} (want {EXPECT_FIB})"
        )))
    }
}

fn main() -> ExitCode {
    let Some(guest) = std::env::args().nth(1) else {
        eprintln!("usage: rust-host <guest.wasm>");
        return ExitCode::from(2);
    };
    match run(&guest) {
        Ok(Ok(msg)) => {
            println!("PASS {guest}: {msg}");
            ExitCode::SUCCESS
        }
        Ok(Err(msg)) => {
            eprintln!("FAIL {guest}: {msg}");
            ExitCode::FAILURE
        }
        Err(e) => {
            eprintln!("FAIL {guest}: {e:#}");
            ExitCode::FAILURE
        }
    }
}
