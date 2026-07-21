#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
suite=$("$root/scripts/fetch-w3c-jsonld-tests.sh")
runner="$root/.cache/odin-rdf-w3c-jsonld-runner"
cli="$root/.cache/odin-rdf"
mkdir -p "$root/.cache"

odin build "$root/tests/w3c/jsonld_runner" -out:"$runner"
odin build "$root/cmd/odin-rdf" -out:"$cli"

# The W3C generalized-RDF evaluations compare datasets, not incidental blank
# node labels. Canonicalize labels by first appearance in sorted statements for
# the two explicitly generalized vectors; ordinary vectors retain their normal
# structural or semantic comparison paths below.
canonicalize_generalized() {
  sort "$1" | awk '
    function canonical(label) {
      if (!(label in labels)) {
        labels[label] = "_:g" next_label
        next_label += 1
      }
      return labels[label]
    }
    {
      remaining = $0
      output = ""
      while (match(remaining, /_:[A-Za-z0-9._-]+/)) {
        output = output substr(remaining, 1, RSTART - 1) canonical(substr(remaining, RSTART, RLENGTH))
        remaining = substr(remaining, RSTART + RLENGTH)
      }
      print output remaining
    }
  '
}

cases='
0001 0002 0003 0004 0005 0006 0007 0008 0009 0010 0011 0012 0013 0014 0015
0016 0017 0018 0019 0020 0022 0023 0024 0025 0026 0027 0028 0029 0030 0031
0032 0033 0034 0035 0036 0113 0114 0115 0116 0117 0118 0119 0120 0121 0122 0123
0124 0125 0126 0127 0128 0129 0130 0131 0132 0133
di01 di02 di03 di04 di05 di06 di07 di09 di10 di11 di12
c001 c002 c003 c004 c005 c013 c014 c018 c019 c023 c024 c027 c031 c037 c038
n006 n007 n008
n001 n002 n003 n004 n005
li01 li02 li03 li04 li05
li06 li07 li08 li09 li10 li11 li12 li13 li14
js01 js02 js03 js04 js05 js06 js07 js08 js09 js10 js11 js12 js13 js14 js15 js16 js17 js18 js19 js20 js21 js22 js23
m001 m002
e001 e002 e003 e004 e005 e006 e007 e008 e009 e010 e011 e012 e013 e014 e015 e016 e017 e018 e019 e020 e021 e022 e023 e024 e025 e026 e027 e028 e029 e030 e031 e032 e033 e034 e035 e036 e037 e038 e039 e040 e041 e042 e043 e044 e045 e046 e047 e048 e049 e050 e051 e052 e053 e054 e055 e056 e057 e058 e059 e060 e061 e062 e063 e064 e065 e066 e067 e068 e069 e070 e071 e072 e073 e074 e075 e076 e077 e078 e079 e080 e081 e082 e083 e084 e085 e086 e087 e088 e089 e090 e091 e092 e093 e094 e095 e096 e097 e098 e099 e100 e101 e102 e103 e104 e105 e106 e107 e108 e109 e110 e111 e112 e113 e114 e117 e118 e119 e120 e121 e122 e124 e125 e126 e127 e128 e129 e130
m003 m004 m005 m006 m007 m008 m012 m017 m018 m019
m009 m010 m011 m013 m014 m015 m016
so05 so06 so08 so09 so11
pr02 pr06 pr10 pr13 pr14 pr15 pr16 pr19 pr22 pr23 pr24 pr25 pr27 pr29 pr30 pr34 pr35 pr36 pr37 pr38 pr39 pr40 pr41 pr43
pi06 pi07 pi08 pi09 pi10 pi11
p001 p002 p003 p004
in01 in02 in03 in04 in05 in06
c006 c007 c008 c009 c010 c011 c012 c015 c016 c017 c020 c021 c022 c025 c034 c035 c036
c026 c028
rt01
tn02
wf01 wf02 wf03 wf04 wf05 wf07
'

negative_cases='di08 e123 m020 so01 so02 so03 c029 pi01 tn01 ep02 er21 er42 en04 en06 in08 in09 er13 er23 er37 er38 er39 er41 er14 er17 er25 er36 er50 er24 er31 er32 er35 e115 e116 er19 er20 er43 er56 pr33 pi03 er26 er44 er48 er49 er52'

total=0
failures=0
for case_id in $cases; do
  input="$suite/toRdf/$case_id-in.jsonld"
  expected="$suite/toRdf/$case_id-out.nq"
  actual="$root/.cache/odin-rdf-jsonld-$case_id.actual.nq"
  expected_sorted="$root/.cache/odin-rdf-jsonld-$case_id.expected.sorted.nq"
  actual_sorted="$root/.cache/odin-rdf-jsonld-$case_id.actual.sorted.nq"
  direction=''
	  generalized=false
  base="https://w3c.github.io/json-ld-api/tests/toRdf/$case_id-in.jsonld"
  case "$case_id" in m005) base="http://example.org/" ;; e076|e089|e090) base="http://example/base/" ;; li13|li14) base="http://example.com/" ;; esac
  semantic_compare=false
  case "$case_id" in c014|c018|c024|li11) semantic_compare=true ;; esac
  case "$case_id" in
    di09|di10) direction=i18n-datatype ;;
    di11|di12) direction=compound-literal ;;
    0118|e075) direction=generalized-rdf ; generalized=true ;;
    e026|e071) direction=json-ld-1.0 ;;
    e077) direction=expand-context-e077 ;;
    c001|c002|c003|c005|c006|c007|c008|c009|c010|c011|c012|c013|c015|c016|c017|c019|c020|c021|c022|c023|c025|c026|c027|c028|c034|c035|c036|c038|n001|n002|n003|n004|n005|n006|n007|n008|li01|li02|li03|li04|li05|li06|li07|li08|li09|li10|in01|in02|in03|in04|in05|in06|tn02|js01|js02|js03|js04|js05|js06|js07|js08|js09|js10|js11|js12|js13|js14|js15|js16|js17|js18|js19|js20|js21|js22|js23|di*|e001|e002|e003|e004|e005|e006|e007|e008|e009|e010|e011|e012|e013|e014|e015|e016|e017|e018|e019|e020|e021|e022|e023|e024|e025|e026|e027|e028|e029|e030|e031|e032|e033|e034|e035|e036|e037|e038|e039|e040|e041|e042|e043|e044|e045|e046|e047|e048|e049|e050|e051|e052|e053|e054|e055|e056|e057|e058|e059|e060|e061|e062|e063|e064|e065|e066|e067|e068|e069|e070|e071|e072|e073|e074|e078|e079|e080|e081|e082|e083|e084|e085|e086|e087|e088|e091|e092|e093|e094|e095|e096|e097|e098|e099|e100|e101|e102|e103|e104|e105|e106|e107|e108|e109|e110|e113|e114|e117|e118|e119|e120|e121|e122|e124|e125|e126|e127|e128|e129|e130|m001|m002|m003|m004|m006|m007|m008|m009|m010|m011|m012|m013|m014|m015|m016|m017|m018|m019|so05|so06|so08|so09|so11|pr02|pr06|pr10|pr13|pr14|pr15|pr16|pr19|pr22|pr23|pr24|pr25|pr27|pr29|pr30|pr34|pr35|pr36|pr37|pr38|pr39|pr40|pr41|pr43|pi06|pi07|pi08|pi09|pi10|pi11|p001|p002|p003|p004) semantic_compare=true ;;
  esac
  run_ok=true
  if ! "$runner" "$input" "$base" "$suite" $direction > "$actual"; then
    run_ok=false
  elif [ "$generalized" = true ]; then
    canonicalize_generalized "$expected" > "$expected_sorted"
    canonicalize_generalized "$actual" > "$actual_sorted"
    diff -u "$expected_sorted" "$actual_sorted" || run_ok=false
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
  mode=''
  case "$case_id" in so01|c029|pi01|tn01|ep02|er21|er42|er24|er32|e115|e116) mode=json-ld-1.0 ;; esac
  if "$runner" "$input" "https://w3c.github.io/json-ld-api/tests/toRdf/$case_id-in.jsonld" "$suite" $mode >/dev/null 2>&1; then
    failures=$((failures + 1))
  fi
  total=$((total + 1))
done

printf 'W3C JSON-LD to-RDF core: %d cases, %d failures\n' "$total" "$failures"
test "$total" -eq 389
test "$failures" -eq 0
