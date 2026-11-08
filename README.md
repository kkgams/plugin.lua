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
result, named entries/arguments, lexical imports/cache/cycles, WASI isolation,
a `host.call` bridge, and syntax-error diagnostics without the GAMS Host.
Output is `dist/plugin.lua.wasm`.

The owner approved Apache-2.0 for GAMS-authored code and reviewed the vendored
and linked third-party notices. Hosted Linux candidate/E2E evidence remains; see
`LICENSING.md`, `THIRD-PARTY-REVIEW.md`, and `PUBLISHING.md`.

## Runtime API (breaking change)

```wit
run: func(source: string, entry: option<string>, args-json: option<string>, source-path: option<string>) -> result<string, string>;
```

The export remains `gams:lua/lua@1.0.0`. Calls must now provide all four
positions; omitted options are `null` in Host JSON calls. For example:

```js
[source, "main", JSON.stringify([{pluginId: "lua", runId: "r1"}]), "ng/graph.lua"]
```

`entry` defaults to `main`; the selected global must be a function. `args-json`
is an optional JSON array unpacked into that function. JSON null arguments become
Lua nil while retaining their argument positions. A context object is optional,
caller-owned data, not an implicit runtime argument. Select `ng_graph_json` to
read graph metadata without defining or calling `main`. Source is always evaluated
before calling the entry, so keep top-level statements free of execution effects
when metadata inspection must not execute the graph.

`source-path` identifies the supplied source for diagnostics and relative imports;
it does not read or grant access to that file. Without it, relative imports start
at the existing granted filesystem root. Strings pass through as results; nil
becomes `null`, and other results are JSON encoded.

```lua
local node = import("./nodes/add.lua")
function main(context)
  local outputs = {}
  node({ value = 3 }, outputs, context)
  return outputs
end
```

Imported files must explicitly return their exports (a function, table or other
non-nil value). Each file has its own global environment inheriting the runtime
libraries; its `import` resolves from that file even when an exported function is
called later. Paths use `/`, support nested `.`/`..` normalization, and are cached
by normalized path for one run. Cycles, missing files and nil exports are errors;
failed imports are not cached. Files are loaded as text only, with no implicit
extension or dotted-name conversion. Existing `require` behavior is unchanged.
Cache identity is path-based, not filesystem-inode or symlink-based. Imports and
`fs.read_text` use only Host-granted WASI preopens; source paths grant no new
filesystem capability.

For a graph file usable both directly and through import, end it with:

```lua
return { main = main, ng_graph_json = ng_graph_json }
```

Run the real component tests separately from static checks:

```sh
nix develop --command bash scripts/test-runtime-component.sh
```

For manual integration checks, the same locked runner can execute a supplied
source file against a read-only directory mounted as `/project`:

```sh
nix develop --command bash scripts/test-runtime-component.sh \
  --run source.lua fixture-directory main '[]' /project/source.lua
```

Use `-` for an absent entry, argument JSON or source path. The runner prints the
Lua result and exits nonzero on errors. Its Host bridge remains the E2E echo
fixture, not a general GAMS Host replacement.

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
