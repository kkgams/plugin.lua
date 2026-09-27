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
- A pinned standalone Wasmtime component-model runner in `runtime-e2e/` executes the final notice-bearing candidate, including `host.call` and syntax-error behavior. Candidate and tag workflows require this runtime E2E; hosted Linux execution is still required.

No timestamp or platform is asserted here because this generated repository does not
carry an independently established validation record for its current bytes.

## Release blockers

- Apache-2.0 was approved for GAMS-authored code; third-party provenance, notices,
  source obligations, and the linked artifact inventory still need owner review.
- Independent Linux CI evidence has not yet been recorded.
- `prepare()` initializes no Git repository and performs no network publication.
- A release scaffold exists, but must not be pushed to a public repository or tagged until licensing and distribution gates are reviewed.
