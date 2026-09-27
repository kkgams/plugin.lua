#!/usr/bin/env bash
# Exercise final plugin.lua WASM through a small standalone Wasmtime component host.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
manifest="$repo_root/runtime-e2e/Cargo.toml"
component="$repo_root/dist/plugin.lua.wasm"
[[ -f "$manifest" ]] || { echo "missing runtime E2E manifest: $manifest" >&2; exit 1; }
[[ -f "$component" ]] || { echo "missing built Lua component: $component (run make build first)" >&2; exit 1; }

if [[ -n "${IN_NIX_SHELL:-}" ]]; then
  # The WASI SDK prepends a wasm-targeting `clang` to PATH. Cargo's native C
  # build scripts (e.g. zstd) must use Nix's *host* compiler instead.
  : "${NIX_CC:?Nix host C compiler required for runtime E2E}"
  export CC="$NIX_CC/bin/cc" CXX="$NIX_CC/bin/c++" AR="$NIX_CC/bin/ar"
  cargo run --locked --manifest-path "$manifest" -- "$component"
else
  command -v nix >/dev/null || { echo 'nix required outside the repo development shell' >&2; exit 1; }
  nix develop "$repo_root" --command cargo run --locked --manifest-path "$manifest" -- "$component"
fi
