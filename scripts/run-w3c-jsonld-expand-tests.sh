#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
suite=$("$root/scripts/fetch-w3c-jsonld-tests.sh")
runner="$root/.cache/odin-rdf-w3c-jsonld-expand-runner"
mkdir -p "$root/.cache"

odin build "$root/tests/w3c/jsonld_expand_runner" -out:"$runner"

# The document-level core targets aliases, scalar/value expansion, @set,
# @list, language/type coercion, reverse properties, transparent nesting,
# graph expansion, sourced-context @import overrides, and protected source
# definitions.
cases='
0001 0002 0003 0004 0005 0006 0007 0008 0009 0010
0011 0012 0013 0014 0015 0016 0017 0018 0019 0020
0021 0022 0023 0024 0025 0026 0027 0028 0029 0030
0031 0032 0033 0034 0035 0036 0037 0038 0039 0040
0042 0043 0049 0063 0064 0078
n001 n002 n003 n004 n005 n006 n007 n008
0079 0080 0081 0082 0083 0085 0086 0093 0094 0095 0096 0099 0100
m001 m002 m003 m004 m006 m007
so08 so09 so11
'

negative_cases='
so07 so10
'

total=0
failures=0
for case_id in $cases; do
  input="$suite/expand/$case_id-in.jsonld"
  expected="$suite/expand/$case_id-out.jsonld"
  actual="$root/.cache/odin-rdf-jsonld-expand-$case_id.actual.jsonld"
  if ! "$runner" "$input" "https://w3c.github.io/json-ld-api/tests/expand/$case_id-in.jsonld" "$suite" > "$actual" || ! jq -S -c . "$actual" > "$actual.canonical" || ! jq -S -c . "$expected" > "$expected.canonical" || ! diff -u "$expected.canonical" "$actual.canonical"; then
    failures=$((failures + 1))
  fi
  total=$((total + 1))
done

for case_id in $negative_cases; do
  input="$suite/expand/$case_id-in.jsonld"
  if "$runner" "$input" "https://w3c.github.io/json-ld-api/tests/expand/$case_id-in.jsonld" "$suite" >/dev/null 2>&1; then
    failures=$((failures + 1))
  fi
  total=$((total + 1))
done

printf 'W3C JSON-LD expansion core: %d cases, %d failures\n' "$total" "$failures"
test "$total" -eq 78
test "$failures" -eq 0
