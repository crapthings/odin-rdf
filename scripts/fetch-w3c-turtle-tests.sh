#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ntriples_suite=$("$root/scripts/fetch-w3c-tests.sh")
suite_root=$(dirname -- "$ntriples_suite")
turtle_suite="$suite_root/rdf-turtle"

if [ ! -f "$turtle_suite/manifest.ttl" ]; then
  printf 'Turtle manifest is missing from pinned W3C suite: %s\n' "$turtle_suite" >&2
  exit 1
fi

printf '%s\n' "$turtle_suite"
