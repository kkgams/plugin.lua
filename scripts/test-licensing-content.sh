#!/usr/bin/env bash
set -euo pipefail
source_dir="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/worker5644059b-licensing.XXXXXX")"
trap 'rm -rf "$work"' EXIT
cd "$work"
unset APPROVED APPROVED_LICENSE_SHA256 APPROVED_NOTICE_SHA256
reject() {
  if bash "$source_dir/check-licensing-digests.sh" > "$work/output" 2>&1; then
    echo 'Licensing preflight accepted missing/empty source text' >&2; exit 1
  fi
}
reject
printf 'license text\n' > LICENSE
reject
: > NOTICE
reject
printf 'notice text\n' > NOTICE
bash "$source_dir/check-licensing-digests.sh"
: > LICENSE
reject
printf 'updated license text\n' > LICENSE
# Source changes need no external digest, but artifact staging verifies embedding.
bash "$source_dir/check-licensing-digests.sh"
echo 'Licensing source-content tests passed'
