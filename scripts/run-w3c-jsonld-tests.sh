#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
suite=$("$root/scripts/fetch-w3c-jsonld-tests.sh")
runner="$root/.cache/odin-rdf-w3c-jsonld-runner"
mkdir -p "$root/.cache"

odin build "$root/tests/w3c/jsonld_runner" -out:"$runner"

cases='
0001 0002 0003 0004 0005 0006 0007 0008 0009 0010 0011 0012 0013 0014 0015
0016 0017 0018 0019 0020 0022 0023 0024 0025 0026 0027 0028 0029 0030 0031
0032 0033 0034 0035 0036 0113 0114 0115 0116 0117 0119 0120 0121 0122 0123
0124 0125 0126 0127 0128 0129 0130 0131 0132 0133
'

total=0
failures=0
for case_id in $cases; do
  input="$suite/toRdf/$case_id-in.jsonld"
  expected="$suite/toRdf/$case_id-out.nq"
  actual="$root/.cache/odin-rdf-jsonld-$case_id.actual.nq"
  expected_sorted="$root/.cache/odin-rdf-jsonld-$case_id.expected.sorted.nq"
  actual_sorted="$root/.cache/odin-rdf-jsonld-$case_id.actual.sorted.nq"
  if ! "$runner" "$input" "https://w3c.github.io/json-ld-api/tests/toRdf/$case_id-in.jsonld" "$suite" > "$actual" || ! sort "$expected" > "$expected_sorted" || ! sort "$actual" > "$actual_sorted" || ! diff -u "$expected_sorted" "$actual_sorted"; then
    failures=$((failures + 1))
  fi
  total=$((total + 1))
done

printf 'W3C JSON-LD to-RDF core: %d cases, %d failures\n' "$total" "$failures"
test "$total" -eq 55
test "$failures" -eq 0
