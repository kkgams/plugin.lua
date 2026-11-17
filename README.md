# Lua Runtime Plugin

[GAMS](https://github.com/kkgams/gams) WebAssembly component embedding Lua 5.5 with JSON, blocking Host calls and capability-restricted filesystem imports.

| Item | Source → output | Screenshot | License / original work |
| --- | --- | --- | --- |
| Lua runtime component | `src/component.c`, `src/runtime.lua`, `src/wit/` → `build.nosync/plugin.lua.wasm` | Not applicable | [Apache-2.0](LICENSE); [notices](NOTICE), [original third-party terms](licenses/THIRD-PARTY.txt); [Lua.org](https://www.lua.org/), [jsmn / Serge Zaitsev](https://github.com/zserge/jsmn), WASI and linked component support |

Distribution sources are raw-WASM OCI packages at `ghcr.io/kkgams/gams/lua:<version>` and GitHub Release assets `plugin.lua.wasm`, `LICENSE`, `NOTICE` and `SHA256SUMS`. OCI tags use the numeric version without the Git tag's `v` prefix. Pin a specific release, not `latest`. The raw component embeds the license and complete third-party notices; the distributed NOTICE also contains those texts.

## Runtime interface

`gams:lua/lua@1.0.0` exports `run(source, entry, args-json, source-path)`. Use null for absent options. The selected global function defaults to `main`; JSON arguments are unpacked into it. `source-path` anchors relative `import` calls, including imports made later by exported functions. Imports cache module exports within one invocation, reject cycles and retain Host-granted WASI restrictions.

See [Runtime API](docs/api.md) for examples, JSON/Host call behavior and limitations. Selecting a metadata function still evaluates top-level source: it is not safe inspection of untrusted Lua. The Host supplies `gams:runtime/runtime@1.0.0` and WASI preopens. No sibling source checkout is required.

## Development

Use `nix develop` for pinned WASI SDK, wit-bindgen, wasm-tools, Rust/Cargo and OCI tooling. The shell also supplies Node.js 24 for the dependency-free wiki engine, Make, Python 3, Git, curl, tar, unzip and shasum. No Node package installation is used.

| Command | Purpose |
| --- | --- |
| `make build` | Incrementally compile `build.nosync/plugin.lua.wasm`, including embedded notices |
| `make package` | Prepare the component, license/notices and checksums under `build.nosync/`; never publish |
| `make test` | Run the existing native Wasmtime runtime tests against a test-compiled component |
| `make open` | Build without tests, then open local `gams.json` in the released Host (macOS Apple Silicon) |
| `make tools/gams.app` | Download the Host and its notices only when absent |
| `make serve-docs` | Preview pinned justgook/wiki documentation; independent `DOCS_PORT=8080` |
| `make docs` / `make validate-docs` | Build documentation into `build.nosync/site/` / validate it |
| `make clean` | Remove all of `build.nosync/`, `tools/` and `gams_modules/`, including unmarked contents; refuse tracked files and symlinks before deleting anything. |

The local Project loads the built component and pinned released UI dependencies. It opens a Files View, not a Lua API demo. Existing downloaded Hosts are not updated implicitly; macOS security checks remain intact.
