#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
suite=$("$root/scripts/fetch-w3c-jsonld-tests.sh")
runner="$root/.cache/odin-rdf-w3c-jsonld-web-runner"
compare_runner="$root/.cache/odin-rdf-w3c-json-compare-runner"
mkdir -p "$root/.cache"

odin build "$root/tests/w3c/jsonld_web_runner" -out:"$runner"
odin build "$root/tests/w3c/json_compare_runner" -out:"$compare_runner"

total=0
failures=0

run_positive() {
  case_id=$1
  input=$2
  content_type=$3
  final=$4
  expected=$5
  shift 5
  actual="$root/.cache/odin-rdf-jsonld-remote-$case_id.actual.jsonld"
  if ! "$runner" remote-expand "$suite" "$input" "$content_type" "$final" "$@" > "$actual" || ! "$compare_runner" "$expected" "$actual"; then
    failures=$((failures + 1))
  fi
  total=$((total + 1))
}

run_negative() {
  case_id=$1
  input=$2
  content_type=$3
  final=$4
  shift 4
  actual="$root/.cache/odin-rdf-jsonld-remote-$case_id.actual.jsonld"
  if "$runner" remote-expand "$suite" "$input" "$content_type" "$final" "$@" > "$actual" 2>/dev/null; then
    failures=$((failures + 1))
  fi
  total=$((total + 1))
}

run_positive 0001 remote-doc/0001-in.jsonld application/ld+json - "$suite/remote-doc/0001-out.jsonld"
run_positive 0002 remote-doc/0002-in.json application/json - "$suite/remote-doc/0002-out.jsonld"
run_positive 0003 remote-doc/0003-in.jldt application/jldTest+json - "$suite/remote-doc/0003-out.jsonld"
run_negative 0004 remote-doc/0004-in.jldte application/jldTest -
run_positive 0005 remote-doc/0005-in.jsonld application/ld+json remote-doc/0001-in.jsonld "$suite/remote-doc/0001-out.jsonld"
run_positive 0006 remote-doc/0006-in.jsonld application/ld+json remote-doc/0001-in.jsonld "$suite/remote-doc/0001-out.jsonld"
run_positive 0007 remote-doc/0007-in.jsonld application/ld+json remote-doc/0001-in.jsonld "$suite/remote-doc/0001-out.jsonld"
run_negative 0008 remote-doc/missing-in.jsonld application/ld+json -
run_positive 0009 remote-doc/0009-in.jsonld application/ld+json - "$suite/remote-doc/0009-out.jsonld" '<0009-context.jsonld>; rel="http://www.w3.org/ns/json-ld#context"'
run_positive 0010 remote-doc/0010-in.json application/json - "$suite/remote-doc/0010-out.jsonld" '<0010-context.jsonld>; rel="http://www.w3.org/ns/json-ld#context"'
run_positive 0011 remote-doc/0011-in.jldt application/jldTest+json - "$suite/remote-doc/0011-out.jsonld" '<0011-context.jsonld>; rel="http://www.w3.org/ns/json-ld#context"'
run_negative 0012 remote-doc/0012-in.json application/json - '<0012-context1.jsonld>; rel="http://www.w3.org/ns/json-ld#context"' '<0012-context2.jsonld>; rel="http://www.w3.org/ns/json-ld#context"'
run_positive 0013 remote-doc/0013-in.json application/json - "$suite/remote-doc/0013-out.jsonld" '<0013-context.html>; rel="http://www.w3.org/ns/json-ld#context"'
run_positive la01 remote-doc/la01-in.html text/html - "$suite/remote-doc/la01-out.jsonld" '<la01-alternate.jsonld>; rel="alternate"; type="application/ld+json"'
run_positive la02 remote-doc/la02-in.jsonld application/ld+json - "$suite/remote-doc/la02-out.jsonld" '<la02-alternate.jsonld>; rel="alternate"; type="application/ld+json"'
run_positive la03 remote-doc/la03-in.json application/json - "$suite/remote-doc/la03-out.jsonld" '<la03-alternate.json>; rel="alternate"; type="application/json"'
run_positive la04 remote-doc/la04-in.json application/json - "$suite/remote-doc/la04-out.jsonld" '<la04-alternate.jsonld>; rel="alternate"; type="application/ld+json"'
run_positive la05 remote-doc/la05-in.html text/html - "$suite/remote-doc/la05-out.jsonld" '<la05-alternate.jsonld>; rel="alternate"; type="application/ld+json"'

printf 'W3C JSON-LD remote document: %d cases, %d failures\n' "$total" "$failures"
test "$total" -eq 18
test "$failures" -eq 0
