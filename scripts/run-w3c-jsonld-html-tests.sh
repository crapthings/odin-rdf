#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
suite=$("$root/scripts/fetch-w3c-jsonld-tests.sh")
runner="$root/.cache/odin-rdf-w3c-jsonld-web-runner"
compare_runner="$root/.cache/odin-rdf-w3c-json-compare-runner"
cli="$root/.cache/odin-rdf"
mkdir -p "$root/.cache"

odin build "$root/tests/w3c/jsonld_web_runner" -out:"$runner"
odin build "$root/tests/w3c/json_compare_runner" -out:"$compare_runner"
odin build "$root/cmd/odin-rdf" -out:"$cli"

total=0
failures=0

run_json_positive() {
  case_id=$1
  mode=$2
  input=$3
  url=$4
  extract_all=$5
  expected=$6
  shift 6
  actual="$root/.cache/odin-rdf-jsonld-html-$case_id.actual.jsonld"
  if ! "$runner" "$mode" "$suite" "$input" "$url" "$extract_all" "$@" > "$actual" || ! "$compare_runner" "$expected" "$actual"; then
    failures=$((failures + 1))
  fi
  total=$((total + 1))
}

run_json_negative() {
  case_id=$1
  mode=$2
  input=$3
  url=$4
  extract_all=$5
  actual="$root/.cache/odin-rdf-jsonld-html-$case_id.actual.jsonld"
  if "$runner" "$mode" "$suite" "$input" "$url" "$extract_all" > "$actual" 2>/dev/null; then
    failures=$((failures + 1))
  fi
  total=$((total + 1))
}

run_rdf_positive() {
  case_id=$1
  input=$2
  url=$3
  extract_all=$4
  expected=$5
  actual="$root/.cache/odin-rdf-jsonld-html-$case_id.actual.nq"
  if ! "$runner" html-tordf "$suite" "$input" "$url" "$extract_all" > "$actual" || ! "$cli" compare "$actual" "$expected" --max-quads 10000 --max-records 10000 > /dev/null; then
    failures=$((failures + 1))
  fi
  total=$((total + 1))
}

run_rdf_negative() {
  case_id=$1
  input=$2
  url=$3
  extract_all=$4
  actual="$root/.cache/odin-rdf-jsonld-html-$case_id.actual.nq"
  if "$runner" html-tordf "$suite" "$input" "$url" "$extract_all" > "$actual" 2>/dev/null; then
    failures=$((failures + 1))
  fi
  total=$((total + 1))
}

html_url() {
  printf '%s/html/%s-in.html' 'https://w3c.github.io/json-ld-api/tests' "$1"
}

# Expansion: 21 official HTML Content Algorithm vectors.
run_json_positive te001 html-expand html/e001-in.html "$(html_url e001)" false "$suite/html/e001-out.jsonld"
run_json_positive tex01 html-expand html/e001-in.html "$(html_url e001)" false "$suite/html/e001-out.jsonld" application/xhtml+xml
run_json_positive te002 html-expand html/e002-in.html "$(html_url e002)" false "$suite/html/e002-out.jsonld"
run_json_positive te003 html-expand html/e003-in.html "$(html_url e003)#second" false "$suite/html/e003-out.jsonld"
run_json_positive te004 html-expand html/e004-in.html "$(html_url e004)" true "$suite/html/e004-out.jsonld"
run_json_positive te005 html-expand html/e005-in.html "$(html_url e005)" true "$suite/html/e005-out.jsonld"
run_json_negative te006 html-expand html/e006-in.html "$(html_url e006)" false
run_json_positive te007 html-expand html/e007-in.html "$(html_url e007)" true "$suite/html/e007-out.jsonld"
run_json_positive te010 html-expand html/e010-in.html "$(html_url e010)" false "$suite/html/e010-out.jsonld"
for case_id in 011 012 013 014 015 016 017; do
  fragment=''
  case "$case_id" in 011) fragment='#third' ;; 012|013) fragment='#first' ;; esac
  run_json_negative "te$case_id" html-expand "html/e$case_id-in.html" "$(html_url e$case_id)$fragment" false
done
run_json_positive te018 html-expand html/e018-in.html "$(html_url e018)" false "$suite/html/e018-out.jsonld"
for case_id in 019 020 021; do
  run_json_positive "te$case_id" html-expand "html/e$case_id-in.html" http://a.example.com/doc false "$suite/html/e$case_id-out.jsonld"
done
run_json_positive te022 html-expand html/e022-in.html "$(html_url e022)#second" false "$suite/html/e022-out.jsonld"

# Compaction and flattening: 9 official vectors.
for case_id in 001 002 003; do
  fragment=''
  if [ "$case_id" = 003 ]; then fragment='#second'; fi
  run_json_positive "tc$case_id" html-compact "html/c$case_id-in.html" "$(html_url c$case_id)$fragment" false "$suite/html/c$case_id-out.jsonld" "$suite/html/c$case_id-context.jsonld"
done
run_json_positive tc004 html-compact html/c004-in.html "$(html_url c004)" true "$suite/html/c004-out.jsonld" "$suite/html/c004-context.jsonld"
for case_id in 001 002 003 004; do
  fragment=''
  if [ "$case_id" = 003 ]; then fragment='#second'; fi
  run_json_positive "tf$case_id" html-flatten "html/f$case_id-in.html" "$(html_url f$case_id)$fragment" false "$suite/html/f$case_id-out.jsonld" "$suite/html/f$case_id-context.jsonld"
done
run_json_positive tf005 html-flatten html/f005-in.html "$(html_url f005)" true "$suite/html/f005-out.jsonld" "$suite/html/f005-context.jsonld"

# To-RDF: 20 official HTML Content Algorithm vectors, compared as RDF datasets.
for case_id in 001 002 003; do
  fragment=''
  if [ "$case_id" = 003 ]; then fragment='#second'; fi
  run_rdf_positive "tr$case_id" "html/r$case_id-in.html" "$(html_url r$case_id)$fragment" false "$suite/html/r$case_id-out.nq"
done
run_rdf_positive tr004 html/r004-in.html "$(html_url r004)" true "$suite/html/r004-out.nq"
run_rdf_positive tr005 html/r005-in.html "$(html_url r005)" true "$suite/html/r005-out.nq"
run_rdf_positive tr006 html/r006-in.html "$(html_url r006)" false "$suite/html/r006-out.nq"
run_rdf_positive tr007 html/r007-in.html "$(html_url r007)" true "$suite/html/r007-out.nq"
run_rdf_positive tr010 html/r010-in.html "$(html_url r010)" false "$suite/html/r010-out.nq"
for case_id in 011 012 013 014 015 016 017; do
  fragment=''
  case "$case_id" in 011) fragment='#third' ;; 012|013) fragment='#first' ;; esac
  run_rdf_negative "tr$case_id" "html/r$case_id-in.html" "$(html_url r$case_id)$fragment" false
done
run_rdf_positive tr018 html/r018-in.html "$(html_url r018)" false "$suite/html/r018-out.nq"
for case_id in 019 020 021; do
  run_rdf_positive "tr$case_id" "html/r$case_id-in.html" http://a.example.com/doc false "$suite/html/r$case_id-out.nq"
done
run_rdf_positive tr022 html/r022-in.html "$(html_url r022)#second" false "$suite/html/r022-out.nq"

printf 'W3C JSON-LD HTML: %d cases, %d failures\n' "$total" "$failures"
test "$total" -eq 50
test "$failures" -eq 0
