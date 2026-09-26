# Preparation evidence

This repository is generated from working-tree source bytes. The ecosystem
orchestrator records global source provenance and hashes separately.

## Validation status

The validation commands in the ecosystem record describe historical extraction
validation and the checks required for this snapshot. `prepare()` does not execute
or claim a current verification run. The main setup orchestrator must run and record
those commands against the generated `plugin.lua` repository.

- Required command: `nix develop --command make test`
- Required artifact check: `nix develop --command wasm-tools validate dist/plugin.lua.wasm`
- `make test` performs build, `wasm-tools validate`, extracted-WIT assertions, and vendored/source invariant checks only. It is explicitly a static test, not a Lua runtime E2E test.
- Lua runtime E2E remains blocked: jco 1.32.1 rejects the exception-handling core, while extracting the native Wasmtime path from `cmd/app` would pull in the Host runtime and its large Rust dependency closure. A small standalone component-model host for `gams:runtime/runtime@1.0.0` is still required.

No timestamp or platform is asserted here because this generated repository does not
carry an independently established validation record for its current bytes.

## Release blockers

- Repository-owner license approval remains unresolved; see `LICENSING.md`.
- Third-party provenance, notices, source obligations, and artifact inventory need approval.
- Independent Linux CI evidence has not yet been recorded.
- No Git repository was initialized and no network publication was performed.
