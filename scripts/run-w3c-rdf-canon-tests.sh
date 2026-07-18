#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
suite=$("$root/scripts/fetch-w3c-rdf-canon-tests.sh")
runner="$root/.cache/odin-rdf-w3c-canon-runner"

mkdir -p "$root/.cache"
odin build "$root/tests/w3c/canon_runner" -out:"$runner"

total=0
failures=0

for input in "$suite"/*-in.nq; do
  expected=${input%-in.nq}-rdfc10.nq
  if [ ! -f "$expected" ]; then continue; fi
  algorithm=sha256
  case "$input" in
    *test075-in.nq) algorithm=sha384 ;;
  esac
  if ! "$runner" evaluation "$input" "$expected" "$algorithm"; then failures=$((failures + 1)); fi
  total=$((total + 1))
done

if ! "$runner" negative "$suite/test074-in.nq"; then failures=$((failures + 1)); fi
total=$((total + 1))

printf 'W3C RDFC-1.0: %d cases, %d failures\n' "$total" "$failures"
test "$total" -eq 65
test "$failures" -eq 0
