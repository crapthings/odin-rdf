#!/bin/sh
set -eu

commit=15619df2fda7a4ca88308733789b6774517f9638
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cache="$root/.cache/w3c-rdf-canon-tests-$commit"

if [ ! -f "$cache/tests/manifest.csv" ]; then
  archive="$root/.cache/rdf-canon-tests-$commit.tar.gz"
  mkdir -p "$root/.cache"
  curl --fail --location --retry 3 \
    "https://github.com/w3c/rdf-canon/archive/$commit.tar.gz" \
    --output "$archive"
  mkdir -p "$cache"
  tar -xzf "$archive" --strip-components=1 -C "$cache"
fi

printf '%s\n' "$cache/tests/rdfc10"
