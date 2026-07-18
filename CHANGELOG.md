# Changelog

This project follows [Semantic Versioning](https://semver.org/).

## Unreleased

- Add `trig.format_quads`, an atomic batch formatter for complete RDF datasets.
  It groups default and named graphs, deterministically orders and deduplicates
  quads, infers safe prefixes including graph names, and rejects ambiguous
  blank-node labels across source scopes.
- Extend `odin-rdf format` to infer Turtle or TriG file input, require an
  explicit syntax for standard input, and use separate `--max-triples` and
  `--max-quads` retention limits.

## 0.13.0 - 2026-07-18

- Add a streaming-safe TriG writer with explicit Turtle-compatible prefix
  declarations, atomic quad serialization, canonical IRIREF fallback, and one
  independent named-graph block per input quad.
- Allow TriG conversion targets and `.trig` output inference without retaining
  or regrouping a dataset. Named graphs now preserve losslessly to TriG as well
  as N-Quads.

## 0.12.0 - 2026-07-18

- Add bounded RDF 1.1 TriG-to-RDF input with default and named graph support,
  `.trig` conversion inference, explicit token/prefix/nesting/quad limits, and
  loss-aware conversion to N-Quads.
- Add a pinned 355-case W3C TriG gate that verifies memory and bounded-reader
  paths with blank-node-aware dataset isomorphism.
- Add a bounded, owned dataset collector that copies callback-scoped RDF terms,
  preserves source order and duplicates, and exposes explicit quad admission
  limits without becoming a graph-store API.

## 0.11.1 - 2026-07-18

- Correct public status text after the `0.11.0` RDF/XML release.

## 0.11.0 - 2026-07-18

- Add bounded RDF/XML-to-RDF conversion with namespace, base-IRI, language,
  node/property element, collection, reification, and default-graph support.
- Add `.rdf`, `.rdfxml`, and `.xml` input inference plus a pinned 169-case
  RDF/XML core gate. Markup-bearing XML Literals remain explicitly unsupported
  until canonical XML handling is added.

## 0.10.0 - 2026-07-18

- Add bounded JSON-LD-to-RDF dataset processing with local contexts, opt-in
  remote document loading, explicit document/context/quad limits, and
  N-Triples/N-Quads/Turtle conversion targets.
- Add `.jsonld` and `.json` conversion inference plus `--max-document-bytes`.

## 0.9.1 - 2026-07-18

- Add a reproducible batch Turtle formatter benchmark to the quality gate.
- Document formatter peak-memory behavior and how to set a deployment-specific
  `--max-triples` admission policy.

## 0.9.0 - 2026-07-18

- Let `odin-rdf convert` infer `.nt`, `.nq`, and `.ttl` file formats while
  retaining explicit `--from`/`--to` overrides and strict format requirements
  for standard streams and unrecognized extensions.

## 0.8.0 - 2026-07-18

- Add `convert.Reader_Limits` and `odin-rdf convert` limits for records,
  N-Triples/N-Quads physical lines, and Turtle top-level statements.
- Add a conversion example with an explicit resource policy.

## 0.7.1 - 2026-07-18

- Add `odin-rdf format --max-triples N` to bound the command's retained Turtle
  graph before formatting. The limit rejects input atomically and preserves an
  existing target file.
- Add a runnable batch Turtle formatter example.

## 0.7.0 - 2026-07-18

- Add `turtle.format_triples`, an atomic batch formatter that groups triples,
  uses Turtle predicate/object-list syntax, emits `a` for valid `rdf:type`,
  removes exact duplicates, and produces deterministic output.
- Add safe automatic prefix inference with familiar RDF, RDFS, XSD, OWL, SKOS,
  and Dublin Core labels plus deterministic generated labels.
- Add `odin-rdf format` for Turtle input with atomic file replacement,
  explicit-prefix control, and safe blank-node scope collision rejection.
- Preserve writer validation when using `a`, improve formatter lookup scaling,
  and add formatter round-trip and CLI failure-atomicity regression tests.

## 0.6.0 - 2026-07-18

- Add `rdf/convert`, a streaming adapter for N-Triples, N-Quads, and Turtle
  readers and writers. It rejects named-graph conversions that would lose RDF
  dataset information.
- Add the `odin-rdf convert` command with stdin/stdout, explicit Turtle prefix
  declarations, source-location diagnostics, and atomic file replacement.

## 0.5.0 - 2026-07-18

- Add a streaming-safe Turtle writer with explicit prefix declarations,
  deterministic longest-namespace compaction, typed-literal datatype
  compaction, and canonical IRIREF fallback.
- Add a Turtle-to-Turtle streaming conversion example and writer documentation.

## 0.4.1 - 2026-07-18

- Correct the Turtle W3C documentation after the 313-case gate landed.
- Run the Turtle example in the cross-platform CI matrix.
- Add a public API reference, benchmark comparison baseline, and release
  checklist.

## 0.4.0 - 2026-07-17

- Define the RDF 1.1 Turtle parser API, streaming architecture, transient
  parse-state model, resource limits, and 313-case W3C conformance gate.
- Add pinned Turtle manifest inventory, test-only RDF graph isomorphism, and a
  relative-capable internal IRIREF decoder while preserving absolute-IRI policy
  for N-Triples and N-Quads.
- Add an RDF 1.1 Turtle parser with directives, relative IRI resolution,
  prefixed names, literal shorthands, property lists, collections, bounded
  reader parsing, statement-atomic emission, and all 313 pinned W3C cases
  passing through memory and 1-byte, 7-byte, and default reader chunks.

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
