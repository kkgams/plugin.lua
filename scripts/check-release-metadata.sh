#!/usr/bin/env bash
set -euo pipefail
[[ "${GITHUB_REPOSITORY:?}" == 'kkgams/plugin.lua' ]] || { echo 'Unexpected repository' >&2; exit 1; }
version="$(cat version.txt)"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid distribution version' >&2; exit 1; }
[[ "$(grep -E '^package ' src/wit/package.wit)" == 'package gams:lua@1.0.0;' ]] || { echo 'Unexpected WIT identity/version' >&2; exit 1; }
if [[ "$GITHUB_REF" == refs/tags/* ]]; then
  [[ "$GITHUB_REF" == "refs/tags/v$version" ]] || { echo 'Tag differs from version.txt' >&2; exit 1; }
else
  [[ "$GITHUB_EVENT_NAME" == workflow_dispatch && "$GITHUB_REF_TYPE" == branch ]] || { echo 'Unexpected release ref' >&2; exit 1; }
fi
bash scripts/check-licensing-digests.sh
