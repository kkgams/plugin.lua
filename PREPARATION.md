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

- The owner approved Apache-2.0 for GAMS-authored code and reviewed this
  repository's third-party NOTICE. Hosted Linux candidate/link evidence is still
  required before a version tag may authorize release.
- `prepare()` initializes no Git repository and performs no network publication.
- The release scaffold is ready for an owner-operated `release` branch push after
  repository variables are set. Do not push a version tag until the exact hosted
  candidate and branch release-shell run pass and are reviewed.
