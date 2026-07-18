#!/bin/sh
set -eu

commit=92f07705a0c0ac27aa9bc6fe1322dcc9fad0114d
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cache="$root/.cache/w3c-json-ld-api-$commit"

if [ ! -f "$cache/tests/toRdf-manifest.jsonld" ]; then
  archive="$root/.cache/json-ld-api-$commit.tar.gz"
  mkdir -p "$root/.cache"
  curl --fail --location --retry 3 \
    "https://github.com/w3c/json-ld-api/archive/$commit.tar.gz" \
    --output "$archive"
  mkdir -p "$cache"
  tar -xzf "$archive" --strip-components=1 -C "$cache"
fi

printf '%s\n' "$cache/tests"
