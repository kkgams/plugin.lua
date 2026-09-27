# plugin.lua

Standalone extraction of the GAMS Lua WebAssembly component, including the
vendored Lua sources, jsmn header, WASM exception/setjmp shims, and local WIT
dependencies required to build it. It exports `gams:lua/lua@1.0.0` and imports
the Host's `gams:runtime/runtime@1.0.0` plus WASI filesystem interfaces.

## Build and verify

```sh
nix develop --command make test
```

`make test` builds/validates the component and checks WIT/vendor source invariants.
Because jco cannot transpile the exception-handling core, the branch-candidate and
tag workflows additionally run `scripts/test-runtime-component.sh` with the locked
standalone `runtime-e2e/` Wasmtime host. It executes the final WASM's `main()`
result, a `host.call` bridge, and syntax-error diagnostics without the GAMS Host.
Output is `dist/plugin.lua.wasm`.

The owner approved Apache-2.0 for GAMS-authored code and reviewed the vendored
and linked third-party notices. Hosted Linux candidate/E2E evidence remains; see
`LICENSING.md`, `THIRD-PARTY-REVIEW.md`, and `PUBLISHING.md`.
