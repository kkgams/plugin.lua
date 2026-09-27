#!/usr/bin/env bash
set -euo pipefail
source_dir="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cd "$work"
printf '0.1.0\n' > version.txt
cat > curl <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ "$*" == *'https://api.github.com/repos/kkgams/plugin.lua/releases/tags/v0.1.0'* ]] || exit 9
case "$TEST_STATUS" in
  transport) exit 7 ;;
  *) printf '%s' "$TEST_STATUS" ;;
esac
SH
chmod +x curl
export CURL_BIN="$work/curl" GH_TOKEN=fake GITHUB_REPOSITORY=kkgams/plugin.lua GITHUB_REF_NAME=v0.1.0
TEST_STATUS=404 bash "$source_dir/check-release-absent.sh"
for status in 200 401 403 500 transport; do
  if TEST_STATUS="$status" bash "$source_dir/check-release-absent.sh" > "$work/out" 2>&1; then
    echo "Unsafe acceptance of release lookup: $status" >&2; exit 1
  fi
done
if GITHUB_REPOSITORY=attacker/repo TEST_STATUS=404 bash "$source_dir/check-release-absent.sh" > "$work/out" 2>&1; then
  echo 'Unsafe repository acceptance' >&2; exit 1
fi
if GITHUB_REF_NAME=v0.1.1 TEST_STATUS=404 bash "$source_dir/check-release-absent.sh" > "$work/out" 2>&1; then
  echo 'Unsafe tag acceptance' >&2; exit 1
fi
echo 'Director GitHub Release absence tests passed'
