#!/usr/bin/env bash
set -euo pipefail
bash scripts/check-licensing-digests.sh
artifact="dist/plugin.${COMPONENT_SLUG:?}.wasm"
test -s "$artifact"
python3 scripts/wasm-notices.py embed "$artifact" --license LICENSE --notice NOTICE
wasm-tools validate "$artifact"
python3 scripts/wasm-notices.py verify "$artifact" --license LICENSE --notice NOTICE
cp LICENSE NOTICE dist/
(cd dist && sha256sum "plugin.${COMPONENT_SLUG}.wasm" LICENSE NOTICE > SHA256SUMS && sha256sum --check SHA256SUMS)
