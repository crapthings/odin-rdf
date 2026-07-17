# Contributing

Thanks for contributing to `odin-rdf`.

Changes to a parser should include:

1. A focused positive or negative test that demonstrates the behavior.
2. A reference to the relevant W3C grammar production or specification section.
3. Successful `odin test rdf` and `odin test rdf/ntriples` runs.
4. For performance claims, the input data, compiler options, and results from at least three runs.

Public APIs must document ownership of strings and allocator-backed memory. Parsers should remain independent of any particular database; database integrations belong in consumers or separate adapter packages.
