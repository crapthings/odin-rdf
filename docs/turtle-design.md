# Turtle parser design

This document defines the implementation contract for the RDF 1.1 Turtle
parser introduced in version 0.4.0.

The normative baseline is the W3C [RDF 1.1 Turtle Recommendation][turtle]. The
acceptance suite is the official [`w3c/rdf-tests` Turtle manifest][tests],
pinned to the same upstream commit as the existing syntax suites:
`d3e844aaa3e2f2b5250f2d1c988ce58870d6bc86`.

## Scope

The implementation covers the complete RDF 1.1 Turtle grammar and
mapping to RDF triples:

- `@base`/`BASE` and `@prefix`/`PREFIX` directives, including their distinct
  terminating-dot rules;
- absolute and relative IRI references, prefixed names, and predicate `a`;
- predicate-object lists, object lists, and comments;
- labeled and anonymous blank nodes, nested blank-node property lists, and RDF
  collections;
- single-, double-, and triple-quoted strings, language tags, datatype IRIs,
  Unicode and string escapes;
- integer, decimal, double, and boolean literal shorthands.

RDF/XML, JSON-LD, RDF-star, storage, querying, and a Turtle writer are outside
this milestone. A writer needs separate prefix and formatting policy and must
not delay parser conformance.

## Public API

The package will be `rdf/turtle` and follow the existing syntax packages:

```odin
Sink :: proc(triple: rdf.Triple, user_data: rawptr) -> bool

Parse_Options :: struct {
	base_iri:            string,
	max_token_bytes:     int,
	max_prefixes:        int,
	max_prefix_bytes:    int,
	max_nesting_depth:   int,
	max_pending_triples: int,
	max_triples:         int,
}

Reader_Options :: struct {
	parse:               Parse_Options,
	chunk_size:          int,
	max_statement_bytes: int,
}

parse :: proc(input: string, sink: Sink, options: Parse_Options = {},
              user_data: rawptr = nil) -> Parse_Error

parse_reader :: proc(reader: io.Reader, sink: Sink,
                     options: Reader_Options = {},
                     user_data: rawptr = nil) -> Reader_Result
```

Zero selects a documented safe default; negative values are invalid.
`base_iri`, when present,
must be absolute. A relative IRI is an error when neither options nor a prior
base directive establishes a usable base.

The parser owns its prefix table and generated blank-node identifiers. Strings
passed to the sink are valid only during that callback, matching the existing
contract. Applications must copy or encode values they retain. Each parse call
receives one non-zero blank-node scope shared by labeled and generated blank
nodes for that document.

Directive callbacks are intentionally absent: declarations affect parser state
but do not represent RDF triples. They can be added later without weakening the
core API.

## Parser architecture

Turtle is document grammar, not a line format. Memory and reader entry points
feed one stateful lexer and recursive-descent parser. The reader preserves state
across arbitrary chunks, including UTF-8 sequences, escapes, prefixed names,
and multiline strings. A framing lexer bounds one top-level statement with
`max_statement_bytes`; the complete document is never materialized.

The implementation has three transient layers:

1. the lexer produces Turtle tokens;
2. recursive-descent production state tracks the current subject, predicate,
   collection, or property list until the top-level statement is complete;
3. the parser commits the resulting RDF triples to the sink.

It does not build a public or document-wide AST. Turtle's semantic result is an
RDF graph, and a full tree would defeat streaming and bounded-memory goals. A
future formatter, IDE, or source-preserving linter may expose a separate
lossless CST/AST API that retains comments, whitespace, token spans, and source
spelling; that concern must not constrain the core graph parser.

Parser state contains the current base and prefix mappings, source position,
document blank-node scope, generated-node counter, a bounded nesting stack,
decoded-token scratch storage, a pending-triple arena, and resource counters.
Nested property lists and collections return their representing RDF term while
adding expanded triples to the current pending statement.

### Shared lexical boundary

`rdf/internal/termlex` remains private. Its absolute-only `read_iri` cannot be
used directly for Turtle. Before grammar work, split it into:

1. an IRIREF decoder that validates characters and escapes but may return a
   relative reference; and
2. syntax policy: N-Triples/N-Quads require absolute IRIs, while Turtle resolves
   against its current base.

The refactor must preserve every existing diagnostic. UTF-8 decoding, Unicode
escapes, language tags, and shared blank-node character classes remain common.
Prefixed names, local-name escapes, long strings, numeric tokens, directives,
and Turtle punctuation belong to `rdf/turtle`.

### IRI and prefix handling

Relative references use the algorithm required by Turtle and RFC 3986 section
5. Unicode escapes are decoded before resolution. A base directive resolves
its reference against the prior base before replacement. Prefix namespaces are
resolved before storage.

Prefixed names concatenate the namespace with the decoded local part. Percent
escapes remain percent escapes; backslash escapes contribute their character.
An undefined prefix is an error, and a later declaration may replace a mapping.
IRI resolution must be independently tested for empty references, fragments,
queries, dot segments, authority changes, and bases with or without paths.

### Triple emission and failure atomicity

One top-level `triples` production may expand into many RDF triples. The parser
buffers all triples from that statement and calls the sink only after accepting
its terminating dot. Syntax and resource errors therefore do not leak partial
statements.

`max_pending_triples` bounds the buffer and `max_nesting_depth` prevents stack
exhaustion. Once commit starts, `false` from the sink yields `Stopped`; accepted
triples cannot be rolled back. Earlier complete statements remain observable if
a later statement fails, consistent with existing streaming APIs.

Collections expand in source order to `rdf:first` and `rdf:rest` and terminate
in `rdf:nil`; `()` is `rdf:nil`. Generated identifiers are implementation
details and must not collide with source blank-node labels in the same scope.

## Resource and ownership guarantees

Reader memory must remain bounded independently of input size. Limits cover
token bytes, prefix count and total bytes, nesting depth, pending triples,
emitted triples, and chunk size. Prefix values and the current base have
document lifetime. Reassignment replaces a prefix and returns the old namespace
bytes to the table budget.

There is no line-length limit: valid long strings cross lines and a statement
may be formatted arbitrarily. Token, statement-byte, and pending-triple limits
provide the relevant bounds.

Memory parsing may reference unescaped input slices. Reader input and decoded,
resolved, prefixed, or generated values use parser-owned storage. The pending
statement retains strings through callbacks and resets only after commit or
failure.

## Errors and diagnostics

`Parse_Error` follows the existing enum code plus one-based line and column.
Every public code has a stable, allocation-free message. The taxonomy should
distinguish:

- missing sink and invalid options;
- invalid UTF-8, escape, IRI reference, base, prefixed name, blank-node label,
  language tag, string, and numeric literal;
- undefined prefix and missing base for a relative IRI;
- expected directive IRI, subject, predicate, object, closing delimiter, or
  terminating dot;
- token, prefix, nesting, pending-triple, and total-triple limits;
- reader error, no progress, and sink stop.

Memory and reader paths must return the same code and location for identical
bytes, including CRLF and chunk-boundary failures. Tests freeze message wording
and representative locations before the package is stable.

## Conformance and verification

The pinned official manifest currently has 313 entries: 145 evaluation, 74
positive syntax, and 94 negative syntax tests. The gate discovers cases from
the manifest rather than hard-coding filenames.

- Positive and evaluation inputs succeed in memory and with reader chunks of
  1 byte, 7 bytes, and the default size.
- Negative syntax inputs fail through every entry point.
- Evaluation results compare expected N-Triples by RDF graph isomorphism;
  blank-node labels and triple order are not semantic.
- Reader and memory paths have differential output, error, and location tests.
- Property tests generate valid nested Turtle and arbitrary bytes; fuzzing
  emphasizes chunk boundaries, long strings, prefixed names, nesting, and
  resource limits.
- Existing N-Triples/N-Quads suites, property tests, fuzz smoke, and benchmarks
  remain regression gates after shared-lexer changes.

The test-only graph-isomorphism helper belongs under `tests/w3c`; it must not
force a public graph-store API prematurely.

## Delivery sequence

Implementation landed as reviewable, always-green changes:

1. Add manifest discovery and test-only graph isomorphism; split IRIREF decoding
   from absolute-IRI policy without observable regressions.
2. Add lexer, directives, base resolution, prefixes, simple triples,
   predicate/object lists, and simple literals.
3. Add long strings, numeric/boolean forms, full prefixed-name grammar, and
   language/datatype handling.
4. Add anonymous nodes, property lists, collections, statement buffering, and
   resource limits.
5. Add the incremental reader, close all 313 official cases, and add
   differential property/fuzz coverage.
6. Advertise Turtle in README and landing page only after the gate passes.

Each stage preserved released syntax behavior. Version 0.4.0 is a minor release
because it adds a package; shared internal refactors stay hidden.

[turtle]: https://www.w3.org/TR/turtle/
[tests]: https://github.com/w3c/rdf-tests/tree/d3e844aaa3e2f2b5250f2d1c988ce58870d6bc86/rdf/rdf11/rdf-turtle
