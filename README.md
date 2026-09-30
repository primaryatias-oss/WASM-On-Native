# WASM-On-Native

Run WebAssembly emitted by **8 languages** on top of native programs written in **5 languages**:
40 host × guest combinations, all driven by one WebAssembly runtime, [Wasmtime](https://wasmtime.dev).

```
NATIVE_LANGUAGES = {C, Nim, Go, Rust, Zig}                 (hosts: native programs that embed a runtime)
WASM_LANGUAGES   = NATIVE_LANGUAGES ∪ {OCaml, Haskell, F*} (guests: source languages compiled to .wasm)
```

Every guest exposes the same tiny contract, every host runs the same algorithm, so the 40 cells
are directly comparable and each source file stays short enough to read in a minute. Copy the
host of your language and the build script of the guest language you care about.

> **Status: read [Status and known risks](#status-and-known-risks) first.** The C and Go guests
> were built and checked. The rest of the code follows the documented workflows of each toolchain
> but had not been compiled when this repo was written; the CI workflow is its first real run.

## Quick start

```bash
scripts/setup-wasmtime.sh     # Wasmtime C API for the C, Nim and Zig hosts
scripts/build-guests.sh       # or: scripts/build-guests.sh c go rust   (only what you have installed)
scripts/build-hosts.sh        # or: scripts/build-hosts.sh rust
scripts/run-matrix.sh         # runs every built host against every built guest
```

A missing toolchain only skips its row/column: `run-matrix.sh` prints `skip` for cells whose host
or guest was not built, `PASS`/`FAIL` for the rest, and exits non-zero if any cell failed
(`STRICT=1` also fails on skips). Restrict the run with `HOSTS="rust go" GUESTS="c zig"`.

Expected output shape:

```
| guest \ host |  c   | nim  |  go  | rust | zig  |
|---|:---:|:---:|:---:|:---:|:---:|
| c            | PASS | PASS | PASS | PASS | PASS |
| nim          | PASS | ...
```

## Which library brings a WASM runtime to the native code

**Wasmtime**, the Bytecode Alliance runtime, version 49.x. One runtime for all five hosts means the
only thing that changes across a row is the host language, and the only thing that changes across a
column is the guest language.

| Host | How Wasmtime is embedded | Where the binding comes from |
|---|---|---|
| **C** | the C API (`wasm.h` + `wasmtime.h`, `libwasmtime`) | official prebuilt release tarball, fetched by `scripts/setup-wasmtime.sh` |
| **Rust** | the `wasmtime` and `wasmtime-wasi` crates | official, from crates.io |
| **Go** | [`wasmtime-go`](https://github.com/bytecodealliance/wasmtime-go) v49 (cgo, ships the C API) | official, `go get` |
| **Zig** | the same C API, imported with `zig translate-c` (no hand-written bindings) | official C API, no Zig-specific package |
| **Nim** | the same C API, declared with `importc` + `header: "wasmtime.h"` (layouts come from the C compiler) | official C API, no Nim-specific package |

Why Wasmtime rather than a smaller runtime:

- **Feature coverage.** The OCaml guest is compiled by `wasm_of_ocaml`, which emits WebAssembly GC,
  exception handling (`exnref`) and tail calls. The Haskell and Go guests need WASI. Wasmtime
  implements all of these and, in the 49.x line, turns GC, exceptions, tail calls and typed
  function references on by default. (The hosts still enable them explicitly, so the requirement
  is visible in the code and older Wasmtime versions keep working.)
- **Reach.** Official bindings exist for three of the five host languages, and the stable C API
  covers the other two without any third-party glue.
- **Standards first.** New proposals and WASI versions land here early, which matters when guests
  come from bleeding-edge toolchains.

### Other popular runtimes

Feature claims change quickly; check each project's current status before relying on a row.

| Runtime | Written in | Good at | Watch out for |
|---|---|---|---|
| **[Wasmtime](https://wasmtime.dev)** (used here) | Rust | Most complete standards support (GC, exceptions, tail calls, component model, WASI 0.2); Cranelift JIT/AOT, Winch baseline compiler, Pulley interpreter; heavily fuzzed; official Rust, C/C++, Go, Python and .NET embeddings | Large binary and slow build if compiled from source; Go binding needs cgo; JIT wants executable memory (Pulley is the portable fallback) |
| **[Wasmer](https://wasmer.io)** | Rust | Choice of backends (Singlepass, Cranelift, LLVM); embeddings for many languages; WASIX adds POSIX-style threads and sockets | WASIX is Wasmer-specific, not a standard; check that the proposals you need (GC, exceptions) are supported by the backend you pick; some language SDKs are less actively maintained |
| **[WasmEdge](https://wasmedge.org)** | C++ | Cloud-native/edge focus; LLVM AOT; extensions for networking and AI inference; Kubernetes/container integrations; C API plus Rust, Go, Java, Python SDKs | Smaller community; useful extras are non-standard host extensions; AOT drags in an LLVM dependency |
| **[WAMR](https://github.com/bytecodealliance/wasm-micro-runtime)** | C | Tiny footprint; interpreter, fast JIT, LLVM JIT and AOT modes; embedded and RTOS targets; GC support | The C embedding API is lower level than Wasmtime's; available features depend on build flags |
| **[wasm3](https://github.com/wasm3/wasm3)** | C | Very small and portable interpreter, no JIT (works where JIT is forbidden, e.g. iOS or microcontrollers), trivial to embed | Development has largely stopped; no GC or modern exception handling, so it cannot run this repo's OCaml guest; interpreter speed |
| **[wazero](https://wazero.io)** | Go | Zero dependencies and no cgo: `go get` and cross-compile anywhere; compiler and interpreter; solid spec test coverage | Go hosts only; newer proposals such as GC and exception handling are not there, so no OCaml guest; slower than Cranelift-class JITs |
| **[Wasmi](https://github.com/wasmi-labs/wasmi)** | Rust | Pure-Rust interpreter, `no_std`, fast startup, small; used where JIT is unacceptable (smart contracts, embedded); has a wasm-c-api compatible C API | Interpreter throughput; fewer proposals than Wasmtime |
| **V8 / Node.js / browsers** | C++ | Best when the host is JavaScript; earliest GC/exception support | Not an embeddable native library for arbitrary languages; the JS glue that some toolchains generate is what the guests here deliberately avoid |

Higher-level option: [Extism](https://extism.org) builds a plugin framework (host SDKs for many
languages, guest PDKs) on top of a runtime; it trades the raw export/import model shown here for
convenience.

## The guest contract

Every guest implements the same two functions on 32-bit integers, with wrapping arithmetic:

| Export | Meaning | Check value |
|---|---|---|
| `add(i32, i32) -> i32` | `a + b` | `add(20, 22) == 42` |
| `fib(i32) -> i32` | n-th Fibonacci number, `fib(0)=0`, `fib(1)=1` | `fib(10) == 55` |

Two module shapes exist, because two kinds of toolchain exist:

- **Reactor (library).** Exports `add` and `fib`; may also export `_initialize` (WASI reactors do).
  Used by C, Nim, Go, Rust, Zig, Haskell and F*.
- **Command (program).** Exports `_start`; it computes the same values itself, prints them and exits
  with status 0 only if they are correct. Used by OCaml, because `wasm_of_ocaml` produces whole
  programs.

## The host algorithm

All five hosts implement exactly this, so you can diff them against each other:

1. Create an engine with GC, exceptions, tail calls and function references enabled, a store with
   WASI (stdout/stderr inherited) and a linker that provides WASI.
2. Compile and instantiate the guest. (A WASI `proc_exit(0)` at this point counts as success.)
3. If the guest exports `_start`: call it. Returning normally or exiting with status 0 is a pass.
4. Otherwise: call `_initialize` if it exists, then call `add(20, 22)` and `fib(10)` and compare with
   `42` and `55`.

Hosts print `PASS <guest>: ...` and exit 0, or print `FAIL <guest>: ...` to stderr and exit 1.

## How each guest is built

| Guest | Toolchain | Target / route | Module | Build script |
|---|---|---|---|---|
| **C** | clang + wasm-ld | `--target=wasm32 -nostdlib`, no libc, no WASI | reactor | [`guests/c`](guests/c) |
| **Rust** | rustc | `wasm32-unknown-unknown`, `#![no_std]` cdylib | reactor | [`guests/rust`](guests/rust) |
| **Zig** | zig | `wasm32-freestanding`, `-fno-entry -rdynamic` | reactor | [`guests/zig`](guests/zig) |
| **Go** | Go ≥ 1.24 | `GOOS=wasip1 GOARCH=wasm -buildmode=c-shared` with `//go:wasmexport` | WASI reactor | [`guests/go`](guests/go) |
| **Nim** | Nim ≥ 2 + wasi-sdk | Nim → C → wasi-sdk clang, `wasm32-wasip1`, `-mexec-model=reactor` | WASI reactor | [`guests/nim`](guests/nim) |
| **Haskell** | GHC wasm backend (`wasm32-wasi-ghc`, via ghc-wasm-meta) | `foreign export ccall`, `-no-hs-main -optl-mexec-model=reactor` | WASI reactor | [`guests/haskell`](guests/haskell) |
| **OCaml** | `wasm_of_ocaml` with the WASI target | bytecode → WasmGC + `exnref` + tail calls, `--enable wasi` | WASI command | [`guests/ocaml`](guests/ocaml) |
| **F\*** | F\* + KaRaMeL + wasi-sdk | F\* → Low\*/KaRaMeL → C → wasi-sdk clang | WASI reactor | [`guests/fstar`](guests/fstar) |

Notes that save time:

- Go and Haskell import `wasi_snapshot_preview1` (and Nim and F\* do too when their libc pulls in
  WASI calls), which is why every host defines WASI. Reactors must have `_initialize` called once
  before any other export.
- The C, Rust and Zig guests import nothing at all, which makes them the simplest to debug.
- OCaml has no released WASI backend yet (see below), and F\* has no WebAssembly backend of its own,
  hence the C detour through KaRaMeL.

## Repository layout

```
guests/<lang>/    guest source + build.sh  -> build/guests/<lang>.wasm
hosts/<lang>/     host source  + build.sh  -> build/hosts/<lang>-host
scripts/          env.sh (versions), setup-*.sh (toolchain downloads), build-*.sh, run-matrix.sh
tools/            node-check.mjs: checks a guest against the contract with Node, no Wasmtime needed
.github/workflows/matrix.yml   builds everything and runs the 5 x 8 matrix, one job per language
```

Versions live in one place, [`scripts/env.sh`](scripts/env.sh) (Wasmtime 49.0.1, wasi-sdk 25).
To check a single guest without building any host: `node --no-warnings tools/node-check.mjs build/guests/c.wasm`.

## Status and known risks

Be honest about what has been exercised:

| Piece | State when this repo was written |
|---|---|
| C guest, Go guest | Built with the scripts here and checked against the contract with `tools/node-check.mjs` (passes). |
| `scripts/run-matrix.sh`, `build-*.sh`, workflow YAML | Logic exercised locally (table, skip, fail, strict, missing toolchains); YAML parsed. |
| Rust, Zig, Nim, Haskell, OCaml, F\* guests | Written to each toolchain's documented workflow, **not compiled yet**. |
| All five hosts | Written against the Wasmtime 49 APIs, **not compiled against Wasmtime yet** (the authoring sandbox could not download Wasmtime, crates, Go modules or the language toolchains). Only syntax/type-checked: the C host against a stand-in header, the Go and Rust hosts parsed. |

The CI workflow is therefore the first end-to-end run. Where I expect trouble, in order:

1. **OCaml** – the WASI target of `wasm_of_ocaml` is still an open pull request
   ([ocsigen/js_of_ocaml#1831](https://github.com/ocsigen/js_of_ocaml/pull/1831)), so
   `scripts/setup-wasm-of-ocaml-wasi.sh` builds that PR from source. Its own notes call it a
   prototype and show `wasmtime -W=all-proposals=y`; if the default Wasmtime configuration in the
   hosts is not enough, that is the flag to mirror. When the PR ships, replace the script with
   `opam install wasm_of_ocaml-compiler`.
2. **F\*** – the KaRaMeL build target and header paths in `scripts/setup-fstar.sh` and
   `guests/fstar/build.sh` may need adjusting for your F\*/KaRaMeL versions.
3. **Nim** – `--cpu:wasm32 --os:linux` with wasi-sdk's clang is the community-documented route, not an
   official one; the guest and the `importc` bindings of the host are the least-trodden code here.
4. **Haskell** – the reactor is initialised by `_initialize` per the GHC user guide; if your GHC version
   also needs `hs_init`, export it with `-optl-Wl,--export=hs_init` and call it from the host after
   `_initialize`.
5. **Zig 0.16** – flags such as `-femit-bin`, `-rpath` and `zig translate-c` are stable across recent
   releases, but this is untested on 0.16.0 specifically.
6. **Rust host** – `wasmtime_wasi::p1` and `I32Exit` are the current names; they have moved between
   releases before.

Please open an issue or fix the failing cell; each cell is one `host` + one `guest` build script.

## Extending

- **New guest language:** add `guests/<lang>/build.sh` that writes `build/guests/<lang>.wasm`, add the
  name to `WASM_LANGUAGES` in `scripts/env.sh`, and add a row to the workflow matrix.
- **New host language:** add `hosts/<lang>/build.sh` that writes `build/hosts/<lang>-host`, implement the
  four-step host algorithm above, add the name to `NATIVE_LANGUAGES`.
- **Next steps beyond this repo:** host imports (guest calling back into the host), passing strings
  through linear memory, the component model (`wasm32-wasip2`, WIT), fuel/epoch limits for sandboxing.

## License

See [LICENSE](LICENSE).
