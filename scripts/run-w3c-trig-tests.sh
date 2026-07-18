#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
runner="$root/.cache/odin-rdf-w3c-trig-runner"
inventory=$(mktemp "${TMPDIR:-/tmp}/odin-rdf-trig-inventory.XXXXXX")
trap 'rm -f "$inventory"' EXIT HUP INT TERM

mkdir -p "$root/.cache"
odin build "$root/tests/w3c/trig_runner" -out:"$runner"
"$root/scripts/list-w3c-trig-tests.sh" > "$inventory"

total=0
failures=0
tab=$(printf '\t')
while IFS="$tab" read -r kind action result; do
  if [ "$result" = - ]; then
    if ! "$runner" "$kind" "$action"; then failures=$((failures + 1)); fi
  else
    if ! "$runner" "$kind" "$action" "$result"; then failures=$((failures + 1)); fi
  fi
  total=$((total + 1))
done < "$inventory"

printf 'W3C RDF 1.1 TriG: %d cases, %d passed, %d failures\n' "$total" "$((total - failures))" "$failures"
test "$total" -eq 355
test "$failures" -eq 0
