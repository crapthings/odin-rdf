# Architecture

## Package boundaries

The `rdf` package contains only syntax-independent data types. Syntax packages such as `rdf/ntriples` produce `Triple` values without depending on a filesystem, database, or in-memory graph implementation. Dataset and quad types will be introduced with N-Quads rather than committed to prematurely.

Consumers receive triples through a sink callback. A converter can write each triple immediately, a database importer can dictionary-encode terms as they arrive, and a small utility can collect them into a dynamic array when retaining the graph is appropriate.

## Memory ownership

The parser avoids copying whenever possible. Values may reference the original input, the reusable line buffer owned by `parse_reader`, or temporary builders used for escape decoding. Consequently, every parsing API guarantees term strings only for the duration of the current sink callback. Consumers must copy strings or encode them into application-owned IDs before returning if they need longer lifetimes.

Blank-node labels are scoped to one parsed document. The parser stores that identity in `Term.scope`; one `parse` or `parse_reader` call shares a non-zero scope, and independent calls receive different scopes. Manually constructed blank nodes default to scope zero, so applications can either provide an explicit scope or dictionary-encode them when merging sources.

The streaming reader requests 64 KiB chunks by default and enforces a 16 MiB maximum physical line length to bound memory growth on untrusted input. Both values are configurable, and callers may also cap the number of emitted triples.

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
