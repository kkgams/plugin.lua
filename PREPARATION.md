## Current 0.2.1 release authorization

The owner's current instruction is: "no need for review of checksums / licenses - those area already prepared - drop pending reviews, commit changes, prepare tags - create script (using gh) to push to repos and create releases."

This supersedes earlier pending human checksum/license and hosted-review approvals
for the prepared 0.2.1 release. Documentation commits and annotated **local**
`v0.2.1` tags at the tested HEAD are authorized. No repeated human review is
pending for these unchanged prepared bytes. Prior "before any tag" restrictions,
including publisher migration, do not restrict local tagging.

This is not evidence of hosted Linux CI, GUI/Host consumption, registry visibility,
immutable policy, draft-first rehearsal or anonymous public-byte verification.
Those coverage gaps remain accurately unverified; publication technical checks
still apply. Version, source closure, evidence, exact license/notice digest and
candidate-byte gates remain strict. No source or legal evidence is refreshed.
No remote push/publication, repository variable or remote configuration change
is performed by this local preparation. Never move or overwrite an existing tag.

> Prepared target: `plugin.lua` v0.2.1; not yet published.
> The documentation below is a frozen historical record, not current
> pending approval requirements. Its human review/local-tag restrictions are
> superseded above; technical publication safeguards are not waived.

# Preparation evidence

Historical source provenance and extraction hashes are recorded in `SOURCE.json`.

## Validation status

Run the commands below against the current checkout and record their results.
Historical extraction validation is not proof that the current checkout passes.

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
- The release scaffold is ready for an owner-operated `release` branch push after
  repository variables are set. Do not push a version tag until the exact hosted
  candidate and branch release-shell run pass and are reviewed.
