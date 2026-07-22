# Contributing

Thanks for contributing to `odin-rdf`.

Changes to a parser should include:

1. A focused positive or negative test that demonstrates the behavior.
2. A reference to the relevant W3C grammar production or specification section.
3. Successful core, affected syntax-package, and differential property tests (`odin test rdf`, `odin test rdf/ntriples`, `odin test rdf/nquads`, and `odin test tests/property`).
4. For performance claims, the input data, compiler options, and results from at least three runs.

Public APIs must document ownership of strings and allocator-backed memory. Parsers should remain independent of any particular database; database integrations belong in consumers or separate adapter packages.

Web JSON-LD changes must use deterministic callback-loader tests; do not add a
live-network test dependency. When changing that boundary, run
`odin check tests/w3c/jsonld_web_runner -vet -warnings-as-errors`,
`./scripts/run-w3c-jsonld-remote-document-tests.sh`, and
`./scripts/run-w3c-jsonld-html-tests.sh`.

Use `./scripts/run-benchmarks.sh` for parser performance comparisons and retain
the complete environment, configuration, and per-process output with the claim.
