# TriG parser and writer design

`rdf/trig` parses RDF 1.1 TriG into callback-scoped `rdf.Quad` values and
serializes individual quads back to TriG. Both surfaces preserve explicit
ownership and bounded-streaming boundaries.

## Grammar and dataset boundary

The parser shares the proven Turtle lexical and term rules while assigning every
expanded statement to either the default graph or the current named graph. It
supports `@prefix`/`@base` and SPARQL-style `PREFIX`/`BASE`, unlabeled default
graph blocks, named graph blocks with or without the `GRAPH` keyword, blank
node graph names, property lists, collections, and the optional terminating dot
immediately before `}`.

Graph labels must be IRIs or blank nodes. A literal, collection, or blank-node
property list is rejected rather than being approximated as a graph name.
Generated collection and property-list statements inherit the graph in which
they appear. A completed top-level triple production is buffered before its
quads are emitted, so resource-limit or syntax errors never leak a partial
production to the sink.

## Bounds and ownership

`Parse_Options` bounds lexical token size, prefix table count and bytes,
property-list/collection nesting, quads pending one production, and total
emitted quads. The zero value uses documented defaults except `max_quads`,
where zero disables the output cap.

TriG cannot use Turtle's dot-framed reader without misframing valid graph
blocks that omit the final dot. `parse_reader` therefore retains one explicitly
bounded document (16 MiB by default), reads it in bounded 64 KiB chunks, then
calls the same parser as the in-memory entry point. It records underlying I/O
errors and rejects stalled readers.

Term strings are valid only during the sink callback. Graph labels are kept
alive internally for the duration of their graph block, but callers still must
copy or encode all values they need after the callback returns.

## Streaming writer boundary

`write_prefixes` accepts the same explicit `turtle.Prefix` declarations as the
Turtle writer. `write_quad` atomically serializes one quad using the same safe
prefix compaction and IRIREF fallback policy. Default-graph quads become
Turtle-compatible triple statements. Named-graph quads become individual graph
blocks, for example `<urn:g> { <urn:s> <urn:p> <urn:o> . }`.

This is intentionally a record writer rather than a document formatter: it
does not retain quads, group graph blocks, reorder input, infer prefixes, or
deduplicate.

`format_quads` is the separately explicit batch API. It accepts a complete
caller-owned `[]rdf.Quad`, validates blank-node scope collisions across both
triple and graph-name positions, sorts and deduplicates the dataset, and writes
one grouped block per named graph. Its `Infer` prefix policy covers graph names
and all triple terms. This makes the memory and ordering tradeoff visible at
the call site rather than hiding a dataset accumulator in the streaming writer.

## Conformance gate

`scripts/run-w3c-trig-tests.sh` pins `w3c/rdf-tests` at the repository-wide
revision and runs all 355 TriG evaluation, positive-syntax, and negative-syntax
cases. Evaluation datasets are compared with test-only blank-node-aware dataset
isomorphism, including blank nodes in graph-name position. Every case also runs
through 1-byte, 7-byte, and default reader chunks.

## Collection boundary

`rdf/dataset.Collector` now provides explicit owned retention for TriG and the
other quad parsers. It copies callback-scoped strings, preserves source order
and duplicates, and exposes a maximum-quad admission limit. It intentionally
does not imply graph lookup, deduplication, indexing, or SPARQL semantics.

RDF/XML XML Literal input is now covered by its dedicated 173-case core gate;
RDF/XML serialization remains intentionally separate.
