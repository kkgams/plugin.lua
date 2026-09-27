# plugin.lua

Standalone extraction of the GAMS Lua WebAssembly component, including the
vendored Lua sources, jsmn header, WASM exception/setjmp shims, and local WIT
dependencies required to build it. It exports `gams:lua/lua@1.0.0` and imports
the Host's `gams:runtime/runtime@1.0.0` plus WASI filesystem interfaces.

## Build and verify

```sh
nix develop --command make test
```

The standalone static test builds and validates the component, inspects its extracted
WIT, and verifies vendored Lua/source invariants. It does not execute Lua and does not
claim full runtime coverage. Runtime E2E remains blocked because jco 1.32.1 cannot
translate this component's exception-handling core. Reusing the native Wasmtime path
from the GAMS Host would import the Host runtime and a large Rust dependency closure;
a small standalone host for the runtime import is still needed. This is also recorded
in `PREPARATION.md`. Output is `dist/plugin.lua.wasm`.

A fail-closed release pipeline scaffold is included; see `PUBLISHING.md`. No licensing texts have been approved or included. Vendored Lua and jsmn make the
third-party review especially important; see `LICENSING.md` and `PREPARATION.md`.
