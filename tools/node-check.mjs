// Development helper: check a guest .wasm against the guest contract using Node's
// built-in WebAssembly + WASI. It is NOT one of the five native hosts; it exists so
// you can sanity-check a guest quickly without a Wasmtime build.
//
//   node --no-warnings tools/node-check.mjs build/guests/c.wasm [...more.wasm]
//
// Mirrors the host algorithm documented in the README:
//   1. instantiate with WASI available
//   2. if the module exports _start        -> run it as a command, success = exit status 0
//   3. otherwise, if it exports _initialize -> call it once
//   4. call add(20, 22) and fib(10) and compare with 42 and 55
import { readFile } from "node:fs/promises";
import { WASI } from "node:wasi";

let failed = 0;

for (const file of process.argv.slice(2)) {
  try {
    const bytes = await readFile(file);
    const wasi = new WASI({ version: "preview1", args: [], env: {}, returnOnExit: true });
    const { instance } = await WebAssembly.instantiate(bytes, {
      wasi_snapshot_preview1: wasi.wasiImport,
    });
    const ex = instance.exports;

    if (typeof ex._start === "function") {
      const code = wasi.start(instance);
      if (code !== 0) throw new Error(`_start exited with status ${code}`);
      console.log(`PASS ${file}: WASI command exited 0`);
      continue;
    }

    if (typeof ex._initialize === "function") wasi.initialize(instance);

    const sum = ex.add(20, 22);
    const fib = ex.fib(10);
    if (sum !== 42 || fib !== 55) {
      throw new Error(`add(20,22)=${sum} (want 42), fib(10)=${fib} (want 55)`);
    }
    console.log(`PASS ${file}: add(20,22)=${sum} fib(10)=${fib}`);
  } catch (err) {
    failed++;
    console.log(`FAIL ${file}: ${err.message}`);
  }
}

process.exit(failed ? 1 : 0);
