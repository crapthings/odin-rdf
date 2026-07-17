#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
suite=$("$root/scripts/fetch-w3c-tests.sh")
runner="$root/.cache/odin-rdf-w3c-runner"

odin build "$root/tests/w3c/runner" -out:"$runner"

total=0
failures=0
positive=0
negative=0
for file in "$suite"/*.nt; do
  mode=positive
  case "$(basename "$file")" in
    *bad*) mode=negative; negative=$((negative + 1)) ;;
    *) positive=$((positive + 1)) ;;
  esac
  if ! "$runner" "$mode" "$file"; then
    failures=$((failures + 1))
  fi
  total=$((total + 1))
done

printf 'W3C RDF 1.1 N-Triples syntax: %d cases, %d failures\n' "$total" "$failures"
if [ "$positive" -ne 43 ] || [ "$negative" -ne 29 ]; then
  printf 'unexpected W3C suite shape: %d positive, %d negative\n' "$positive" "$negative" >&2
  exit 1
fi
test "$failures" -eq 0
