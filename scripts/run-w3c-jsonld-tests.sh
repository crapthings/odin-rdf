#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
suite=$("$root/scripts/fetch-w3c-jsonld-tests.sh")
runner="$root/.cache/odin-rdf-w3c-jsonld-runner"
cli="$root/.cache/odin-rdf"
mkdir -p "$root/.cache"

odin build "$root/tests/w3c/jsonld_runner" -out:"$runner"
odin build "$root/cmd/odin-rdf" -out:"$cli"

cases='
0001 0002 0003 0004 0005 0006 0007 0008 0009 0010 0011 0012 0013 0014 0015
0016 0017 0018 0019 0020 0022 0023 0024 0025 0026 0027 0028 0029 0030 0031
0032 0033 0034 0035 0036 0113 0114 0115 0116 0117 0119 0120 0121 0122 0123
0124 0125 0126 0127 0128 0129 0130 0131 0132 0133
di01 di02 di03 di04 di05 di06 di07 di09 di10 di11 di12
c001 c002 c003 c005 c013 c019 c023
m001 m002
e003 e004 e008 e014 e015 e016 e023 e027 e036 e038 e043 e046 e047 e048 e050 e056 e060 e061 e065 e071 e072 e079 e080 e081 e082 e083 e084 e085 e086 e087 e088 e091 e092 e093 e094 e095 e096 e097 e098 e099 e100 e101 e102 e103 e104 e105 e106 e107 e108 e109 e110 e113 e114 e117 e118 e119 e120 e121 e122 e124 e125 e126 e127 e128 e129 e130
m003 m004 m006 m007 m008 m012 m017 m018 m019
'

negative_cases='di08 e123 m020'

total=0
failures=0
for case_id in $cases; do
  input="$suite/toRdf/$case_id-in.jsonld"
  expected="$suite/toRdf/$case_id-out.nq"
  actual="$root/.cache/odin-rdf-jsonld-$case_id.actual.nq"
  expected_sorted="$root/.cache/odin-rdf-jsonld-$case_id.expected.sorted.nq"
  actual_sorted="$root/.cache/odin-rdf-jsonld-$case_id.actual.sorted.nq"
  direction=''
	semantic_compare=false
  case "$case_id" in
    di09|di10) direction=i18n-datatype ;;
    di11|di12) direction=compound-literal ;;
    c001|c002|c003|c005|c013|c019|c023|di*|e003|e004|e008|e014|e015|e016|e023|e027|e036|e038|e043|e046|e047|e048|e050|e056|e060|e061|e065|e071|e072|e079|e080|e081|e082|e083|e084|e085|e086|e087|e088|e091|e092|e093|e094|e095|e096|e097|e098|e099|e100|e101|e102|e103|e104|e105|e106|e107|e108|e109|e110|e113|e114|e117|e118|e119|e120|e121|e122|e124|e125|e126|e127|e128|e129|e130|m001|m002|m003|m004|m006|m007|m008|m012|m017|m018|m019) semantic_compare=true ;;
  esac
  run_ok=true
  if ! "$runner" "$input" "https://w3c.github.io/json-ld-api/tests/toRdf/$case_id-in.jsonld" "$suite" $direction > "$actual"; then
    run_ok=false
  elif [ -n "$direction" ] || [ "$semantic_compare" = true ]; then
    "$cli" compare "$actual" "$expected" --max-quads 10000 --max-records 10000 >/dev/null || run_ok=false
  elif ! sort "$expected" > "$expected_sorted" || ! sort "$actual" > "$actual_sorted" || ! diff -u "$expected_sorted" "$actual_sorted"; then
    run_ok=false
  fi
  if [ "$run_ok" = false ]; then
    failures=$((failures + 1))
  fi
  total=$((total + 1))
done

for case_id in $negative_cases; do
  input="$suite/toRdf/$case_id-in.jsonld"
  if "$runner" "$input" "https://w3c.github.io/json-ld-api/tests/toRdf/$case_id-in.jsonld" "$suite" >/dev/null 2>&1; then
    failures=$((failures + 1))
  fi
  total=$((total + 1))
done

printf 'W3C JSON-LD to-RDF core: %d cases, %d failures\n' "$total" "$failures"
test "$total" -eq 153
test "$failures" -eq 0
