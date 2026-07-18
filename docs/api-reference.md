# API reference

This reference describes the supported public surface in version 0.5.0. The
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
infer prefixes, group triples, use property-list/collection abbreviations, or
format a complete document; those require a future batch formatter.

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
