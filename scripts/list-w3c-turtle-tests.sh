#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
suite=$("$root/scripts/fetch-w3c-turtle-tests.sh")

awk -v suite="$suite" '
function iri_value(line, value) {
  value = line
  sub(/^[^<]*</, "", value)
  sub(/>.*/, "", value)
  return value
}
function emit() {
  if (kind == "") return
  result_path = result == "" ? "-" : suite "/" result
  print kind "\t" suite "/" action "\t" result_path
}
/^<#[^>]+>/ {
  emit()
  kind = ""
  action = ""
  result = ""
  in_entry = 1
}
in_entry && /rdf:type[[:space:]]+rdft:TestTurtle/ {
  if ($0 ~ /TestTurtleEval/) kind = "evaluation"
  else if ($0 ~ /TestTurtlePositiveSyntax/) kind = "positive"
  else if ($0 ~ /TestTurtleNegativeSyntax/) kind = "negative"
  next
}
kind != "" && /mf:action[[:space:]]+<[^>]+>/ { action = iri_value($0); next }
kind != "" && /mf:result[[:space:]]+<[^>]+>/ { result = iri_value($0); next }
END { emit() }
' "$suite/manifest.ttl"
