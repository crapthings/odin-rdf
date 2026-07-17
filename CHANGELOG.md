# Changelog

This project follows [Semantic Versioning](https://semver.org/).

## 0.1.0 - 2026-07-17

Initial public release.

- Add an RDF 1.1 N-Triples parser with strict grammar validation for UTF-8 input, IRI references, blank-node labels, language tags, and escapes.
- Add bounded-memory `io.Reader` parsing with line and triple limits.
- Add explicit simple, language-tagged, and typed literal constructors.
- Add syntax-independent RDF term and triple structure validation.
- Preserve document-local blank-node identity across in-memory and streaming parser calls.
- Add stable, allocation-free messages for every public error enum.
- Reject invalid negative reader limits instead of silently applying defaults.
- Add an atomic N-Triples writer with parser/writer round-trip coverage.
- Pass all 72 pinned W3C RDF 1.1 N-Triples syntax tests through the in-memory and streaming parser paths.
- Add Linux, macOS, and Windows CI, AddressSanitizer tests, examples, and a parser benchmark.
