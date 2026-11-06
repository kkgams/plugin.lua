## Current tag-based release authorization

Pushing the matching version tag authorizes release in this repository. No manual
checksum variables, approval boolean, hosted-review approval, or `release`-branch
HEAD match is required. Branch candidates still validate their payloads; they do
not publish a GitHub Release or OCI version. Manual branch runs verify only.

Repository/tag/version and WIT identity checks, build/runtime tests, source and
build-evidence checks, nonempty LICENSE/NOTICE, exact embedded licensing bytes,
generated SHA256SUMS, independent candidates, and GitHub Release/OCI no-overwrite
checks remain required. The workflow uses the automatic GitHub token. Never move
or overwrite an existing version tag. Pages publication remains independent.

This policy supersedes historical approval-variable and pre-tag review/branch
requirements below, not source provenance or legal terms. It does not claim hosted
validation or authorize this editing session to commit, push, tag, or publish.
No source snapshots, legal texts, or historical evidence are refreshed.

> Prepared target: `plugin.lua` v0.2.1; not yet published.
> The documentation below is a frozen historical record, not current
> pending approval requirements. Its manual approval/checksum and pre-tag
> review/branch requirements are superseded above; content checks remain.

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

## Local Project and documentation

```sh
nix develop --command make open  # build, then open this repository's gams.json
make serve-docs                 # http://localhost:8080; DOCS_PORT overrides
make validate-docs
make docs                       # portable site under build/site/
```

`make open` builds `dist/plugin.lua.wasm` and explicitly sets `GAMS_APP_CWD`
to this repository. The local Project loads that component and the pinned
released Files View to inspect Project files; it is not an API demo.
The shell uses the released layout provider.
No sibling source checkout is required.

`make tools/gams.app` downloads the released macOS Apple Silicon Host only
when absent and retains its notices under `tools/gams-release-notices/`.
Existing downloads are not updated implicitly; macOS security checks remain
intact. The first download and Project launch require network access.
Pinned dependencies are declared in `gams.json`; Host caches live in ignored
`gams_modules/`. Native GUI behavior requires separate verification.

Documentation uses pinned justgook/wiki v1.4.0, with ignored engine/output
under `build/`. `build-docs` remains a build alias. GitHub Pages runs `make docs`
on every push to `release`, independently of component release tags.
Enable **Settings → Pages → Source → GitHub Actions**. Existing component
build, runtime tests, candidate checks and matching-tag release rules are unchanged.
