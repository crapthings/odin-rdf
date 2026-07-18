#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
suite=$("$root/scripts/fetch-w3c-tests.sh" | xargs dirname)/rdf-xml
runner="$root/.cache/odin-rdf-w3c-rdfxml-runner"
base='https://w3c.github.io/rdf-tests/rdf/rdf11/rdf-xml/'

mkdir -p "$root/.cache"
odin build "$root/tests/w3c/rdfxml_runner" -out:"$runner"

total=0
failures=0

for action in $(find "$suite" -name '*.rdf' -type f | sort); do
  result=${action%.rdf}.nt
  if [ ! -f "$result" ]; then continue; fi
  relative=${action#"$suite"/}
  if ! "$runner" evaluation "$action" "$base$relative" "$result"; then failures=$((failures + 1)); fi
  total=$((total + 1))
done

for action in $(find "$suite" -name 'error*.rdf' -type f | sort); do
  relative=${action#"$suite"/}
  if ! "$runner" negative "$action" "$base$relative"; then failures=$((failures + 1)); fi
  total=$((total + 1))
done

printf 'W3C RDF/XML core: %d cases, %d failures\n' "$total" "$failures"
test "$total" -eq 173
test "$failures" -eq 0
