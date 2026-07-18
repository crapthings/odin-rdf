# JSON-LD to RDF design

`rdf/jsonld` is a bounded JSON-LD document processor that emits RDF dataset
quads. It is intentionally not a streaming syntax parser: JSON-LD context
processing, lists, reverse properties, and named graphs require retained
document state.

## Public boundary

```odin
parse(input: string, sink: Sink, options: Options = {}, user_data: rawptr = nil) -> Parse_Error
parse_reader(reader: io.Reader, sink: Sink, options: Reader_Options = {}, user_data: rawptr = nil) -> Reader_Result
```

Both entry points produce `rdf.Quad` values. String fields are transient and
valid for the callback only. The reader retains at most `max_document_bytes`
(16 MiB by default); it is a bounded document reader, not a record stream.

`Options` bounds document bytes, JSON nesting, processed contexts, remote
contexts, and emitted quads. Its `Document_Loader` is opt-in. The package never
opens URLs itself, so applications choose caching, authentication, redirects,
and network policy explicitly.

## Implemented to-RDF core

The processor accepts strict JSON and handles local contexts, `@base`,
`@vocab`, prefixes, term aliases, `@id`, `@type`, value objects, language and
datatype coercion, arrays and `@list`, reverse properties, `@graph`,
`@included`, and `@nest`. It emits default and named graph quads and keeps
explicit blank-node identifiers document-local.

It is designed around JSON-LD 1.1's JSON-LD-to-RDF direction, not the complete
JSON-LD API. The first release intentionally does not expose compaction,
framing, RDF-to-JSON-LD, JSON-LD serialization, a built-in HTTP loader,
directional literals, scoped contexts, `@import`, protected terms, or map
containers. Those additions require their own conformance milestones.

## Conversion and CLI

`convert.Format.JSON_LD` is an input format only. It can write N-Triples,
N-Quads, or Turtle; JSON-LD output is rejected rather than approximated.
`odin-rdf convert` recognizes `jsonld`, `json-ld`, and `json`, and infers
`.jsonld` and `.json`. `--max-document-bytes N` sets the retained JSON-LD
document limit. CLI conversion intentionally has no document loader, so remote
contexts fail explicitly instead of causing implicit network access.

## Conformance discipline

The repository pins the W3C JSON-LD API test corpus and runs a stable core
JSON-LD-to-RDF selection alongside package tests. The selection covers context
expansion, scalar coercion, collections, reverse properties, named graphs,
blank-node allocation, and relative IRI cases. The broader 1.1 suite remains
the gate for future scoped-context, map-container, direction, and generalized
RDF work.
