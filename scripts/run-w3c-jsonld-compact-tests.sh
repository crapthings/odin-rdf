#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
suite=$("$root/scripts/fetch-w3c-jsonld-tests.sh")
runner="$root/.cache/odin-rdf-w3c-jsonld-compact-runner"
cli="$root/.cache/odin-rdf"
mkdir -p "$root/.cache"

odin build "$root/tests/w3c/jsonld_compact_runner" -out:"$runner"
odin build "$root/cmd/odin-rdf" -out:"$cli"

# Local-context compaction core selected from the pinned W3C JSON-LD 1.1 API
# corpus. This covers language maps and semantic index-map handling. An RDF
# dataset has no slot for ordinary @index annotations, so compaction never
# invents index keys that cannot be recovered from the source dataset.
cases='
0001 0002 0005 0006 0008 0009 0010 0011 0012 0013 0014 0015 0016 0017
0019 0020 0021 0022 0023 0024 0025 0026 0027 0028 0029 0030 0031 0032
0033 0034 0035 0036 0039 0040 0041 0042 0044 0046 0047 0048 0049 0050
0051 0052 0053 0054 0055 0056 0057 0058 0059 0060 0061 0063 0064 0065
0067 0068 0069 0070 0071 0073 0074 0076 0112 0113
di01 di02 di03 di04 di05 di06 di07
'

total=0
failures=0
for case_id in $cases; do
  input="$suite/compact/$case_id-in.jsonld"
  context="$suite/compact/$case_id-context.jsonld"
  expected="$suite/compact/$case_id-out.jsonld"
  actual="$root/.cache/odin-rdf-jsonld-compact-$case_id.actual.jsonld"
  direction=''
  case "$case_id" in di*) direction=--rdf-direction-compound ;; esac
  if ! "$runner" "$input" "$context" $direction > "$actual" || ! "$cli" compare "$actual" "$expected" --max-quads 10000 --max-records 10000 >/dev/null; then
    failures=$((failures + 1))
  fi
  total=$((total + 1))
done

printf 'W3C JSON-LD compaction core: %d cases, %d failures\n' "$total" "$failures"
test "$total" -eq 73
test "$failures" -eq 0
