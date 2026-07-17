# W3C conformance tests

This directory integrates the official `w3c/rdf-tests` RDF 1.1 N-Triples syntax manifest. Test data is not vendored. The runner downloads a pinned upstream commit instead:

```sh
./scripts/run-w3c-tests.sh
```

The suite is pinned to commit `d3e844aaa3e2f2b5250f2d1c988ce58870d6bc86` and contains 43 positive and 29 negative syntax cases. Every case runs through the in-memory parser and the streaming reader with 1-byte, 7-byte, and default-size chunks. Every positive case also completes a parse → write → parse round trip. Downloaded files are cached under `.cache/`.
