#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
suite=$("$root/scripts/fetch-w3c-jsonld-tests.sh")
runner="$root/.cache/odin-rdf-w3c-jsonld-fromrdf-runner"
cli="$root/.cache/odin-rdf"
mkdir -p "$root/.cache"

odin build "$root/tests/w3c/jsonld_fromrdf_runner" -out:"$runner"
odin build "$root/cmd/odin-rdf" -out:"$cli"

# This is the JSON-LD 1.1 RDF-to-JSON-LD core before the directional-literal
# extension cases. The comparison intentionally canonicalizes the RDF datasets
# after parsing both JSON-LD documents, so object-member order and unrelated
# node ordering do not create false failures while list ordering remains RDF
# observable.
cases='
0001 0002 0003 0004 0005 0006 0007 0008 0009 0010 0011 0012 0013 0014
0015 0016 0017 0018 0019 0020 0021 0022 0023 0024 0025 0026 0027 0028
'

total=0
failures=0
for case_id in $cases; do
  flags=''
  case "$case_id" in
    0018|0027|0028) flags='--use-native-types' ;;
    0019) flags='--use-rdf-type' ;;
  esac
  input="$suite/fromRdf/$case_id-in.nq"
  expected="$suite/fromRdf/$case_id-out.jsonld"
  actual="$root/.cache/odin-rdf-jsonld-fromrdf-$case_id.actual.jsonld"
  if ! "$runner" "$input" $flags > "$actual" || ! "$cli" compare "$actual" "$expected" --max-quads 10000 --max-records 10000 >/dev/null; then
    failures=$((failures + 1))
  fi
  total=$((total + 1))
done

printf 'W3C JSON-LD RDF-to-JSON-LD core: %d cases, %d failures\n' "$total" "$failures"
test "$total" -eq 28
test "$failures" -eq 0
