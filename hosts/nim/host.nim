# Native host written in Nim, embedding Wasmtime through its C API.
#
# Usage: nim-host <guest.wasm>
#
# Nim talks to C libraries with `importc`. The struct types below are declared with
# `header: "wasmtime.h"`, so their real layout comes from the C compiler; Nim only needs to
# know the field names it touches.
#
# Every host in this repo implements the same algorithm (see README, "The host algorithm"):
#   1. Create an engine with the WebAssembly proposals that OCaml/Haskell guests need
#      (GC, exceptions, tail calls, typed function references) and a linker that provides WASI.
#   2. Instantiate the guest.
#   3. If it exports _start it is a WASI *command*: run it; exit status 0 means success.
#   4. Otherwise it is a *reactor* (a library): call _initialize if present, then call
#      add(20, 22) and fib(10) and compare against 42 and 55.
import std/os

const
  expectAdd = 42'i32
  expectFib = 55'i32
  # from wasmtime/val.h and wasmtime/extern.h
  WASMTIME_I32 = 0'u8
  WASMTIME_EXTERN_FUNC = 0'u8

type
  WasmConfig {.importc: "wasm_config_t", header: "wasmtime.h", incompleteStruct.} = object
  WasmEngine {.importc: "wasm_engine_t", header: "wasmtime.h", incompleteStruct.} = object
  WasmTrap {.importc: "wasm_trap_t", header: "wasmtime.h", incompleteStruct.} = object
  WasiConfig {.importc: "wasi_config_t", header: "wasmtime.h", incompleteStruct.} = object
  WasmtimeStore {.importc: "wasmtime_store_t", header: "wasmtime.h", incompleteStruct.} = object
  WasmtimeContext {.importc: "wasmtime_context_t", header: "wasmtime.h", incompleteStruct.} = object
  WasmtimeLinker {.importc: "wasmtime_linker_t", header: "wasmtime.h", incompleteStruct.} = object
  WasmtimeModule {.importc: "wasmtime_module_t", header: "wasmtime.h", incompleteStruct.} = object
  WasmtimeError {.importc: "wasmtime_error_t", header: "wasmtime.h", incompleteStruct.} = object

  WasmByteVec {.importc: "wasm_byte_vec_t", header: "wasmtime.h".} = object
    size: csize_t
    data: ptr char

  WasmtimeFunc {.importc: "wasmtime_func_t", header: "wasmtime.h".} = object
  WasmtimeInstance {.importc: "wasmtime_instance_t", header: "wasmtime.h".} = object

  WasmtimeValUnion {.importc: "wasmtime_valunion_t", header: "wasmtime.h".} = object
    i32: int32
  WasmtimeVal {.importc: "wasmtime_val_t", header: "wasmtime.h".} = object
    kind: uint8
    `of`: WasmtimeValUnion

  WasmtimeExternUnion {.importc: "wasmtime_extern_union_t", header: "wasmtime.h".} = object
    `func`: WasmtimeFunc
  WasmtimeExtern {.importc: "wasmtime_extern_t", header: "wasmtime.h".} = object
    kind: uint8
    `of`: WasmtimeExternUnion

{.push importc, header: "wasmtime.h", cdecl.}
proc wasm_config_new(): ptr WasmConfig
proc wasmtime_config_wasm_function_references_set(c: ptr WasmConfig, enable: bool)
proc wasmtime_config_wasm_gc_set(c: ptr WasmConfig, enable: bool)
proc wasmtime_config_wasm_exceptions_set(c: ptr WasmConfig, enable: bool)
proc wasmtime_config_wasm_tail_call_set(c: ptr WasmConfig, enable: bool)
proc wasm_engine_new_with_config(c: ptr WasmConfig): ptr WasmEngine
proc wasmtime_store_new(e: ptr WasmEngine, data: pointer, finalizer: pointer): ptr WasmtimeStore
proc wasmtime_store_context(s: ptr WasmtimeStore): ptr WasmtimeContext
proc wasi_config_new(): ptr WasiConfig
proc wasi_config_inherit_stdout(c: ptr WasiConfig)
proc wasi_config_inherit_stderr(c: ptr WasiConfig)
proc wasmtime_context_set_wasi(ctx: ptr WasmtimeContext, wasi: ptr WasiConfig): ptr WasmtimeError
proc wasmtime_linker_new(e: ptr WasmEngine): ptr WasmtimeLinker
proc wasmtime_linker_define_wasi(l: ptr WasmtimeLinker): ptr WasmtimeError
proc wasmtime_module_new(e: ptr WasmEngine, wasm: ptr uint8, len: csize_t,
                         ret: ptr ptr WasmtimeModule): ptr WasmtimeError
proc wasmtime_linker_instantiate(l: ptr WasmtimeLinker, ctx: ptr WasmtimeContext,
                                 m: ptr WasmtimeModule, inst: ptr WasmtimeInstance,
                                 trap: ptr ptr WasmTrap): ptr WasmtimeError
proc wasmtime_instance_export_get(ctx: ptr WasmtimeContext, inst: ptr WasmtimeInstance,
                                  name: cstring, nameLen: csize_t,
                                  item: ptr WasmtimeExtern): bool
proc wasmtime_func_call(ctx: ptr WasmtimeContext, f: ptr WasmtimeFunc,
                        args: ptr WasmtimeVal, nargs: csize_t,
                        results: ptr WasmtimeVal, nresults: csize_t,
                        trap: ptr ptr WasmTrap): ptr WasmtimeError
proc wasmtime_error_message(e: ptr WasmtimeError, msg: ptr WasmByteVec)
proc wasmtime_error_delete(e: ptr WasmtimeError)
proc wasmtime_error_exit_status(e: ptr WasmtimeError, status: ptr cint): bool
proc wasm_trap_message(t: ptr WasmTrap, msg: ptr WasmByteVec)
proc wasm_trap_delete(t: ptr WasmTrap)
proc wasm_byte_vec_delete(v: ptr WasmByteVec)
{.pop.}

proc fail(guest, what: string, error: ptr WasmtimeError = nil, trap: ptr WasmTrap = nil): int =
  var text = "FAIL " & guest & ": " & what
  var msg: WasmByteVec
  if error != nil:
    wasmtime_error_message(error, addr msg)
    wasmtime_error_delete(error)
  elif trap != nil:
    wasm_trap_message(trap, addr msg)
    wasm_trap_delete(trap)
  if msg.size > 0:
    var detail = newString(int(msg.size))
    copyMem(addr detail[0], msg.data, int(msg.size))
    wasm_byte_vec_delete(addr msg)
    text.add ": " & detail
  stderr.writeLine text
  result = 1

# A WASI command finishes by calling proc_exit, which Wasmtime reports as an error carrying an
# exit status. Status 0 is a normal, successful exit.
proc isCleanExit(error: ptr WasmtimeError): bool =
  var status: cint
  error != nil and wasmtime_error_exit_status(error, addr status) and status == 0

proc getFunc(ctx: ptr WasmtimeContext, inst: var WasmtimeInstance, name: cstring,
             f: var WasmtimeFunc): bool =
  var item: WasmtimeExtern
  if not wasmtime_instance_export_get(ctx, addr inst, name, csize_t(len(name)), addr item):
    return false
  if item.kind != WASMTIME_EXTERN_FUNC:
    return false
  f = item.`of`.`func`
  true

proc callI32(ctx: ptr WasmtimeContext, f: var WasmtimeFunc, input: openArray[int32],
             output: var int32, guest, name: string): int =
  var args: array[2, WasmtimeVal]
  var res: WasmtimeVal
  for i, v in input:
    args[i].kind = WASMTIME_I32
    args[i].`of`.i32 = v
  var trap: ptr WasmTrap = nil
  let error = wasmtime_func_call(ctx, addr f, addr args[0], csize_t(input.len), addr res, 1, addr trap)
  if error != nil or trap != nil:
    return fail(guest, name, error, trap)
  if res.kind != WASMTIME_I32:
    return fail(guest, "result is not an i32")
  output = res.`of`.i32
  0

proc main(): int =
  if paramCount() != 1:
    stderr.writeLine "usage: nim-host <guest.wasm>"
    return 2
  let guest = paramStr(1)

  var wasm: string
  try:
    wasm = readFile(guest)
  except IOError:
    return fail(guest, "cannot read file")

  # 1. engine, store, linker with WASI
  let config = wasm_config_new()
  wasmtime_config_wasm_function_references_set(config, true)
  wasmtime_config_wasm_gc_set(config, true)
  wasmtime_config_wasm_exceptions_set(config, true)
  wasmtime_config_wasm_tail_call_set(config, true)
  let engine = wasm_engine_new_with_config(config) # takes ownership of config

  let store = wasmtime_store_new(engine, nil, nil)
  let ctx = wasmtime_store_context(store)

  let wasi = wasi_config_new()
  wasi_config_inherit_stdout(wasi)
  wasi_config_inherit_stderr(wasi)
  var error = wasmtime_context_set_wasi(ctx, wasi) # takes ownership
  if error != nil: return fail(guest, "set_wasi", error)

  let linker = wasmtime_linker_new(engine)
  error = wasmtime_linker_define_wasi(linker)
  if error != nil: return fail(guest, "define_wasi", error)

  # 2. compile and instantiate
  var module: ptr WasmtimeModule
  error = wasmtime_module_new(engine, cast[ptr uint8](unsafeAddr wasm[0]), csize_t(wasm.len), addr module)
  if error != nil: return fail(guest, "compile", error)

  var instance: WasmtimeInstance
  var trap: ptr WasmTrap = nil
  error = wasmtime_linker_instantiate(linker, ctx, module, addr instance, addr trap)
  if isCleanExit(error):
    echo "PASS ", guest, ": WASI command exited 0"
    return 0
  if error != nil or trap != nil: return fail(guest, "instantiate", error, trap)

  var f: WasmtimeFunc
  if getFunc(ctx, instance, "_start", f):
    # 3. WASI command
    error = wasmtime_func_call(ctx, addr f, nil, 0, nil, 0, addr trap)
    if isCleanExit(error) or (error == nil and trap == nil):
      if error != nil: wasmtime_error_delete(error)
      echo "PASS ", guest, ": WASI command exited 0"
      return 0
    return fail(guest, "_start", error, trap)

  # 4. reactor
  if getFunc(ctx, instance, "_initialize", f):
    error = wasmtime_func_call(ctx, addr f, nil, 0, nil, 0, addr trap)
    if error != nil or trap != nil: return fail(guest, "_initialize", error, trap)

  var sum, fibv: int32
  if not getFunc(ctx, instance, "add", f): return fail(guest, "missing export: add")
  var rc = callI32(ctx, f, [20'i32, 22'i32], sum, guest, "add")
  if rc != 0: return rc
  if not getFunc(ctx, instance, "fib", f): return fail(guest, "missing export: fib")
  rc = callI32(ctx, f, [10'i32], fibv, guest, "fib")
  if rc != 0: return rc

  if sum == expectAdd and fibv == expectFib:
    echo "PASS ", guest, ": add(20,22)=", sum, " fib(10)=", fibv
    return 0
  fail(guest, "add(20,22)=" & $sum & " (want " & $expectAdd & ") fib(10)=" & $fibv &
       " (want " & $expectFib & ")")

quit main()
