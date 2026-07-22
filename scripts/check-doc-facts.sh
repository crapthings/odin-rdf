#!/bin/sh
set -eu

fail() {
	printf '%s\n' "$1" >&2
	exit 1
}

readme_release=$(sed -n 's/^\*\*Current release: `\([^`]*\)`\*\*.*/\1/p' README.md)
site_release=$(sed -n 's/.*>Version \([^<]*\)<.*/\1/p' docs/index.html)

[ -n "$readme_release" ] || fail "README release marker is missing"
[ -n "$site_release" ] || fail "landing-page release marker is missing"
[ "$readme_release" = "$site_release" ] || fail "README and landing-page releases differ"

grep -Fq -- 'Conformance breakdown — 2,432 passing pinned W3C gate cases' README.md || fail "README W3C total is missing"
grep -Fq -- 'W3C 2,432/2,432' docs/index.html || fail "landing-page W3C total is missing"
grep -Fq -- '| JSON-LD Remote Document / HTML Content Algorithms | 18 / 50 |' README.md || fail "README Web JSON-LD counts are missing"
grep -Fq -- 'runs all 18 official Remote' docs/jsonld-design.md || fail "Remote Document count is missing"
grep -Fq -- 'runs all 50 official HTML Content' docs/jsonld-design.md || fail "HTML count is missing"
grep -Fq -- 'odin run examples/jsonld_web' docs/releasing.md || fail "release example gate is missing"
grep -Fq -- 'odin check tests/w3c/jsonld_web_runner -vet -warnings-as-errors' docs/releasing.md || fail "release Web runner gate is missing"
grep -Fq -- './scripts/run-w3c-jsonld-remote-document-tests.sh' docs/releasing.md || fail "release Remote Document gate is missing"
grep -Fq -- './scripts/run-w3c-jsonld-html-tests.sh' docs/releasing.md || fail "release HTML gate is missing"
