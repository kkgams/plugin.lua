#!/usr/bin/env bash
# Re-link exactly the Makefile inputs, inspect a real link map, and prove its
# notice-bearing stripped result is identical to the release candidate.
set -euo pipefail
[[ $# -eq 1 ]] || { echo 'Usage: record-build-evidence.sh OUTPUT_DIR' >&2; exit 2; }
output="$1"
[[ ! -e "$output" ]] || { echo "Evidence directory already exists: $output" >&2; exit 1; }
: "${WASI_SDK_PATH:?WASI SDK path required}"
for file in LICENSE NOTICE "$WASI_SDK_PATH/VERSION" \
    build/bindings/lua_plugin.c build/bindings/lua_plugin_component_type.o \
    dist/plugin.lua.wasm; do
  [[ -s "$file" ]] || { echo "Missing evidence input: $file" >&2; exit 1; }
done
# The relink without embedded notices is temporary. Never include an
# unlicensed WASM in the publicly downloadable evidence artifact.
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$output"
cp "$WASI_SDK_PATH/VERSION" "$output/wasi-sdk-VERSION"
{
  printf 'uname: '; uname -a
  printf 'wasi clang:\n'; wasm32-wasip2-clang --version
  printf 'wasm-component-ld: '; "$WASI_SDK_PATH/bin/wasm-component-ld" --version
  printf 'wasm-tools: '; wasm-tools --version
  printf 'wit-bindgen: '; wit-bindgen --version
  printf 'node: '; node --version
  printf 'npm: '; npm --version
  :
} > "$output/tool-versions.txt" 2>&1

wasm32-wasip2-clang -o "$work/relinked.wasm" -mexec-model=reactor \
  -Ibuild/bindings -O2 -DNDEBUG -Dl_signalT=int -Isrc/vendor/lua -Isrc -mexception-handling -mmultivalue -mreference-types -mllvm -wasm-enable-sjlj -mllvm -wasm-use-legacy-eh=false \
  build/bindings/lua_plugin.c src/component.c src/shim/wasm_setjmp_shim.c src/shim/wasm_eh_tags.s src/vendor/lua/lapi.c src/vendor/lua/lauxlib.c src/vendor/lua/lbaselib.c src/vendor/lua/lcode.c src/vendor/lua/lcorolib.c src/vendor/lua/lctype.c src/vendor/lua/ldebug.c src/vendor/lua/ldo.c src/vendor/lua/ldump.c src/vendor/lua/lfunc.c src/vendor/lua/lgc.c src/vendor/lua/llex.c src/vendor/lua/lmathlib.c src/vendor/lua/lmem.c src/vendor/lua/loadlib.c src/vendor/lua/lobject.c src/vendor/lua/lopcodes.c src/vendor/lua/lparser.c src/vendor/lua/lstate.c src/vendor/lua/lstring.c src/vendor/lua/lstrlib.c src/vendor/lua/ltable.c src/vendor/lua/ltablib.c src/vendor/lua/ltm.c src/vendor/lua/lundump.c src/vendor/lua/lutf8lib.c src/vendor/lua/lvm.c src/vendor/lua/lzio.c \
  build/bindings/lua_plugin_component_type.o \
  -Wl,--strip-all -Wl,-Map,"$output/link.map"
[[ -s "$output/link.map" ]] || { echo 'Empty link map' >&2; exit 1; }
wasm-tools validate "$work/relinked.wasm"
wasm-tools strip -a "$work/relinked.wasm" -o "$work/repackaged.wasm"
python3 scripts/wasm-notices.py embed "$work/repackaged.wasm" --license LICENSE --notice NOTICE
cmp dist/plugin.lua.wasm "$work/repackaged.wasm"
wasm-tools metadata show --json dist/plugin.lua.wasm > "$output/component-metadata.json"
sha256sum LICENSE NOTICE dist/plugin.lua.wasm > "$output/approved-bytes-sha256.txt"
printf 'Reviewed link map: %s\n' "$output/link.map"
sha256sum dist/plugin.lua.wasm
