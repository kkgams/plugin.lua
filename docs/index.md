---
title: Lua Runtime Plugin
status: reference
---

# Lua Runtime Plugin

[GAMS](https://github.com/kkgams/gams) WebAssembly component embedding Lua 5.5 with JSON, blocking Host calls and capability-restricted filesystem imports.

| Item | Source → output | Screenshot |
| --- | --- | --- |
| Lua runtime component | `src/component.c`, `src/runtime.lua`, `src/wit/` → `build.nosync/plugin.lua.wasm` | Not applicable |

Distribution sources include raw-WASM OCI at `ghcr.io/kkgams/gams/lua:<version>` and GitHub Release assets. OCI tags use the numeric version without the Git tag's `v` prefix. Pin specific versions rather than `latest`. The Host supplies the runtime call interface and WASI preopens; there is no sibling checkout requirement.

See [[api|Runtime API]] for named entry functions, arguments, imports and Host calls.

## Development

Use `nix develop` for the pinned WASI SDK, wit-bindgen, wasm-tools, Rust/Cargo and OCI tooling. The shell also supplies Node.js 24 for the dependency-free wiki engine, Make, Python 3, Git, curl, tar, unzip and shasum. No Node package installation is used.

| Command | Purpose |
| --- | --- |
| `make build` | Incrementally compile `build.nosync/plugin.lua.wasm` |
| `make package` | Prepare the component, notices and checksums under `build.nosync/`, without publication |
| `make test` | Run native Wasmtime runtime tests against a test-compiled component |
| `make open` | Build without tests, then open local `gams.json` in the released Host (macOS Apple Silicon) |
| `make tools/gams.app` | Download the released Host and its notices only when absent |
| `make serve-docs` | Preview documentation; independent `DOCS_PORT=8080` |
| `make docs` | Build documentation into `build.nosync/site/` |
| `make validate-docs` | Validate wiki content |
| `make clean` | Remove known recreatable build output, downloaded Host/notices and configured Unit download caches; preserve supplied/unrelated files and refuse tracked paths or directory symlinks |

The local Project opens a Files View with pinned released UI dependencies, not a Lua API demo. Existing Host downloads are preserved and macOS security checks remain intact.
