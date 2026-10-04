> **Prospective v0.2.0 maintenance preparation — NOT release-ready.**
> Target: `plugin.lua` v0.2.0, `plugin.lua.wasm`, `ghcr.io/kkgams/gams/lua:0.2.0`.
> Below is frozen historical documentation: existing GitHub Release URLs,
> versioned examples and repair instructions refer to their original releases.
> For a future v0.2.0 candidate, use the prepared distribution metadata;
> rebuild and run repository-owned locked toolchain/runtime tests, review
> source drift, linked evidence and exact LICENSE/NOTICE/candidate digests.
> Migrate the direct-release publisher to draft-first immutable-policy and
> exact public-byte verification before any tag/OCI push/Pages publication.
> Do not run the historical publishing commands as v0.2.0 instructions.

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
