#!/usr/bin/env bash
# Fails if a likely private key or common secret pattern is found in tracked files.
# Intentionally simple and dependency-free so it runs in CI without extra installs.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

PATTERN='(-----BEGIN [A-Z ]*PRIVATE KEY-----|0x[a-fA-F0-9]{64}\b.*(PRIVATE_KEY|private_key|deployer)|AKIA[0-9A-Z]{16})'

MATCHES=$(git grep -InE "$PATTERN" -- \
  ':!*.md' \
  ':!scripts/scan-secrets.sh' \
  ':!pnpm-lock.yaml' || true)

if [ -n "$MATCHES" ]; then
  echo "Potential secret material found in tracked files:"
  echo "$MATCHES"
  exit 1
fi

echo "No secret patterns found in tracked files."
