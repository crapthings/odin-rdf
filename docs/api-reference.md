# API reference

This reference describes the supported public surface on the current development branch. The
source remains authoritative for exact Odin declarations.

## Common callback contract

All parsers emit through a `Sink` callback and stop when it returns `false`.
Term strings may point into caller input or parser-owned scratch storage and
remain valid only for the duration of the callback. Copy them or convert them
to application-owned IDs before returning when longer ownership is required.

Each parse call assigns parsed blank-node labels a non-zero document scope.
Equal labels within one document identify the same node; equal labels from
independent calls do not. `ntriples.parse_scoped` is the advanced integration
entry point for explicitly sharing a non-zero scope.

Parser failures use `Parse_Error {code, line, column}` with one-based source
locations. A zero-value error is success. Inspect the enum code in program
logic and use `parse_error_message(code)` for a stable, allocation-free human
description. Writers follow the same pattern with `write_error_message`.

## Core `rdf`

- `Term`, `Triple`, and `Quad` represent the syntax-independent data model.
- `iri`, `blank_node`, `literal`, `language_literal`, and `typed_literal`
  construct terms with valid structural invariants.
- `default_graph_quad` and `named_graph_quad` construct quads; `triple` extracts
  the triple component from a quad.
- `validate_term_structure`, `validate_triple_structure`, and
  `validate_quad_structure` validate the RDF data-model shape without applying
  a concrete serialization's lexical grammar.
- `new_blank_node_scope` creates document identity for advanced integrations.

## Owned collection `rdf/dataset`

```odin
init(collector: ^Collector, options: Options = {}) -> Error_Code
add(collector: ^Collector, quad: rdf.Quad) -> Error_Code
sink(quad: rdf.Quad, user_data: rawptr) -> bool
triple_sink(triple: rdf.Triple, user_data: rawptr) -> bool
destroy(collector: ^Collector)
```

`Collector` copies a quad and every referenced term string into collector-owned
storage. `quads` preserves source order and duplicates until `destroy`; it is
not an RDF graph or dataset-set API. `Options.max_quads` is an optional positive
admission limit (zero disables it). `sink` lets any quad parser write directly
to the collector; `triple_sink` maps graph-syntax output to default-graph quads.
If either returns false, inspect `collector.last_error` to
distinguish `Quad_Limit`, an invalid caller-supplied quad, or allocation failure
from a parser-originated stop.

## N-Triples `rdf/ntriples`

```odin
parse(input: string, sink: Sink, user_data: rawptr = nil) -> Parse_Error
parse_scoped(input: string, sink: Sink, scope: rdf.Blank_Node_Scope,
             user_data: rawptr = nil) -> Parse_Error
parse_reader(reader: io.Reader, sink: Sink, options: Reader_Options = {},
             user_data: rawptr = nil) -> Reader_Result
write_triple(builder: ^strings.Builder, triple: rdf.Triple) -> Write_Error
write_term(builder: ^strings.Builder, term: rdf.Term) -> Write_Error
```

| `Reader_Options` field | Zero value | Meaning |
| --- | --- | --- |
| `chunk_size` | 64 KiB | Bytes requested per read; negative is invalid. |
| `max_line_bytes` | 16 MiB | Maximum physical line; negative is invalid. |
| `max_triples` | Unlimited | Maximum emitted triples. |

`Reader_Result` returns `error`, the preserved `reader_error`, `triples`, and
`bytes_read`. Reader ownership and closing remain the caller's responsibility.

## N-Quads `rdf/nquads`

```odin
parse(input: string, sink: Sink, user_data: rawptr = nil) -> Parse_Error
parse_reader(reader: io.Reader, sink: Sink, options: Reader_Options = {},
             user_data: rawptr = nil) -> Reader_Result
write_quad(builder: ^strings.Builder, quad: rdf.Quad) -> Write_Error
```

| `Reader_Options` field | Zero value | Meaning |
| --- | --- | --- |
| `chunk_size` | 64 KiB | Bytes requested per read; negative is invalid. |
| `max_line_bytes` | 16 MiB | Maximum physical line; negative is invalid. |
| `max_quads` | Unlimited | Maximum emitted quads. |

`Reader_Result` returns `error`, the preserved `reader_error`, `quads`, and
`bytes_read`. A `Quad` with `has_graph == false` is in the default graph.

## Turtle `rdf/turtle`

```odin
parse(input: string, sink: Sink, options: Parse_Options = {},
      user_data: rawptr = nil) -> Parse_Error
parse_reader(reader: io.Reader, sink: Sink, options: Reader_Options = {},
             user_data: rawptr = nil) -> Reader_Result
write_prefixes(builder: ^strings.Builder, prefixes: []Prefix) -> Write_Error
write_term(builder: ^strings.Builder, term: rdf.Term,
           options: Writer_Options = {}) -> Write_Error
write_triple(builder: ^strings.Builder, triple: rdf.Triple,
             options: Writer_Options = {}) -> Write_Error
format_triples(builder: ^strings.Builder, triples: []rdf.Triple,
               options: Format_Options = {}) -> Write_Error
```

| `Parse_Options` field | Zero value | Meaning |
| --- | --- | --- |
| `base_iri` | No initial base | Absolute base used before a base directive. |
| `max_token_bytes` | 16 MiB | Maximum decoded bytes in one token. |
| `max_prefixes` | 1,024 | Maximum distinct prefix labels. |
| `max_prefix_bytes` | 16 MiB | Maximum retained prefix-table bytes. |
| `max_nesting_depth` | 256 | Maximum property-list/collection nesting. |
| `max_pending_triples` | 100,000 | Maximum triples buffered by one statement. |
| `max_triples` | Unlimited | Maximum triples emitted by the document. |

`Reader_Options` embeds these limits in `parse` and adds:

| `Reader_Options` field | Zero value | Meaning |
| --- | --- | --- |
| `chunk_size` | 64 KiB | Bytes requested per read; negative is invalid. |
| `max_statement_bytes` | 16 MiB | Maximum buffered top-level production. |

`Reader_Result` returns `error`, the preserved `reader_error`, `triples`, and
`bytes_read`. Turtle validates a complete top-level statement before emitting
any of its expanded triples, so syntax and configured-limit failures do not
partially commit that statement. Earlier valid statements remain emitted.

`Prefix {label, namespace}` configures an explicit Turtle namespace; an empty
label is the default prefix. `Writer_Options.prefixes` uses that table to choose
the longest matching safe namespace, preserving declaration order on ties.
`write_prefixes` emits the declarations once, while `write_term` and
`write_triple` are atomic and streaming-safe. They fall back to canonical
IRIREFs when a compact prefixed name would need escaping. The writer does not
infer prefixes, group triples, or retain document state.

`format_triples` is the separate, batch-oriented path. It atomically appends a
complete document, sorts triples deterministically, groups predicate/object
lists, uses `a` for `rdf:type`, and removes exact duplicate triples.
`Format_Options.prefix_policy` defaults to `Infer`, which adds known W3C labels
where safe and otherwise uses deterministic `ns1`, `ns2`, ... labels.
`Explicit_Only` retains only caller-provided declarations. Formatting needs the
complete triple collection and does not preserve source layout, comments, or
statement order. It rejects two blank nodes with the same label from different
non-identical source scopes, because Turtle would otherwise serialize them as
one node.

## JSON-LD `rdf/jsonld`

```odin
parse(input: string, sink: Sink, options: Options = {},
      user_data: rawptr = nil) -> Parse_Error
parse_reader(reader: io.Reader, sink: Sink, options: Reader_Options = {},
             user_data: rawptr = nil) -> Reader_Result
```

JSON-LD emits `rdf.Quad` values and retains a complete document. `Options`
provides `base_iri`, `max_document_bytes` (16 MiB), `max_nesting_depth` (256),
`max_contexts` (1,024), `max_remote_contexts` (16), `max_quads` (unlimited),
and an opt-in `Document_Loader`. The loader receives a resolved context URL and
must return its document synchronously; no network transport is built in.

`Reader_Options` embeds `parse`, adds `chunk_size` (64 KiB), and supplies a
document bound through `max_document_bytes`. `Reader_Result` reports `quads`,
`bytes_read`, and any underlying `reader_error`. See the [JSON-LD design
boundary](jsonld-design.md) for the supported to-RDF profile and deliberately
deferred JSON-LD API features.

## RDF/XML `rdf/rdfxml`

```odin
parse(input: string, sink: Sink, options: Options = {},
      user_data: rawptr = nil) -> Parse_Error
parse_reader(reader: io.Reader, sink: Sink, options: Reader_Options = {},
             user_data: rawptr = nil) -> Reader_Result
```

RDF/XML emits default-graph `rdf.Quad` values and retains one bounded XML
document. `Options` provides `base_iri`, `max_document_bytes` (16 MiB),
`max_elements` (100,000), `max_attributes` (100,000),
`max_nesting_depth` (256), and `max_quads` (unlimited). It never fetches
external documents or resources.

`Reader_Options` embeds `parse`, adds `chunk_size` (64 KiB), and can override
the document byte bound through `max_document_bytes`. `Reader_Result` reports
`quads`, `bytes_read`, and any underlying `reader_error`. See the [RDF/XML
design boundary](rdfxml-design.md) for supported constructs, the explicit XML
Literal serialization behavior, and the W3C core selection. XML parser diagnostics do not
currently carry source positions; semantic RDF/XML failures therefore use a
zero line and column.

## TriG `rdf/trig`

```odin
parse(input: string, sink: Sink, options: Parse_Options = {},
      user_data: rawptr = nil) -> Parse_Error
parse_reader(reader: io.Reader, sink: Sink, options: Reader_Options = {},
             user_data: rawptr = nil) -> Reader_Result
write_prefixes(builder: ^strings.Builder, prefixes: []turtle.Prefix) -> Write_Error
write_quad(builder: ^strings.Builder, quad: rdf.Quad,
           options: Writer_Options = {}) -> Write_Error
format_quads(builder: ^strings.Builder, quads: []rdf.Quad,
             options: Format_Options = {}) -> Write_Error
```

TriG emits `rdf.Quad` values for default and named graph statements. It supports
RDF 1.1 directives, graph blocks with or without `GRAPH`, compact
predicate/object lists, property lists, collections, and optional dots directly
before a graph's closing brace. `Parse_Options` provides `base_iri`, token,
prefix-count/bytes, nesting, pending-quad, and emitted-quad limits. The reader
retains one bounded document (16 MiB by default) because TriG graph blocks do
not have a line-safe or dot-only framing rule. `Reader_Options` adds a 64 KiB
chunk size and `max_document_bytes`. See the [TriG design](trig-design.md) for
ownership and conformance details.

`Writer_Options.prefixes` uses `turtle.Prefix` declarations and the same
longest-safe-namespace compaction policy as the Turtle writer. Call
`write_prefixes` once before records when declarations are wanted.
`write_quad` is atomic and streaming-safe: default-graph quads become a
Turtle-compatible triple, and each named quad becomes an independent TriG
graph block. It does not group graph blocks, reorder records, infer prefixes,
or retain document state.

`format_quads` is the separate, batch-oriented path. It atomically appends a
complete TriG document, orders default graph statements before named graphs,
groups triples by graph/subject/predicate, and removes exact duplicate quads.
`Format_Options.prefix_policy` uses Turtle's `Infer` or `Explicit_Only` policy;
inference covers graph names as well as triple terms. Formatting rejects an
identical blank-node label from different non-identical source scopes, because
TriG would otherwise serialize them as one node. It deliberately needs a
complete caller-owned dataset and does not preserve statement order or layout.

## Conversion `rdf/convert`

```odin
convert(reader: io.Reader, output: io.Writer, options: Options) -> Result
```

`Format` is one of `N_Triples`, `N_Quads`, `Turtle`, `TriG`, or input-only
`JSON_LD` and `RDF_XML`. `Options` selects the
input and output formats, `reader_limits: Reader_Limits`, and
`turtle_prefixes: []turtle.Prefix` for explicit Turtle and TriG output
declarations.
`Result` reports `statements` written, `bytes_read`, and an `Error`.

| `Reader_Limits` field | Applies to | Zero value |
| --- | --- | --- |
| `chunk_size` | All source readers | Syntax default (64 KiB). |
| `max_records` | All source readers | Unlimited. |
| `max_line_bytes` | N-Triples, N-Quads | Syntax default (16 MiB). |
| `max_statement_bytes` | Turtle | Turtle default (16 MiB). |
| `max_document_bytes` | JSON-LD, RDF/XML, TriG | Syntax default (16 MiB). |

All limit fields must be non-negative. `max_records` maps to triple or quad
records according to the source syntax; it counts before a record is passed to
the destination writer.

`Error.code` distinguishes invalid formats, invalid Turtle/TriG prefix configuration,
source parse errors, a named graph that the selected target cannot represent,
serialization failures, and output-write failures. Source parse errors retain
their one-based `line`, `column`, parser diagnostic in `detail`, and reader
I/O error when available. Other failures have zero line and column.

The adapter streams each validated statement directly to the selected writer.
N-Triples and Turtle map to the N-Quads or TriG default graph when those are
targets. N-Quads default-graph statements can map to triples, while a named
graph is rejected only for N-Triples and Turtle rather than silently losing
data. The adapter does not flush or close either stream.

## Command `cmd/odin-rdf`

```sh
odin-rdf convert INPUT [--from FORMAT] [--to FORMAT] [--output PATH] \
  [--prefix LABEL=NAMESPACE] [--max-records N] [--max-line-bytes N] \
  [--max-statement-bytes N] [--max-document-bytes N]
odin-rdf format INPUT [--from turtle|trig] [--output PATH] \
  [--prefix LABEL=NAMESPACE] [--max-triples N] [--max-quads N] \
  [--no-infer-prefixes]
```

The command accepts `ntriples`/`nt`, `nquads`/`nq`, `turtle`/`ttl`, `trig`,
input-only `jsonld`/`json-ld`/`json`, and input-only
`rdfxml`/`rdf-xml`/`rdf/xml`/`rdf`/`xml`. It infers formats from file paths ending
in `.nt`, `.nq`, `.ttl`, `.jsonld`, `.json`, `.rdfxml`, `.rdf`, `.xml`, or `.trig`; explicit
`--from` and `--to` options override that inference. `INPUT` and `--output`
use `-` for standard input and output, which requires the matching explicit
format option; unrecognized extensions do too. Output files use
a same-directory exclusive temporary path named `<target>.odin-rdf.tmp`; the
target is replaced only after conversion and close succeed. Existing temporary
files are never overwritten. Standard output deliberately remains streaming
and can contain earlier records if a later parse error occurs.

`convert` accepts `--max-records N` for all input syntaxes,
`--max-line-bytes N` for N-Triples/N-Quads, and `--max-statement-bytes N` for
Turtle, plus `--max-document-bytes N` for JSON-LD, RDF/XML, and TriG. Each `N` is a positive decimal integer; the CLI maps the values to
`Reader_Limits` before opening the source parser.

`format` accepts Turtle or TriG input, inferring `.ttl` or `.trig` file paths;
standard input requires `--from turtle` or `--from trig`. It retains the
complete graph or dataset and writes grouped, deterministic output in the same
syntax. It does not emit partial output after a parse or formatting failure.
Prefix inference is enabled by default; use `--no-infer-prefixes` to use only
repeated explicit `--prefix` declarations. `--max-triples N` bounds retained
Turtle triples, while `--max-quads N` bounds retained TriG quads. Each is
required to be a positive decimal integer when present and is only valid for
its corresponding input syntax.

## Memory and reader entry points

The memory entry point is best when all bytes are already available. Reader
entry points bound input buffering, preserve I/O errors, report progress, and
retain parser state across arbitrary chunk boundaries. Both paths use the same
grammar and are tested for equivalent output, error codes, and source locations.

Line-oriented N-Triples and N-Quads readers bound one physical line. Turtle's
reader bounds one top-level production because valid strings and collections
may span lines. JSON-LD, RDF/XML, and TriG retain one bounded document. A reader that
repeatedly returns no bytes and no error is eventually rejected with
`No_Progress`.

## Stability policy

Error enum values and function signatures are API. Message strings are stable
diagnostic text but are not intended as machine-readable identifiers. New
syntax packages should use `parse_error_message`; new writers should use
`write_error_message`. Package-internal parsing helpers remain private, and the
streaming parser does not expose an AST.
