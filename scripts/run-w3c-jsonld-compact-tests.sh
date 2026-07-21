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
# corpus. This covers language maps and semantic index-map handling. Ordinary
# @index annotations are RDF-invisible, so their reconstruction is exercised
# only when the original source document is explicitly supplied to compaction.
cases='
0001 0002 0003 0004 0005 0006 0007 0008 0009 0010 0011 0012 0013 0014 0015 0016 0017 0018
0019 0020 0021 0022 0023 0024 0025 0026 0027 0028 0029 0030 0031 0032
0033 0034 0035 0036 0037 0038 0038a 0039 0040 0041 0042 0043 0044 0045 0046 0047 0048 0049 0050
0051 0052 0053 0054 0055 0056 0057 0058 0059 0060 0061 0062 0063 0064 0065
0066 0067 0068 0069 0070 0071 0072 0073 0074 0075 0076 0077 0078 0079 0080 0081 0082 0083 0084 0085 0086 0087 0088 0089 0090 0091 0092 0093 0094 0095 0096 0097 0098 0099 0100 0101 0102 0103 0104 0105 0106 0107 0108 0109 0110 0111 0112 0113 0114
di01 di02 di03 di04 di05 di06 di07
c001 c002 c003 c004 c005 c006 c007 c008 c009 c010 c011 c012 c013 c014 c015 c016 c017 c018 c019 c020 c021 c022 c023 c024 c025 c026 c027 c028 in01 in02 in03 in04 in05 js01 js02 js03 js04 js05 js06 js07 js08 js09 js10 js11 la01 li01 li02 li03 li04 li05 m001 m002 m003 m004 m005 m006 m007 m008 m009 m010 m011 m012 m013 m014 m015 m016 m017 m018 m019 m020 m021 m022 m023 n001 n002 n003 n004 n005 n006 n007 n008 n009 n010 n011 p001 p002 p003 p004 p005 p006 p007 p008 pi01 pi02 pi03 pi04 pi05 pi06 pr04 pr05 r001 r002 s001 s002 tn01 tn02 tn03
'

total=0
failures=0
for case_id in $cases; do
  input="$suite/compact/$case_id-in.jsonld"
  context="$suite/compact/$case_id-context.jsonld"
  expected="$suite/compact/$case_id-out.jsonld"
	case "$case_id" in
		0038a)
			input="$suite/compact/0038-in.jsonld"
			context="$suite/compact/0038-context.jsonld"
			;;
	esac
  actual="$root/.cache/odin-rdf-jsonld-compact-$case_id.actual.jsonld"
  direction=''
  base=''
  compare_base=''
  shape=''
	array_policy=''
	mode=''
  case "$case_id" in di*) direction=--rdf-direction-compound ;; esac
  case "$case_id" in
    0037|0075) base="--base https://w3c.github.io/json-ld-api/tests/compact/$case_id-in.jsonld"; compare_base="$base" ;;
    0038|0106) mode=--processing-mode-1.0 ;;
    r001) base="--base http://example.org/"; compare_base="$base" ;;
    0045|0062|0066|0111|c015|c025) base="--base https://w3c.github.io/json-ld-api/tests/compact/$case_id-in.jsonld" ;;
    c004) base="--base https://w3c.github.io/json-ld-api/tests/compact/$case_id-in.jsonld"; compare_base="$base" ;;
  esac
  case "$case_id" in 0070|0091|0093) array_policy=--preserve-arrays ;; esac
  case "$case_id" in 0001|0002|0003|0004|0005|0007|0008|0009|0010|0011|0012|0013|0014|0015|0016|0017|0018|0019|0020|0021|0025|0028|0029|0034|0038a|0043|0047|0053|0054|0055|0056|0058|0059|0063|0064|0071|0072|0073|0074|0076|0077|0078|0079|0080|0081|0082|0083|0084|0085|0086|0087|0088|0090|0092|0094|0095|0096|0097|0098|0099|0100|0101|0102|0103|0104|0105|0107|0108|0109|0110|0111|0112|0113|0114|c001|c002|c003|c004|c005|c006|c007|c008|c009|c010|c011|c012|c013|c014|c015|c016|c017|c018|c019|c020|c021|c022|c023|c024|c025|c026|c027|c028|di02|di03|di04|di05|di06|di07|in01|in02|in03|in04|in05|js01|js02|js03|js04|js05|js06|js07|js08|js09|js10|js11|li01|li02|li03|li04|li05|m001|m002|m003|m005|m006|m007|m011|m012|m013|m014|m015|m016|m017|m018|m019|m020|m021|m022|m023|n001|n002|n003|n004|n005|n006|n007|n008|n009|n010|n011|p001|p002|p003|p004|p005|p006|p007|p008|pi01|pi02|pi03|pi04|pi05|pi06|pr04|pr05|r001|r002|s001|s002|tn01|tn02|tn03) shape="--expect $expected" ;; esac
  case "$case_id" in 0006|0022|0023|0024|0026|0027|0030|0031|0032|0033|0035|0036|0037|0038|0039|0040|0041|0042|0044|0045|0046|0048|0049|0050|0051|0052|0057|0060|0061|0062|0065|0066|0067|0068|0069|0070|0075|0089|0091|0093|0106|di01|la01|m004|m008|m009|m010) shape="--expect $expected" ;; esac
  if ! "$runner" "$input" "$context" $base $direction $array_policy $mode $shape > "$actual" || ! "$cli" compare "$actual" "$expected" $compare_base --max-quads 10000 --max-records 10000 >/dev/null; then
    failures=$((failures + 1))
  fi
  total=$((total + 1))
done

# Negative W3C cases currently exercised by the bounded runner. JSON-LD 1.0
# cases explicitly select that processing mode; a successful compaction is a
# regression regardless of the package's stable diagnostic wording.
negative_cases='
e001 e002 en01 ep05 ep06 ep07 ep08 ep09 ep10 ep11 ep12 ep13 ep14 ep15 pr01 pr02 pr03
'
for case_id in $negative_cases; do
  input="$suite/compact/$case_id-in.jsonld"
  context="$suite/compact/$case_id-context.jsonld"
  mode=''
  case "$case_id" in e001|ep05|ep07|ep10|ep11|ep12|ep13|ep14|ep15) mode=--processing-mode-1.0 ;; esac
  if "$runner" "$input" "$context" $mode >/dev/null 2>&1; then
    failures=$((failures + 1))
  fi
  total=$((total + 1))
done

printf 'W3C JSON-LD compaction core: %d cases, %d failures\n' "$total" "$failures"
test "$total" -eq 246
test "$failures" -eq 0
