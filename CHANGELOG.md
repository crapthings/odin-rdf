# Changelog

This project follows [Semantic Versioning](https://semver.org/).

## Unreleased

- Retain owned keys while processing sourced JSON-LD contexts, so term
  definitions remain valid after the loaded JSON document is released.
- Resolve relative sourced term identifiers against an importing context's
  `@vocab`, as required when a source context is merged.
- Extend the JSON-LD Expansion gate with the W3C `so07`, `so10`, and `so11`
  source-context vectors. The gate now covers 78 vectors, including expected
  failures for protected-term redefinitions.
- Support JSON-LD 1.1 non-propagating scoped contexts in document Expansion,
  Flattening, and Framing. `@propagate: false` now restores the previous
  context at nested node objects, while type-scoped contexts are
  non-propagating unless they explicitly opt in.
- Extend the Expansion gate to 84 vectors with W3C property-, type-, embedded-,
  and sourced-context propagation coverage, plus invalid `@propagate` values.

## 0.25.0 - 2026-07-20

- Add bounded JSON-LD `@import` source contexts through the existing opt-in
  document loader. Imported definitions apply before definitions in the
  containing context, and recursive or array-valued source contexts are
  rejected explicitly.
- Enforce JSON-LD `@protected` term definitions, including sourced contexts:
  same-context overrides remain valid, while later incompatible redefinitions
  return `Protected_Term_Redefinition`.
- Resolve each object context once during Expansion, avoiding duplicate remote
  loads while keeping term-scoped and object-local contexts in one path.
- Extend the pinned JSON-LD Expansion gate with two sourced-context override
  vectors, for 75 cases total.

## 0.24.0 - 2026-07-20

- Add bounded, deterministic JSON-LD Expansion and Flattening APIs. Expansion
  preserves document-level JSON-LD annotations before RDF conversion; Flattening
  builds a bounded deterministic node-map.
- Add a bounded JSON-LD Framing profile with recursive embedding, standard
  embed modes, `@explicit`, defaults, `@requireAll`, value/list patterns, and
  basic reverse framing. Named-graph matching, `@included`, and the remaining
  Framing policy matrix remain explicitly out of scope.
- Add pinned W3C core gates for 73 Expansion, 35 Flattening, and 79 Framing
  vectors. No implicit network access is added; document loading remains
  caller-controlled.

## 0.23.0 - 2026-07-18

- Add bounded, deterministic RDF dataset to expanded JSON-LD serialization with
  named-graph preservation, safe RDF list collapse, `rdf:JSON`, and optional
  native JSON scalars.
- Add atomic explicit-context JSON-LD compaction with language maps, list and
  `@set` containers, typed values, named graphs, and a `convert --to jsonld
  --context PATH` CLI path. JSON-LD output requires an explicit positive
  `max_records` dataset bound.
- Add pinned W3C RDF-to-JSON-LD (28 cases) and compaction (66 cases) core
  gates. The document-level Expansion, Flattening, and Framing APIs remain
  deliberately out of scope for this release.

## 0.22.0 - 2026-07-18

- Add bounded `odin-rdf diff BEFORE AFTER` for deterministic canonical dataset
  change review across every supported input syntax. It canonicalizes both
  complete datasets under the existing RDFC-1.0 and reader limits, then emits
  sorted canonical N-Quads lines prefixed with `- ` (removed) or `+ ` (added).
- `diff` accepts an atomic `--output` target and returns `0` for no changes,
  `1` for changes, or `2` for an input, canonicalization, or output error.
  It intentionally does not claim to be a minimum blank-node edit script.
- Add CLI coverage for two-input syntax inference, bounded failure, deterministic
  output, empty equal output, and stable diagnostic text. No public library API
  changes.

## 0.21.0 - 2026-07-18

- Add bounded `odin-rdf canon`, `hash`, and `compare` commands for every
  supported RDF input syntax. They use the existing RDFC-1.0 APIs only after a
  complete owned dataset is collected under an explicit quad admission policy.
- `canon` writes atomic canonical N-Quads, `hash` writes a SHA-256 or SHA-384
  hexadecimal digest, and `compare` reports isomorphism with conventional
  `0` (equal), `1` (different), and `2` (error) exit codes.
- Add CLI coverage for syntax inference, hash selection, blank-node equality,
  collector limits, and atomic file replacement. No existing public APIs
  change.

## 0.20.0 - 2026-07-18

- Add `canon.canonical_hash` for atomic SHA-256 or SHA-384 digests of a
  complete dataset's RDFC-1.0 canonical N-Quads form.
- Add `canon.isomorphic` for collision-independent dataset comparison through
  canonical text, permitting unrelated source blank-node labels and scopes.
- Document the integrity-helper boundary: these APIs support cache, integrity,
  and higher-level signing inputs but do not implement signatures, storage, or
  SPARQL. No existing public APIs change.

## 0.19.0 - 2026-07-18

- Add `rdf/canon`, a resource-bounded implementation of W3C RDF Dataset
  Canonicalization 1.0 (RDFC-1.0) with canonical N-Quads output and SHA-256 or
  SHA-384 algorithm selection.
- Add the pinned 65-case official RDFC-1.0 conformance and resource-limit
  suite to local verification and CI. No existing public APIs change.

## 0.18.0 - 2026-07-18

- Add an explicit-prefix stateful RDF/XML document writer with per-record
  atomicity, copied and capacity-bounded blank-node identity, and a runnable
  streaming example. Extend RDF/XML QName validation to the XML 1.0 Fifth
  Edition NCName grammar.

## 0.17.0 - 2026-07-18

- Add RDF/XML as an explicit bounded batch `convert` target. It requires a
  positive `max_records` admission limit, retains owned default-graph terms,
  rejects named graphs before output, and writes the XML document only after
  parsing and serialization both succeed.

## 0.16.0 - 2026-07-18

- Add `rdfxml.write_triples`, an atomic deterministic RDF/XML writer for
  complete default graphs. It uses XML-safe blank-node identifiers, preserves
  source triple order, supports language, datatype, and XML Literal values,
  and explicitly rejects RDF/XML-unrepresentable predicates and XML 1.0
  characters.

## 0.15.0 - 2026-07-18

- Add markup-bearing RDF/XML `rdf:parseType="Literal"` support with
  token-preserved XML Literal serialization, including mixed content, comments,
  namespace propagation, explicit end tags, and canonical attribute ordering.
- Expand the pinned RDF/XML core conformance gate from 169 to 173 cases by
  enabling the four XML Literal namespace and canonicalization fixtures.

## 0.14.0 - 2026-07-18

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
