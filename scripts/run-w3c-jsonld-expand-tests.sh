#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
suite=$("$root/scripts/fetch-w3c-jsonld-tests.sh")
runner="$root/.cache/odin-rdf-w3c-jsonld-expand-runner"
compare_runner="$root/.cache/odin-rdf-w3c-json-compare-runner"
mkdir -p "$root/.cache"

odin build "$root/tests/w3c/jsonld_expand_runner" -out:"$runner"
odin build "$root/tests/w3c/json_compare_runner" -out:"$compare_runner"

# The document-level core targets aliases, scalar/value expansion, @set,
# @list, language/type coercion, reverse properties, transparent nesting,
# graph expansion, sourced-context @import overrides, protected source
# definitions, and non-propagating scoped contexts.
cases='
0001 0002 0003 0004 0005 0006 0007 0008 0009 0010
0011 0012 0013 0014 0015 0016 0017 0018 0019 0020
0021 0022 0023 0024 0025 0026 0027 0028 0029 0030
0031 0032 0033 0034 0035 0036 0037 0038 0039 0040
0041 0042 0043 0044 0045 0046 0047 0048 0049 0050 0051 0052 0053 0054 0055 0056 0057 0058 0059 0060 0061 0062 0063 0064 0065 0066 0067 0068 0069 0070 0071 0072 0073 0074 0075 0076 0078
0077
0079 0080 0081 0082 0083 0085 0086 0093 0094 0095 0096 0099 0100
0084 0087 0088 0089 0090 0098 0101 0105 0106
0091 0092 0097 0102 0103 0104 0107 0108 0109 0110 0111 0112 0113 0117 0118 0119 0120 0121 0124 0125
0114 0122 0126 0127 0128 0129 0130 0131
c001 c002 c003 c004 c005 c006 c007 c008 c009 c010 c011 c012 c015 c016 c017 c019 c020 c021 c022 c025
c013 c014 c018
c023 c024
li01 li02 li03 li04 li05 li06 li07 li08 li09 li10
c031 c034 c035 c036 c037 c038
in01 in02 in03 in04 in05
in06
js01 js02 js03 js04 js05 js06 js07 js08 js09 js10 js11 js12 js13 js14 js15 js16 js17 js18 js19 js20 js22 js23
js21
l001
p001 p002 p003 p004
pi06 pi07 pi08 pi09 pi10 pi11
pr02 pr06 pr10 pr13 pr14 pr15 pr16 pr19 pr22 pr23 pr24 pr25 pr27 pr29 pr30 pr34 pr35 pr36 pr37 pr38 pr39 pr40 pr41 pr43
tn02
n001 n002 n003 n004 n005 n006 n007 n008
0079 0080 0081 0082 0083 0085 0086 0093 0094 0095 0096 0099 0100
m001 m002 m003 m004 m005 m006 m007 m008 m009 m010 m011 m012 m013 m014 m015 m016 m017 m018 m019
so08 so09 so11
c026 c027 c028 so05 so06
di01 di02 di03 di04 di05 di06 di07
'

negative_cases='
so01 so02 so03 so07 so10 c029 c030 pi01 tn01 0115 0116 ep02 er21 er42 es01 di08 di09 m020 0123
'

total=0
failures=0
for case_id in $cases; do
  input="$suite/expand/$case_id-in.jsonld"
  expected="$suite/expand/$case_id-out.jsonld"
  actual="$root/.cache/odin-rdf-jsonld-expand-$case_id.actual.jsonld"
  base="https://w3c.github.io/json-ld-api/tests/expand/$case_id-in.jsonld"
  mode=''
  case "$case_id" in 0076) base="http://example/base/" ;; 0089|0090) base="http://example/base/" ;; m005) base="http://example.org/" ;; esac
  case "$case_id" in 0077) mode=expand-context-0077 ;; esac
  if ! "$runner" "$input" "$base" "$suite" $mode > "$actual" || ! "$compare_runner" "$expected" "$actual"; then
    failures=$((failures + 1))
  fi
  total=$((total + 1))
done

for case_id in $negative_cases; do
  input="$suite/expand/$case_id-in.jsonld"
  mode=''
  case "$case_id" in so01|c029|pi01|tn01|0115|0116|ep02|er21|er42|es01) mode=json-ld-1.0 ;; esac
  if "$runner" "$input" "https://w3c.github.io/json-ld-api/tests/expand/$case_id-in.jsonld" "$suite" $mode >/dev/null 2>&1; then
    failures=$((failures + 1))
  fi
  total=$((total + 1))
done

printf 'W3C JSON-LD expansion core: %d cases, %d failures\n' "$total" "$failures"
test "$total" -eq 308
test "$failures" -eq 0
