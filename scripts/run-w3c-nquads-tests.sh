#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
nt_suite=$("$root/scripts/fetch-w3c-tests.sh")
suite=$(dirname "$nt_suite")/rdf-n-quads
runner="$root/.cache/odin-rdf-w3c-nquads-runner"

odin build "$root/tests/w3c/nquads_runner" -out:"$runner"

positive_list="$root/.cache/nquads-positive.txt"
negative_list="$root/.cache/nquads-negative.txt"
awk '
  /TestNQuadsPositiveSyntax/ { mode="positive" }
  /TestNQuadsNegativeSyntax/ { mode="negative" }
  /mf:action/ {
    line=$0
    sub(/^.*</, "", line)
    sub(/>.*$/, "", line)
    if (mode == "positive") print line
  }
' "$suite/manifest.ttl" > "$positive_list"
awk '
  /TestNQuadsPositiveSyntax/ { mode="positive" }
  /TestNQuadsNegativeSyntax/ { mode="negative" }
  /mf:action/ {
    line=$0
    sub(/^.*</, "", line)
    sub(/>.*$/, "", line)
    if (mode == "negative") print line
  }
' "$suite/manifest.ttl" > "$negative_list"

total=0
failures=0
while IFS= read -r file; do
  if ! "$runner" positive "$suite/$file"; then failures=$((failures + 1)); fi
  total=$((total + 1))
done < "$positive_list"
while IFS= read -r file; do
  if ! "$runner" negative "$suite/$file"; then failures=$((failures + 1)); fi
  total=$((total + 1))
done < "$negative_list"

positive=$(wc -l < "$positive_list" | tr -d ' ')
negative=$(wc -l < "$negative_list" | tr -d ' ')
printf 'W3C RDF 1.1 N-Quads syntax: %d cases, %d failures\n' "$total" "$failures"
test "$positive" -eq 53
test "$negative" -eq 34
test "$failures" -eq 0
