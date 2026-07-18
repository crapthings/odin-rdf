# Architecture

## Package boundaries

The `rdf` package contains only syntax-independent data types. Syntax packages such as `rdf/ntriples` and `rdf/nquads` produce `Triple` and `Quad` values without depending on a filesystem, database, or in-memory graph implementation. A quad represents the default graph explicitly with `has_graph = false`; the default graph is never encoded as a sentinel RDF term.

Consumers receive triples through a sink callback. A converter can write each triple immediately, a database importer can dictionary-encode terms as they arrive, and `rdf/dataset.Collector` can safely retain copied quads with an explicit admission limit when materialization is appropriate. The collector preserves order and duplicates; it is not graph storage.

`rdf/jsonld`, `rdf/rdfxml`, and `rdf/trig` are intentional exceptions to record streaming:
each retains one bounded document before emitting quads. JSON-LD's optional
loader is supplied by the caller; RDF/XML and TriG have no external-resource or network
behavior. These packages expose document, nesting, and output limits rather
than silently materializing an unbounded graph.

## Conversion boundary

`rdf/convert` is the narrow adapter between syntax readers and writers. It
retains only one destination record builder, so N-Triples, N-Quads default
graphs, and Turtle can move through the pipeline without graph materialization.
The adapter makes the one semantic asymmetry explicit: a named N-Quads graph
is valid only when N-Quads is the target. Conversion to N-Triples or Turtle
stops with an error before that record is written; it never degrades a dataset
into a graph by silently dropping the graph name.

The `cmd/odin-rdf` wrapper owns file policy rather than the library. It writes
file targets to an exclusive same-directory temporary path and renames only on
success. Standard output remains intentionally streaming for record targets;
the bounded RDF/XML target is the explicit complete-graph exception, so it
writes only after parsing and serialization have both succeeded.

## Memory ownership

The parser avoids copying whenever possible. Values may reference the original input, the reusable line buffer owned by `parse_reader`, or temporary builders used for escape decoding. Consequently, every parsing API guarantees term strings only for the duration of the current sink callback. Consumers must copy strings or encode them into application-owned IDs before returning if they need longer lifetimes.

Blank-node labels are scoped to one parsed document. Parsers store that identity in `Term.scope`; one `parse` or `parse_reader` call shares a non-zero scope across triple positions and N-Quads graph names, while independent calls and syntax packages draw from one process-wide scope generator. Manually constructed blank nodes default to scope zero, so applications can provide an explicit scope or dictionary-encode them when merging sources.

The streaming reader requests 64 KiB chunks by default. Line-oriented parsers
enforce a 16 MiB maximum physical line length; JSON-LD, RDF/XML, and TriG instead
enforce a 16 MiB retained-document bound. Callers may also cap emitted triples
or quads according to the syntax.

## Error handling

- Invalid syntax reports an exact source location; malformed lines are never skipped silently.
- Unsupported syntax must produce an explicit error instead of an approximate RDF result.
- `Stopped` means that the sink requested an early exit, not that the input was malformed.
- `Reader_Result.reader_error` preserves underlying I/O failures, while `Parse_Error` reports syntax failures with document-relative line and column numbers.
- Every public error enum has a matching message function that returns a stable human-readable description without allocating.

## Standards policy

RDF 1.1 is the stable baseline. RDF 1.2 features should be added behind explicit options only after the specification is stable, its tests are pinned, and the API has been reviewed.

The core package validates RDF term and triple structure separately from lexical syntax. N-Triples enforces the grammar tested by the pinned W3C suite. Full RFC 3987 IRI and BCP 47 language-tag validation are not claimed by the syntax-independent layer.

## Performance policy

Correctness against the W3C test suite comes first. Performance work should use representative large inputs and report throughput, allocation counts, and peak memory. Optimize copying and allocation behavior first, then I/O batching and data layout; consider SIMD only after profiling identifies a clear benefit.

The [shared term lexer design](shared-lexer-design.md) freezes the compatibility
contract and before-refactor throughput baseline for the next parser-internal
migration. Both N-Triples and N-Quads now use `rdf/internal/termlex` while
retaining ownership of their document grammars and public errors. N-Quads scans
each statement once instead of constructing and reparsing synthetic N-Triples.

The implemented [Turtle parser and writer design](turtle-design.md) defines
Turtle grammar, streaming, ownership, transient parse-state, conformance
boundaries, and explicit-prefix serialization policy.

The [TriG parser design](trig-design.md) defines dataset graph assignment,
bounded-document reader behavior, and its full pinned W3C gate.

The [streaming conversion design](conversion-design.md) records the conversion
matrix, named-graph loss boundary, error propagation, and command file policy.
