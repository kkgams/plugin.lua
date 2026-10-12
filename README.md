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
