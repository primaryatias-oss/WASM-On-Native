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

> **Status:** all 40 cells pass on Linux x86-64 with the toolchain versions listed in
> [Verified toolchain versions](#verified-toolchain-versions), and each host passes a self-test that
> proves it also *rejects* broken guests. See [Verification](#verification) for exactly what was run.

## Quick start

Install the toolchains of the languages you care about (see the table below), then:

```bash
scripts/setup-wasmtime.sh     # Wasmtime C API for the C, Nim and Zig hosts
scripts/build-guests.sh       # or: scripts/build-guests.sh c go rust   (only what you have installed)
scripts/build-hosts.sh        # or: scripts/build-hosts.sh rust
scripts/run-matrix.sh         # runs every built host against every built guest
scripts/selftest.sh           # checks that the hosts also reject bad guests
```

A missing toolchain only skips its row/column: `run-matrix.sh` prints `skip` for cells whose host
or guest was not built, `PASS`/`FAIL` for the rest, and exits non-zero if any cell failed
(`STRICT=1` also fails on skips). Restrict the run with `HOSTS="rust go" GUESTS="c zig"`.

Result on the machine this was developed on:

```
| guest \ host | c | nim | go | rust | zig |
|---|:---:|:---:|:---:|:---:|:---:|
| c | PASS | PASS | PASS | PASS | PASS |
| nim | PASS | PASS | PASS | PASS | PASS |
| go | PASS | PASS | PASS | PASS | PASS |
| rust | PASS | PASS | PASS | PASS | PASS |
| zig | PASS | PASS | PASS | PASS | PASS |
| ocaml | PASS | PASS | PASS | PASS | PASS |
| haskell | PASS | PASS | PASS | PASS | PASS |
| fstar | PASS | PASS | PASS | PASS | PASS |
```

### What you need per language

| Language | Role | Toolchain | Installed by |
|---|---|---|---|
| C | host + guest | a C compiler; `clang` + `wasm-ld` for the guest (`apt install clang lld`) | Wasmtime C API: `scripts/setup-wasmtime.sh` |
| Rust | host + guest | Rust **≥ 1.96** (the `wasmtime` 49 crate needs it) + `rustup target add wasm32-unknown-unknown` | crates.io |
| Go | host + guest | Go **≥ 1.24** (`//go:wasmexport`), a C compiler for cgo | `go get` (wasmtime-go v49) |
| Zig | host + guest | Zig 0.16 | Wasmtime C API script |
| Nim | host + guest | Nim ≥ 2.2 + wasi-sdk for the guest | `scripts/setup-wasi-sdk.sh`, Wasmtime C API script |
| OCaml | guest | OCaml 4.14 – 5.5, opam, `wasm_of_ocaml` **≥ 6.4.0**, Binaryen ≥ 119 | `scripts/setup-wasm-of-ocaml.sh` |
| Haskell | guest | GHC's WebAssembly backend (`wasm32-wasi-ghc`), about 5 GB | `scripts/setup-ghc-wasm.sh` |
| F\* | guest | F\* + KaRaMeL + Z3 (one release tarball) + wasi-sdk | `scripts/setup-fstar.sh`, `scripts/setup-wasi-sdk.sh` |

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
  exception handling and tail calls. The Haskell, Go, Nim and OCaml guests need WASI. Wasmtime
  lists GC, exceptions, tail calls, function references and the component model as
  [Tier 1](https://github.com/bytecodealliance/wasmtime/blob/main/docs/stability-tiers.md).
  We checked that Wasmtime 49 runs every guest, the WasmGC-based OCaml one included, with its
  **default** configuration. The hosts still switch GC, exceptions, tail calls and function
  references on explicitly so the requirement is visible in the code and older versions keep working.
- **Reach.** Official bindings exist for three of the five host languages, and the stable C API
  covers the other two without any third-party glue.
- **Standards first.** New proposals and WASI versions land here early, which matters when guests
  come from bleeding-edge toolchains.

### Other popular runtimes

Feature claims change quickly; check each project's current status before relying on a row. The
proposal statements below come from each project's own README or docs at the time of writing.

| Runtime | Written in | Good at | Watch out for |
|---|---|---|---|
| **[Wasmtime](https://wasmtime.dev)** (used here) | Rust | Most complete standards support (GC, exceptions, tail calls, function references, component model are Tier 1); Cranelift JIT/AOT, Winch baseline compiler, Pulley interpreter; heavily fuzzed; official Rust, C/C++, Go, Python and .NET embeddings | Large binary and slow build if compiled from source (the Rust host takes minutes to compile); the crates track recent Rust releases; Go binding needs cgo; JIT wants executable memory (Pulley is the portable fallback) |
| **[Wasmer](https://wasmer.io)** | Rust | Choice of compiler backends (Singlepass, Cranelift, LLVM); embeddings for many languages; WASIX adds POSIX-style threads and sockets | WASIX is Wasmer-specific, not a standard; exception handling is available on Cranelift and LLVM but was still in progress on Singlepass, so the backend you pick decides what runs; some language SDKs are less actively maintained |
| **[WasmEdge](https://wasmedge.org)** | C++ | Cloud-native/edge focus (plug-ins, serverless, edge nodes) and AI-inference extensions; C, Go and Rust SDKs; LLVM-based AOT | Smaller community; the useful extras (sockets, databases, AI) are non-standard host extensions; check its proposal table for GC before choosing it for OCaml-style guests |
| **[WAMR](https://github.com/bytecodealliance/wasm-micro-runtime)** | C | Tiny footprint (tens of KB on a Cortex-M4F); interpreter, Fast JIT, LLVM JIT and AOT modes; embedded and RTOS targets; supports GC, exception handling, tail calls and threads | The C embedding API is lower level than Wasmtime's; available features depend on build flags |
| **[wasm3](https://github.com/wasm3/wasm3)** | C | Very small and portable interpreter, no JIT (works where JIT is forbidden, e.g. iOS or microcontrollers), trivial to embed; supports tail calls and exceptions | In minimal-maintenance mode; **no GC**, so it cannot run this repo's OCaml guest; interpreter speed |
| **[wazero](https://wazero.io)** | Go | Zero dependencies and no cgo: `go get` and cross-compile anywhere; compiler and interpreter; Wasm 2.0 compliant, with exceptions and typed references arriving in recent releases | Go hosts only; slower than Cranelift-class JITs; confirm GC support before pointing it at the OCaml guest |
| **[Wasmi](https://github.com/wasmi-labs/wasmi)** | Rust | Pure-Rust interpreter, `no_std`, small and fast to start; used where JIT is unacceptable (smart contracts, embedded); security-audited; official wasm-c-api C bindings | Interpreter throughput; tail calls yes, but GC and exception handling are still in development, so no OCaml guest |
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

Hosts print `PASS <guest>: ...` and exit 0, or print `FAIL <guest>: ...` to stderr and exit 1
(usage errors exit 2). `scripts/selftest.sh` checks all of that against deliberately broken modules.

## How each guest is built

| Guest | Toolchain | Target / route | Module | Build script |
|---|---|---|---|---|
| **C** | clang + wasm-ld | `--target=wasm32 -nostdlib`, no libc, no WASI | reactor | [`guests/c`](guests/c) |
| **Rust** | rustc | `wasm32-unknown-unknown`, `#![no_std]` cdylib | reactor | [`guests/rust`](guests/rust) |
| **Zig** | zig | `wasm32-freestanding`, `-fno-entry -rdynamic` | reactor | [`guests/zig`](guests/zig) |
| **Go** | Go ≥ 1.24 | `GOOS=wasip1 GOARCH=wasm -buildmode=c-shared` with `//go:wasmexport` | WASI reactor | [`guests/go`](guests/go) |
| **Nim** | Nim ≥ 2.2 + wasi-sdk | Nim → C → wasi-sdk clang, `wasm32-wasip1`, `-d:useMalloc`, `-mexec-model=reactor` | WASI reactor | [`guests/nim`](guests/nim) |
| **Haskell** | GHC wasm backend (`wasm32-wasi-ghc`) | `foreign export ccall`, `-no-hs-main -optl-mexec-model=reactor`, plus `boot.c` that starts the RTS | WASI reactor | [`guests/haskell`](guests/haskell) |
| **OCaml** | `wasm_of_ocaml` ≥ 6.4.0 | bytecode → WasmGC + exceptions + tail calls, `--enable wasi` | WASI command | [`guests/ocaml`](guests/ocaml) |
| **F\*** | F\* + KaRaMeL + wasi-sdk | F\* verifies → Low\*/KaRaMeL → C → wasi-sdk clang | WASI reactor | [`guests/fstar`](guests/fstar) |

### Gotchas we hit (so you do not have to)

- **Rust host: Wasmtime 49 needs Rust 1.96+.** Older toolchains fail at dependency resolution;
  `hosts/rust/Cargo.toml` declares `rust-version` so cargo says so.
- **Nim → WASI: use `-d:useMalloc`.** Nim's own allocator calls `mmap`, which WASI does not have
  (wasi-libc stops the C compile with an `#error`). `-d:useMalloc` hands allocation to wasi-libc.
  Nim has no WASI target of its own, so the route is `--os:linux` + wasi-sdk's clang.
- **Haskell reactors must call `hs_init`.** Without it every export dies with
  `RTS is not initialised; call hs_init() first`. The standard recipe makes each embedder export
  and call `hs_init(0, 0)` after `_initialize`. `guests/haskell/boot.c` instead calls it from a C
  constructor, which runs inside `_initialize`, so the five hosts stay language-agnostic.
  GHC also drops the object file of a C source next to that source, so the build script compiles
  a copy in `build/`.
- **Every module that calls into WASI must export `memory`,** even if it only calls `proc_exit`.
  Wasmtime rejects the call otherwise with `missing required memory export`
  (`tools/make-test-guests.mjs` had to learn this).
- **OCaml → WASI needs `wasm_of_ocaml` ≥ 6.4.0.** The WASI backend was an open pull request for a
  long time; it is in the 6.4 releases. It emits a WASI *command* (`_start`), not a library, and
  needs Binaryen ≥ 119 (`wasm-opt`, `wasm-merge`) at build time, newer than most distro packages.
- **F\* extraction needs the module checked first.** Current F\* refuses
  `--codegen krml` on a module that is not in the checked-file cache, so `guests/fstar/build.sh`
  verifies with `--cache_checked_modules` and extracts in a second call. The F\* release tarball
  bundles KaRaMeL (`krml`), its C headers and Z3, so no opam is needed.
- **Go reactors** need `-buildmode=c-shared` and `//go:wasmexport` (Go 1.24+); the module then exports
  `_initialize`, which the host must call once before anything else.

## Repository layout

```
guests/<lang>/    guest source + build.sh  -> build/guests/<lang>.wasm
hosts/<lang>/     host source  + build.sh  -> build/hosts/<lang>-host
scripts/          env.sh (versions), setup-*.sh (toolchain downloads), build-*.sh,
                  run-matrix.sh (the 5 x 8 table), selftest.sh (good and bad guests)
tools/            node-check.mjs      checks a guest against the contract with Node, no Wasmtime needed
                  inspect.mjs         prints the imports and exports of .wasm files
                  make-test-guests.mjs  writes the hand-made good/bad modules used by selftest.sh
.github/workflows/matrix.yml   builds everything and runs the 5 x 8 matrix, one job per language
```

Versions live in one place, [`scripts/env.sh`](scripts/env.sh). To check a single guest without
building any host: `node --no-warnings tools/node-check.mjs build/guests/c.wasm`.

## Verification

What has been run, on Ubuntu 24.04 x86-64, for this repository:

- **Every host builds and runs against every guest** (`scripts/run-matrix.sh`, all 40 cells `PASS`).
- **Every guest is also checked by Node's WASI** (`tools/node-check.mjs`) and its imports and exports
  are inspected (`tools/inspect.mjs`), so a host bug cannot hide a guest bug.
- **Negative tests** (`scripts/selftest.sh`): each host is run against 19 hand-assembled modules that
  must pass (a correct reactor, a command exiting 0, exit 0 during instantiation, ...) or must fail
  (wrong sum, wrong `fib`, missing export, wrong signature, trap in an export, trap in
  `_initialize`, non-zero exit, trap or exit while instantiating, garbage, empty and truncated
  files, missing file, no arguments). Every `fail-` module differs from a `pass-` module in one
  detail, so a failure can only come from that detail.
- **Default configuration:** a C host with the four proposal switches removed still runs all
  guests, including the WasmGC-based OCaml guest.
- **Fresh-clone and lock-file checks:** a clean clone of the branch builds all 8 guests and 5 hosts and
  passes the strict matrix and self-test; the Rust host builds with `cargo build --locked` and the Go
  host with an empty module cache and `-mod=readonly`, so the committed `Cargo.lock` and `go.sum` are
  complete.
- **CI:** [`.github/workflows/matrix.yml`](.github/workflows/matrix.yml) runs on fresh `ubuntu-24.04`
  runners: eight guest jobs (each installs its own toolchain, builds the guest and checks it with
  Node), then five host jobs that build the host, run `scripts/selftest.sh`, download the guests built
  on the *other* runners and run a `STRICT=1` matrix row. The last run passed all 13 jobs, including
  `wasm_of_ocaml` installed from opam on OCaml 5.3 and the 5 GB GHC install. Check the Actions tab
  for the current state.

### Verified toolchain versions

| Component | Version |
|---|---|
| Wasmtime (C API, `wasmtime` crate, `wasmtime-go`) | 49.0.1 / 49.x / v49.0.0 |
| Rust | 1.98.1 |
| Go | 1.24.7 |
| Zig | 0.16.0 |
| Nim | 2.2.13 (the 2.2 line) |
| wasi-sdk | 25 (clang 19.1.5) |
| GHC wasm backend | 9.12.4 (`wasm32-wasi-ghc`, ghc-wasm-meta flavour 9.12) |
| `wasm_of_ocaml` | 6.4.1 with Binaryen 123 (built from source on OCaml 4.14.1 for the local runs; installed from opam on OCaml 5.3 in CI) |
| F\* / KaRaMeL / Z3 | 2026.09.27 (bundled KaRaMeL and Z3) |
| Node.js (checker only) | 22 |

## Extending

- **New guest language:** add `guests/<lang>/build.sh` that writes `build/guests/<lang>.wasm`, add the
  name to `WASM_LANGUAGES` in `scripts/env.sh`, and add it to the workflow matrix.
- **New host language:** add `hosts/<lang>/build.sh` that writes `build/hosts/<lang>-host`, implement the
  four-step host algorithm above, add the name to `NATIVE_LANGUAGES`, and run `scripts/selftest.sh`.
- **Next steps beyond this repo:** host imports (guest calling back into the host), passing strings
  through linear memory, the component model (`wasm32-wasip2`, WIT), fuel/epoch limits for sandboxing.

## License

See [LICENSE](LICENSE).
