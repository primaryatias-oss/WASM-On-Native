// Development helper: print the imports and exports of .wasm files.
//   node --no-warnings tools/inspect.mjs build/guests/*.wasm
import { readFile } from "node:fs/promises";

for (const file of process.argv.slice(2)) {
  const module = await WebAssembly.compile(await readFile(file));
  const imports = WebAssembly.Module.imports(module).map((i) => `${i.module}.${i.name}`);
  const exports = WebAssembly.Module.exports(module).map((e) => e.name);
  console.log(`${file}\n  imports: ${imports.join(", ") || "(none)"}\n  exports: ${exports.join(", ")}`);
}
