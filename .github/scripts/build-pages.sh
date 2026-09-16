#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <output-dir>" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUTPUT_DIR="$1"

cd "$ROOT_DIR"
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

cp pack.toml "$OUTPUT_DIR/pack.toml"
cp index.toml "$OUTPUT_DIR/index.toml"
touch "$OUTPUT_DIR/.nojekyll"

while IFS= read -r indexed_file; do
  [[ -n "$indexed_file" ]] || continue
  mkdir -p "$OUTPUT_DIR/$(dirname "$indexed_file")"
  cp "$indexed_file" "$OUTPUT_DIR/$indexed_file"
done < <(sed -nE 's/^file = "(.*)"$/\1/p' index.toml)
