#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
suite=$("$root/scripts/fetch-w3c-jsonld-tests.sh")
runner="$root/.cache/odin-rdf-w3c-jsonld-flatten-runner"
mkdir -p "$root/.cache"

odin build "$root/tests/w3c/jsonld_flatten_runner" -out:"$runner"

# This core covers node-map construction, embedded-node extraction, blank-node
# allocation, reverse properties, list preservation, index annotations, set
# de-duplication, and nested graph objects. JSON-LD 1.1 graph/id/type
# containers are gated separately with the context profile.
cases='
0001 0002 0003 0004 0005 0006 0007 0008 0009 0010
0011 0012 0013 0014 0015 0016 0017 0018 0019 0023
0020 0021 0027 0030 0031 0032 0033 0034 0035 0036
0037 0039 0040 0041 0042
0022 0024 0025 0026 0028 0043 0047 0048 0049
li01 li02 li03
in01 in02 in03 in04 in05
0038 0045
0046
in06
'

total=0
failures=0
for case_id in $cases; do
  input="$suite/flatten/$case_id-in.jsonld"
  expected="$suite/flatten/$case_id-out.jsonld"
  actual="$root/.cache/odin-rdf-jsonld-flatten-$case_id.actual.jsonld"
  if ! "$runner" "$input" "https://w3c.github.io/json-ld-api/tests/flatten/$case_id-in.jsonld" "$suite" > "$actual" || ! jq -S -c . "$actual" > "$actual.canonical" || ! jq -S -c . "$expected" > "$expected.canonical" || ! diff -u "$expected.canonical" "$actual.canonical"; then
    failures=$((failures + 1))
  fi
  total=$((total + 1))
done

printf 'W3C JSON-LD flattening core: %d cases, %d failures\n' "$total" "$failures"
test "$total" -eq 56
test "$failures" -eq 0
