# Changelog

This project follows [Semantic Versioning](https://semver.org/).

## Unreleased

- Define the RDF 1.1 Turtle parser API, streaming architecture, transient
  parse-state model, resource limits, and 313-case W3C conformance gate.

## 0.3.1 - 2026-07-17

- Preserve the first invalid Unicode-escape digit when a physical line ending also truncates the escape, keeping memory and reader diagnostics identical.

## 0.3.0 - 2026-07-17

- Add deterministic property tests that compare N-Triples and N-Quads memory parsing, bounded-reader chunking, and canonical writer round trips across generated RDF data and random byte input.
- Document the shared term-lexer migration contract and add a configurable, reproducible benchmark runner with a frozen before-refactor baseline.
- Extract syntax-neutral RDF term lexing into `rdf/internal/termlex` and migrate N-Triples without changing its public API, diagnostics, or callback lifetimes.
- Parse N-Quads directly through the shared term lexer, removing synthetic N-Triples reparsing while preserving conformance and improving parser throughput.
- Add mixed-term N-Triples and N-Quads benchmarks alongside the focused synthetic workloads.
- Add reproducible differential parser fuzzing with pull-request smoke coverage and a daily AddressSanitizer campaign.
- Align N-Triples memory and bounded-reader errors for physical line endings inside literals and Unicode escapes.

## 0.2.0 - 2026-07-17

- Add the RDF dataset `Quad` model with explicit default-graph representation.
- Add an RDF 1.1 N-Quads parser, bounded `io.Reader` path, and atomic writer.
- Pass all 87 pinned W3C RDF 1.1 N-Quads syntax tests through memory and streaming paths with writer round trips.
- Share blank-node scopes and proven N-Triples term parsing across syntax packages.

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
