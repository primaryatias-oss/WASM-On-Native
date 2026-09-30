// Development helper: write tiny hand-assembled WebAssembly modules that exercise the
// success and failure paths of the hosts. No toolchain is needed, only Node.
//
//   node tools/make-test-guests.mjs build/test-guests
//
// Each file name starts with the outcome every host must report: "pass-" or "fail-".
// scripts/selftest.sh runs every built host against every module and checks that.
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const I32 = 0x7f;
const leb = (n) => {
  const out = [];
  do {
    let b = n & 0x7f;
    n >>>= 7;
    out.push(n ? b | 0x80 : b);
  } while (n);
  return out;
};
const vec = (items) => [...leb(items.length), ...items.flat()];
const name = (s) => [...leb(s.length), ...Buffer.from(s)];
const section = (id, body) => [id, ...leb(body.length), ...body];

const op = {
  unreachable: [0x00],
  end: [0x0b],
  call: (f) => [0x10, ...leb(f)],
  localGet: (i) => [0x20, ...leb(i)],
  i32Const: (n) => [0x41, ...leb(n)], // only used with small non-negative values
  i32Add: [0x6a],
};

// A module is described by plain data:
//   types:   [[params], [results]] pairs, valtypes are single bytes
//   imports: [module, field, typeIndex] (functions only; they take the first function indexes)
//   funcs:   [typeIndex, bodyBytes] for each defined function
//   exports: [exportName, functionIndex]
//   start:   optional function index
//   memory:  true to define one memory and export it as "memory" (WASI requires that export
//            from every module that calls into WASI, even for proc_exit)
function build({ types, imports = [], funcs, exports, start, memory = false }) {
  const bytes = [0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00];
  bytes.push(...section(1, vec(types.map(([p, r]) => [0x60, ...vec(p.map((t) => [t])), ...vec(r.map((t) => [t]))]))));
  if (imports.length) {
    bytes.push(...section(2, vec(imports.map(([m, f, t]) => [...name(m), ...name(f), 0x00, ...leb(t)]))));
  }
  bytes.push(...section(3, vec(funcs.map(([t]) => leb(t)))));
  if (memory) bytes.push(...section(5, vec([[0x00, 0x01]]))); // one memory, min 1 page
  const allExports = exports.map(([n, f]) => [...name(n), 0x00, ...leb(f)]);
  if (memory) allExports.push([...name("memory"), 0x02, 0x00]);
  bytes.push(...section(7, vec(allExports)));
  if (start !== undefined) bytes.push(...section(8, leb(start)));
  bytes.push(...section(10, vec(funcs.map(([, body]) => {
    const code = [0x00, ...body, ...op.end]; // no locals
    return [...leb(code.length), ...code];
  }))));
  return Buffer.from(bytes);
}

// Shared pieces. Type indexes: 0 = (i32,i32)->i32, 1 = (i32)->i32, 2 = ()->(), 3 = (i32)->()
const types = [[[I32, I32], [I32]], [[I32], [I32]], [[], []], [[I32], []]];
const addOk = [0, [...op.localGet(0), ...op.localGet(1), ...op.i32Add]];
const addOffByOne = [0, [...op.localGet(0), ...op.localGet(1), ...op.i32Add, ...op.i32Const(1), ...op.i32Add]];
const addTraps = [0, op.unreachable];
const fib55 = [1, op.i32Const(55)]; // right for fib(10), which is all the hosts ask
const fibZero = [1, op.i32Const(0)];
const procExit = ["wasi_snapshot_preview1", "proc_exit", 3];
const exitWith = (code) => [2, [...op.i32Const(code), ...op.call(0)]]; // call the import (index 0)

const modules = {
  // --- reactors: exports add and fib -------------------------------------------------------
  "pass-reactor": build({ types, funcs: [addOk, fib55], exports: [["add", 0], ["fib", 1]] }),
  "pass-reactor-initialize": build({
    types,
    funcs: [addOk, fib55, [2, []]],
    exports: [["add", 0], ["fib", 1], ["_initialize", 2]],
  }),
  "fail-reactor-wrong-add": build({ types, funcs: [addOffByOne, fib55], exports: [["add", 0], ["fib", 1]] }),
  "fail-reactor-wrong-fib": build({ types, funcs: [addOk, fibZero], exports: [["add", 0], ["fib", 1]] }),
  "fail-reactor-missing-fib": build({ types, funcs: [addOk], exports: [["add", 0]] }),
  "fail-reactor-missing-add": build({ types, funcs: [fib55], exports: [["fib", 0]] }),
  "fail-reactor-wrong-signature": build({ types, funcs: [[2, []], fib55], exports: [["add", 0], ["fib", 1]] }),
  "fail-reactor-add-traps": build({ types, funcs: [addTraps, fib55], exports: [["add", 0], ["fib", 1]] }),
  "fail-reactor-initialize-traps": build({
    types,
    funcs: [addOk, fib55, [2, op.unreachable]],
    exports: [["add", 0], ["fib", 1], ["_initialize", 2]],
  }),
  // --- WASI commands: exports _start -------------------------------------------------------
  "pass-command-exit0": build({ types, imports: [procExit], funcs: [exitWith(0)], exports: [["_start", 1]], memory: true }),
  "pass-command-returns": build({ types, funcs: [[2, []]], exports: [["_start", 0]] }),
  "fail-command-exit3": build({ types, imports: [procExit], funcs: [exitWith(3)], exports: [["_start", 1]], memory: true }),
  "fail-command-traps": build({ types, funcs: [[2, op.unreachable]], exports: [["_start", 0]] }),
  // --- exit or trap while instantiating (a wasm `start` function) --------------------------
  "pass-start-exit0": build({ types, imports: [procExit], funcs: [exitWith(0)], exports: [], start: 1, memory: true }),
  "fail-start-exit1": build({ types, imports: [procExit], funcs: [exitWith(1)], exports: [], start: 1, memory: true }),
  "fail-start-traps": build({ types, funcs: [[2, op.unreachable]], exports: [], start: 0 }),
  // --- not a module ------------------------------------------------------------------------
  "fail-garbage": Buffer.from("this is not WebAssembly\n"),
  "fail-empty": Buffer.alloc(0),
  "fail-truncated": build({ types, funcs: [addOk, fib55], exports: [["add", 0], ["fib", 1]] }).subarray(0, 30),
};

const outDir = process.argv[2] ?? "build/test-guests";
mkdirSync(outDir, { recursive: true });
for (const [n, bytes] of Object.entries(modules)) writeFileSync(join(outDir, `${n}.wasm`), bytes);
console.log(`wrote ${Object.keys(modules).length} test guests to ${outDir}`);
