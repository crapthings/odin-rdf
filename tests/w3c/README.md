# W3C conformance tests

This directory integrates the official `w3c/rdf-tests` RDF 1.1 N-Triples and N-Quads syntax manifests. Test data is not vendored. The runners download one pinned upstream commit instead:

```sh
./scripts/run-w3c-tests.sh
./scripts/run-w3c-nquads-tests.sh
./scripts/check-w3c-turtle-manifest.sh
./scripts/run-w3c-turtle-tests.sh
./scripts/run-w3c-rdfxml-tests.sh
```

The N-Triples gate covers 72 manifest cases. The N-Quads gate covers 87
manifest cases and runs positive inputs through parse-write-parse round trips.
Both gates exercise in-memory parsing and bounded-reader chunk sizes of 1 byte,
7 bytes, and the default buffer size.

The Turtle gate covers all 313 manifest cases: 145 evaluation, 74 positive
syntax, and 94 negative syntax tests. `tests/w3c/support` provides test-only RDF
graph isomorphism for comparing Turtle evaluation output with expected
N-Triples while ignoring blank-node labels and triple order.
`scripts/list-w3c-turtle-tests.sh` emits a tab-separated inventory of case type,
action path, and expected-result path so the runner does not infer test
semantics from filenames. The Turtle runner checks every case through memory
parsing and bounded-reader chunk sizes of 1 byte, 7 bytes, and the default size.
Evaluation cases compare the emitted triples with expected N-Triples by RDF
graph isomorphism. Negative cases require the memory and reader paths to agree
on error code and one-based source location.

All suites are pinned to commit `d3e844aaa3e2f2b5250f2d1c988ce58870d6bc86`.
The N-Triples manifest contains 43 positive and 29 negative syntax cases. Every
N-Triples case runs through the in-memory parser and the streaming reader with
1-byte, 7-byte, and default-size chunks. Every positive case also completes a
parse → write → parse round trip. Downloaded files are cached under `.cache/`.
# JSON-LD core selection

`../scripts/run-w3c-jsonld-tests.sh` pins the W3C JSON-LD API corpus and runs
all 451 JSON-LD-to-RDF evaluation cases. The adjacent Expansion and Flattening
gates run 398 executions (385 unique vectors) and 58 vectors. Compaction,
Framing, and RDF-to-JSON-LD each have dedicated pinned gates. The explicit Web
entry points are covered by 18 Remote Document vectors and all 50 HTML Content
Algorithm vectors through `run-w3c-jsonld-remote-document-tests.sh` and
`run-w3c-jsonld-html-tests.sh`. These JSON-LD gates remain a documented
implementation profile, not a claim of complete JSON-LD 1.1 API coverage.
Flattening emits expanded JSON-LD only; W3C vectors that require an output
context and `compactArrays` result shaping belong to the separate Compaction
workflow.

# RDF/XML core selection

`../scripts/run-w3c-rdfxml-tests.sh` runs 132 RDF/XML evaluation cases and 41
negative cases (173 total) from the same pinned corpus. Each case exercises the
memory parser plus 1-byte, 7-byte, and default reader chunks; evaluations use
RDF graph isomorphism against the expected N-Triples.

The selection includes the XML Literal namespace and canonicalization fixtures.
The parser preserves markup-bearing `rdf:parseType="Literal"` values as
`rdf:XMLLiteral` rather than flattening them to plain text.
