#!/usr/bin/env bash
# Exercise the test-only Lua component with the locked native Wasmtime host.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export LUA_COMPONENT_PATH="${LUA_COMPONENT_PATH:-$repo_root/build.nosync/test/plugin.lua.wasm}"
export CARGO_TARGET_DIR="$repo_root/build.nosync/runtime-target"
mkdir -p "$repo_root/build.nosync/tmp"
export TMPDIR="$repo_root/build.nosync/tmp"
[[ -f "$LUA_COMPONENT_PATH" ]] || {
	echo "missing test component: $LUA_COMPONENT_PATH (run make test first)" >&2
	exit 1
}

if [[ -z "${IN_NIX_SHELL:-}" ]]; then
	exec nix develop "$repo_root" --command bash "$repo_root/scripts/test-runtime-component.sh" "$@"
fi
# The WASI SDK's clang targets WASM; Cargo's C build scripts need the host SDK.
: "${NIX_CC:?Nix host C compiler required for runtime E2E}"
export CC="$NIX_CC/bin/cc" CXX="$NIX_CC/bin/c++" AR="$NIX_CC/bin/ar"
if [[ $# -eq 0 ]]; then
	exec cargo test --locked --manifest-path "$repo_root/runtime-e2e/Cargo.toml" -- --nocapture
fi
exec cargo run --locked --manifest-path "$repo_root/runtime-e2e/Cargo.toml" -- "$LUA_COMPONENT_PATH" "$@"
