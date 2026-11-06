#!/usr/bin/env bash
# Validate required source licensing texts; no external approval state is needed.
set -euo pipefail
for file in LICENSE NOTICE; do
  [[ -s "$file" ]] || { echo "Missing or empty required text: $file" >&2; exit 1; }
done
