#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <oci-reference> <artifact>" >&2
  exit 2
fi

oci_ref="$1"
artifact="$2"
: "${GITHUB_ACTOR:?GITHUB_ACTOR is required}"
: "${GITHUB_TOKEN:?GITHUB_TOKEN is required}"

curl_bin="${CURL_BIN:-curl}"
wkg_bin="${WKG_BIN:-wkg}"
python_bin="${PYTHON_BIN:-python3}"

[[ -s "$artifact" ]] || { echo "Artifact is missing or empty: $artifact" >&2; exit 1; }
[[ "$oci_ref" != *@* ]] || { echo "Expected a tagged OCI reference, not a digest: $oci_ref" >&2; exit 1; }
[[ "$oci_ref" == */*:* ]] || { echo "Invalid tagged OCI reference: $oci_ref" >&2; exit 1; }

registry="${oci_ref%%/*}"
[[ "$registry" == ghcr.io ]] || { echo 'Only GHCR is supported by this release preflight.' >&2; exit 1; }
repository_and_tag="${oci_ref#*/}"
repository="${repository_and_tag%:*}"
tag="${repository_and_tag##*:}"
[[ -n "$registry" && -n "$repository" && -n "$tag" ]] || {
  echo "Invalid tagged OCI reference: $oci_ref" >&2
  exit 1
}

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

request() {
  local name="$1" body="$2" headers="$3"
  shift 3
  local status
  if ! status="$($curl_bin --silent --show-error --output "$body" --dump-header "$headers" --write-out '%{http_code}' "$@")"; then
    echo "$name failed at the HTTP transport layer; refusing to infer tag absence." >&2
    return 1
  fi
  [[ "$status" =~ ^[0-9]{3}$ ]] || {
    echo "$name returned an invalid HTTP status '$status'." >&2
    return 1
  }
  printf '%s' "$status"
}

challenge_body="$work_dir/challenge.body"
challenge_headers="$work_dir/challenge.headers"
challenge_status="$(request 'Registry authentication challenge' "$challenge_body" "$challenge_headers" "https://${registry}/v2/")"
if [[ "$challenge_status" != 401 ]]; then
  echo "Registry authentication challenge returned HTTP $challenge_status; expected 401." >&2
  exit 1
fi

auth_fields="$work_dir/auth-fields"
if ! "$python_bin" - "$challenge_headers" > "$auth_fields" <<'PY'
import re
import sys

values = []
with open(sys.argv[1], encoding="utf-8") as headers:
    for line in headers:
        if line.lower().startswith("www-authenticate:"):
            values.append(line.split(":", 1)[1].strip())
if len(values) != 1:
    raise SystemExit("expected exactly one WWW-Authenticate header")
challenge = values[0]
if not re.match(r"(?i)^bearer\s", challenge):
    raise SystemExit("expected a Bearer authentication challenge")

def parameter(name):
    match = re.search(rf'(?i)(?:^|,)\s*{name}="([^"]+)"', challenge.split(None, 1)[1])
    if not match:
        raise SystemExit(f"Bearer challenge has no {name}")
    return match.group(1)

realm = parameter("realm")
service = parameter("service")
if realm != "https://ghcr.io/token" or service != "ghcr.io":
    raise SystemExit("Refusing to send GitHub credentials to an unexpected token realm/service")
print(realm)
print(service)
PY
then
  echo 'Registry returned a malformed authentication challenge.' >&2
  exit 1
fi
mapfile -t auth < "$auth_fields"
[[ ${#auth[@]} -eq 2 ]] || { echo 'Could not parse registry authentication challenge.' >&2; exit 1; }
realm="${auth[0]}"
service="${auth[1]}"

token_body="$work_dir/token.body"
token_headers="$work_dir/token.headers"
token_status="$(request 'Read-only registry token request' "$token_body" "$token_headers" \
  --get \
  --user "${GITHUB_ACTOR}:${GITHUB_TOKEN}" \
  --data-urlencode "service=${service}" \
  --data-urlencode "scope=repository:${repository}:pull" \
  "$realm")"
if [[ "$token_status" != 200 ]]; then
  echo "Read-only registry token request returned HTTP $token_status; refusing to infer tag absence." >&2
  exit 1
fi

if ! registry_token="$($python_bin - "$token_body" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as response:
    payload = json.load(response)
token = payload.get("token") or payload.get("access_token")
if not isinstance(token, str) or not token:
    raise SystemExit("token response has no non-empty token")
print(token)
PY
)"; then
  echo 'Registry returned a malformed token response.' >&2
  exit 1
fi

manifest_body="$work_dir/manifest.body"
manifest_headers="$work_dir/manifest.headers"
manifest_status="$(request 'OCI manifest lookup' "$manifest_body" "$manifest_headers" \
  --head \
  --header "Authorization: Bearer ${registry_token}" \
  --header 'Accept: application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json' \
  "https://${registry}/v2/${repository}/manifests/${tag}")"

case "$manifest_status" in
  404)
    echo "OCI tag $oci_ref is absent; push is permitted."
    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
      echo 'should_push=true' >> "$GITHUB_OUTPUT"
    fi
    ;;
  200)
    pulled="$work_dir/existing.wasm"
    "$wkg_bin" oci pull "$oci_ref" -o "$pulled"
    [[ -s "$pulled" ]] || { echo "Pulled OCI artifact is missing or empty: $oci_ref" >&2; exit 1; }
    if ! cmp --silent "$artifact" "$pulled"; then
      echo "OCI tag $oci_ref already exists with different artifact bytes; refusing to overwrite it." >&2
      exit 1
    fi
    echo "OCI tag $oci_ref already contains the exact artifact bytes; push will be skipped."
    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
      echo 'should_push=false' >> "$GITHUB_OUTPUT"
    fi
    ;;
  *)
    echo "OCI manifest lookup returned HTTP $manifest_status; refusing to infer tag absence." >&2
    exit 1
    ;;
esac
