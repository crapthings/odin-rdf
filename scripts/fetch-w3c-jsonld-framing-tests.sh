#!/bin/sh
set -eu

commit=3bf782ba9a40dd1b143435abe386d38df64f2b47
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cache="$root/.cache/w3c-json-ld-framing-$commit"

if [ ! -f "$cache/tests/frame-manifest.jsonld" ]; then
  archive="$root/.cache/json-ld-framing-$commit.tar.gz"
  mkdir -p "$root/.cache"
  curl --fail --location --retry 3 \
    "https://github.com/w3c/json-ld-framing/archive/$commit.tar.gz" \
    --output "$archive"
  mkdir -p "$cache"
  tar -xzf "$archive" --strip-components=1 -C "$cache"
fi

printf '%s\n' "$cache/tests"
