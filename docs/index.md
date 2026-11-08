---
title: Development
status: reference
---

# plugin.lua development

Build and verify the component with its pinned toolchain:

```sh
nix develop --command make build
nix develop --command make test
```

## Runtime calls and imports

`run(source, entry, args-json, source-path)` keeps the `gams:lua/lua@1.0.0`
export but breaks the previous one-argument call. Supply null for absent options.
The global entry defaults to `main` and must exist; `args-json` is an optional
JSON argument array unpacked into it. Pass optional context as an ordinary argument,
for example `[{"pluginId":"lua","runId":"r1"}]`. A named metadata entry can run
without `main`; top-level source statements still execute.

`import("./nodes/add.lua")` returns the file's explicit exports. Relative paths
resolve from the importing Lua file, including later calls from exported functions.
The optional `source-path` anchors the root script; without it imports use the
existing granted root. Normalized paths are cached per run. Cycles and nil exports
are errors. Imports are text-only and retain WASI filesystem restrictions.
`require` is unchanged. See README for module/context examples and limitations.

Exercise the actual component with the pinned Wasmtime runner:

```sh
nix develop --command bash scripts/test-runtime-component.sh
```

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

See the repository README and licensing/publication documents for API details,
coverage limits and existing release gates.
