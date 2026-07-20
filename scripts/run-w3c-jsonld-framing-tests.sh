#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
suite=$("$root/scripts/fetch-w3c-jsonld-framing-tests.sh")
runner="$root/.cache/odin-rdf-w3c-jsonld-frame-runner"
mkdir -p "$root/.cache"

odin build "$root/tests/w3c/jsonld_frame_runner" -out:"$runner"

# The initial Framing gate covers nested library embedding, no-match, default
# recursive embedding, explicit filtering, boolean @embed control, defaults,
# require-all matching, ID selection, multi-type matching, empty-frame
# selection, @set containers, protected empty contexts, @included node
# selection, and scoped named-graph / graph-container framing. The full policy
# matrix remains outside this bounded profile.
cases='
0001 0002 0003 0004 0005 0006 0007 0008
0009 0011 0012 0013 0014 0016 0017 0018 0019 0020 0022 0023 0024 0025 0026 0027
0028 0029 0030 0031 0032 0033 0034 0035 0036 0037 0038 0039 0040 0041 0042 0043 0044 0045 0046 0048 0049
0051 0055 0056 0057 0058 0059 0060 0062 0063 0064 0065 0066 0067 0068 0069 0070
0061
eo01 g001 g002 g003 g004 g005 g006 g007 g008 g009 p050 ra01 ra02
p020 p021 p049
in01 in02 in03
0047 0050 g010
'

total=0
failures=0
for case_id in $cases; do
  input="$suite/frame/$case_id-in.jsonld"
  frame="$suite/frame/$case_id-frame.jsonld"
  expected="$suite/frame/$case_id-out.jsonld"
  case "$case_id" in
    p020)
      input="$suite/frame/0020-in.jsonld"
      frame="$suite/frame/0020-frame.jsonld"
      expected="$suite/frame/p020-out.jsonld"
      ;;
    p021)
      input="$suite/frame/0021-in.jsonld"
      frame="$suite/frame/0021-frame.jsonld"
      expected="$suite/frame/p021-out.jsonld"
      ;;
    p049)
      input="$suite/frame/0049-in.jsonld"
      frame="$suite/frame/0049-frame.jsonld"
      expected="$suite/frame/p049-out.jsonld"
      ;;
  esac
  actual="$root/.cache/odin-rdf-jsonld-frame-$case_id.actual.jsonld"
  base="https://w3c.github.io/json-ld-framing/tests/frame/$case_id-in.jsonld"
  omit_graph=false
  legacy_mode=false
  case "$case_id" in
    0001|0002|0003|0004|0005|0006|0007|0008|0009|0016|0017|0018|0020|0022|0046|0049|0059) legacy_mode=true ;;
    0056|0057|0067) base="" ;;
    0065|0066) base="" ; omit_graph=true ;;
    0023|0031|0032|0033|0034|0035|0036|0037|0038|0039|0040|0041|0042|0043|0044|0045) omit_graph=true ;;
  esac
  run_ok=true
  if [ "$omit_graph" = true ] && [ "$legacy_mode" = true ]; then
    "$runner" "$input" "$frame" "$base" omit-graph json-ld-1.0 > "$actual" || run_ok=false
  elif [ "$omit_graph" = true ]; then
    "$runner" "$input" "$frame" "$base" omit-graph > "$actual" || run_ok=false
  elif [ "$legacy_mode" = true ]; then
    "$runner" "$input" "$frame" "$base" json-ld-1.0 > "$actual" || run_ok=false
  else
    "$runner" "$input" "$frame" "$base" > "$actual" || run_ok=false
  fi
  if [ "$run_ok" = false ] || ! jq -S -c . "$actual" > "$actual.canonical" || ! jq -S -c . "$expected" > "$expected.canonical" || ! diff -u "$expected.canonical" "$actual.canonical"; then
    failures=$((failures + 1))
  fi
  total=$((total + 1))
done

# The official manifest also defines three negative framing evaluations. They
# have no expected JSON document: successful framing is the failure condition.
for case_id in 0052 0053 0054; do
  input="$suite/frame/$case_id-in.jsonld"
  frame="$suite/frame/$case_id-frame.jsonld"
  base="https://w3c.github.io/json-ld-framing/tests/frame/$case_id-in.jsonld"
  actual="$root/.cache/odin-rdf-jsonld-frame-$case_id.actual.jsonld"
  if "$runner" "$input" "$frame" "$base" > "$actual" 2>/dev/null; then
    failures=$((failures + 1))
  fi
  total=$((total + 1))
done

printf 'W3C JSON-LD framing core: %d cases, %d failures\n' "$total" "$failures"
test "$total" -eq 87
test "$failures" -eq 0
