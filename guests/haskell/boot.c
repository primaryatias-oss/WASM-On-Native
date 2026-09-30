/* Start the Haskell runtime as part of the WASI reactor's `_initialize`.
 *
 * A GHC reactor module must have hs_init() called before any exported Haskell function runs;
 * the usual recipe makes every embedder export and call it (see ghc-wasm-meta's README). This
 * constructor does it from inside `_initialize` instead, so hosts only need the generic
 * reactor protocol ("call _initialize once") that every other guest in this repo uses. */
#include <HsFFI.h>

__attribute__((constructor)) static void boot_haskell_runtime(void) {
    hs_init(0, 0);
}
