# API reference

This reference describes the supported public surface in version 0.8.0. The
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

## Conversion `rdf/convert`

```odin
convert(reader: io.Reader, output: io.Writer, options: Options) -> Result
```

`Format` is one of `N_Triples`, `N_Quads`, or `Turtle`. `Options` selects the
input and output formats, `reader_limits: Reader_Limits`, and
`turtle_prefixes: []turtle.Prefix` for explicit Turtle output declarations.
`Result` reports `statements` written, `bytes_read`, and an `Error`.

| `Reader_Limits` field | Applies to | Zero value |
| --- | --- | --- |
| `chunk_size` | All source readers | Syntax default (64 KiB). |
| `max_records` | All source readers | Unlimited. |
| `max_line_bytes` | N-Triples, N-Quads | Syntax default (16 MiB). |
| `max_statement_bytes` | Turtle | Turtle default (16 MiB). |

All limit fields must be non-negative. `max_records` maps to triple or quad
records according to the source syntax; it counts before a record is passed to
the destination writer.

`Error.code` distinguishes invalid formats, invalid Turtle prefix configuration,
source parse errors, a named graph that the selected target cannot represent,
serialization failures, and output-write failures. Source parse errors retain
their one-based `line`, `column`, parser diagnostic in `detail`, and reader
I/O error when available. Other failures have zero line and column.

The adapter streams each validated statement directly to the selected writer.
N-Triples and Turtle map to the N-Quads default graph when N-Quads is the
target. N-Quads default-graph statements can map to triples, but a named graph
is rejected for N-Triples and Turtle rather than silently losing data. The
adapter does not flush or close either stream.

## Command `cmd/odin-rdf`

```sh
odin-rdf convert INPUT --from FORMAT --to FORMAT [--output PATH] \
  [--prefix LABEL=NAMESPACE] [--max-records N] [--max-line-bytes N] \
  [--max-statement-bytes N]
odin-rdf format INPUT [--output PATH] [--prefix LABEL=NAMESPACE] \
  [--max-triples N] [--no-infer-prefixes]
```

The command accepts `ntriples`/`nt`, `nquads`/`nq`, and `turtle`/`ttl`.
`INPUT` and `--output` use `-` for standard input and output. Output files use
a same-directory exclusive temporary path named `<target>.odin-rdf.tmp`; the
target is replaced only after conversion and close succeed. Existing temporary
files are never overwritten. Standard output deliberately remains streaming
and can contain earlier records if a later parse error occurs.

`convert` accepts `--max-records N` for all input syntaxes,
`--max-line-bytes N` for N-Triples/N-Quads, and `--max-statement-bytes N` for
Turtle. Each `N` is a positive decimal integer; the CLI maps the values to
`Reader_Limits` before opening the source parser.

`format` accepts Turtle input, retains its complete graph, and writes grouped,
deterministic Turtle. It does not emit partial output after a parse or
formatting failure. Prefix inference is enabled by default; use
`--no-infer-prefixes` to use only repeated explicit `--prefix` declarations.
Because it retains triples, `--max-triples N` applies Turtle's emitted-triple
limit before the collector can retain more than `N` triples. `N` is a required,
positive decimal integer when the option is present.

## Memory and reader entry points

The memory entry point is best when all bytes are already available. Reader
entry points bound input buffering, preserve I/O errors, report progress, and
retain parser state across arbitrary chunk boundaries. Both paths use the same
grammar and are tested for equivalent output, error codes, and source locations.

Line-oriented N-Triples and N-Quads readers bound one physical line. Turtle's
reader bounds one top-level production because valid strings and collections
may span lines. A reader that repeatedly returns no bytes and no error is
eventually rejected with `No_Progress`.

## Stability policy

Error enum values and function signatures are API. Message strings are stable
diagnostic text but are not intended as machine-readable identifiers. New
syntax packages should use `parse_error_message`; new writers should use
`write_error_message`. Package-internal parsing helpers remain private, and the
streaming parser does not expose an AST.
