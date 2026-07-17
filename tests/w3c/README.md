# W3C conformance tests

This directory integrates the official `w3c/rdf-tests` RDF 1.1 N-Triples and N-Quads syntax manifests. Test data is not vendored. The runners download one pinned upstream commit instead:

```sh
./scripts/run-w3c-tests.sh
./scripts/run-w3c-nquads-tests.sh
./scripts/check-w3c-turtle-manifest.sh
```

The N-Triples gate covers 72 manifest cases. The N-Quads gate covers 87
manifest cases and runs positive inputs through parse-write-parse round trips.
Both gates exercise in-memory parsing and bounded-reader chunk sizes of 1 byte,
7 bytes, and the default buffer size.

The Turtle foundation currently inventories the pinned manifest's 313 cases
(145 evaluation, 74 positive syntax, and 94 negative syntax) without claiming
parser support. `tests/w3c/support` provides test-only RDF graph isomorphism for
comparing future Turtle evaluation output with expected N-Triples while
ignoring blank-node labels and triple order.
`scripts/list-w3c-turtle-tests.sh` emits a tab-separated inventory of case type,
action path, and expected-result path so the future runner does not infer test
semantics from filenames.

All suites are pinned to commit `d3e844aaa3e2f2b5250f2d1c988ce58870d6bc86`.
The N-Triples manifest contains 43 positive and 29 negative syntax cases. Every
N-Triples case runs through the in-memory parser and the streaming reader with
1-byte, 7-byte, and default-size chunks. Every positive case also completes a
parse → write → parse round trip. Downloaded files are cached under `.cache/`.
