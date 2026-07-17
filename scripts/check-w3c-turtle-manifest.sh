#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
inventory=$("$root/scripts/list-w3c-turtle-tests.sh")

evaluation=$(printf '%s\n' "$inventory" | awk -F '\t' '$1 == "evaluation" { count += 1 } END { print count + 0 }')
positive=$(printf '%s\n' "$inventory" | awk -F '\t' '$1 == "positive" { count += 1 } END { print count + 0 }')
negative=$(printf '%s\n' "$inventory" | awk -F '\t' '$1 == "negative" { count += 1 } END { print count + 0 }')
total=$((evaluation + positive + negative))

printf 'W3C RDF 1.1 Turtle manifest: %d cases (%d evaluation, %d positive syntax, %d negative syntax)\n' \
  "$total" "$evaluation" "$positive" "$negative"

if [ "$evaluation" -ne 145 ] || [ "$positive" -ne 74 ] || [ "$negative" -ne 94 ]; then
  printf 'unexpected pinned Turtle suite shape\n' >&2
  exit 1
fi

tab=$(printf '\t')
printf '%s\n' "$inventory" | while IFS="$tab" read -r kind action result; do
  if [ ! -f "$action" ]; then
    printf 'missing Turtle %s action: %s\n' "$kind" "$action" >&2
    exit 1
  fi
  if [ "$kind" = evaluation ] && [ ! -f "$result" ]; then
    printf 'missing Turtle evaluation result: %s\n' "$result" >&2
    exit 1
  fi
done
