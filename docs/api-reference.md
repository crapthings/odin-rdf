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

## Dataset canonicalization `rdf/canon`

```odin
canonicalize(builder: ^strings.Builder, quads: []rdf.Quad,
             options: Options = {}) -> Error_Code
canonical_hash(builder: ^strings.Builder, quads: []rdf.Quad,
               options: Options = {}) -> Error_Code
isomorphic(left, right: []rdf.Quad,
           options: Options = {}) -> (bool, Error_Code)
```

`canonicalize` implements W3C RDF Dataset Canonicalization 1.0 (RDFC-1.0) for
a complete dataset. It atomically appends canonical N-Quads: on any error the
destination builder is unchanged. Input quads remain caller-owned and are not
retained after the call. Exact duplicate quads are removed because an RDF
dataset is a set.

`Options.hash_algorithm` defaults to `SHA_256`; `SHA_384` is also supported.
Zero-valued limits select safe defaults: 100,000 input quads, 100,000 blank
nodes, 10,000,000 work steps, 1,000,000 permutations, and recursion depth 256.
Set a positive value to override an individual bound. Negative integer limits
return `Invalid_Option`. `Work_Limit`, `Permutation_Limit`, and
`Recursion_Limit` are intentional dataset-poisoning protections, not parser
errors; choose application-specific bounds before raising them for untrusted
input.

The output follows RDFC-1.0's canonical N-Quads escaping rules, which differ
in a few control-character cases from ordinary N-Quads serialization. Use this
API for stable equality, fixture, or signing inputs; it is deliberately batch
oriented and does not introduce graph storage or query state.

`canonical_hash` atomically appends the lowercase hexadecimal SHA-256 or
SHA-384 digest of that same canonical N-Quads form. It is appropriate for
integrity records, cache keys, and higher-level signing protocols; it does not
sign or verify data itself. `isomorphic` canonicalizes both complete datasets
under the same limits and compares their canonical text. It permits different
blank-node labels and scopes, but does not rely on hash equality, so a digest
collision cannot affect its result.

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
expand(builder: ^strings.Builder, input: string,
       options: Expand_Options = {}) -> Expand_Error
flatten(builder: ^strings.Builder, input: string,
        options: Flatten_Options = {}) -> Flatten_Error
frame(builder: ^strings.Builder, input, frame: string,
      options: Frame_Options = {}) -> Frame_Error
serialize(builder: ^strings.Builder, quads: []rdf.Quad,
          options: Serialize_Options = {}) -> Serialize_Error
compact(builder: ^strings.Builder, quads: []rdf.Quad, context_text: string,
        options: Compact_Options = {}) -> Compact_Error
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

`expand` is the document-level JSON-LD operation: it atomically appends a
deterministic expanded document before conversion to RDF can discard ordinary
`@index` annotations. `Expand_Options.context_options` has the same bounded,
opt-in loader policy as `parse`; `max_output_bytes` defaults to 32 MiB. The
current core covers aliases, values and coercion, `@list`, `@set`, `@nest`,
language and index containers, `@reverse`, default/named graph expansion, and
document-level `@graph`, `@id`, and `@type` containers (including
`[@graph, @index]` / `[@graph, @id]` composites). It supports term- and
type-scoped local contexts plus single-level `@import` source contexts through
the opt-in loader, and rejects incompatible redefinitions of `@protected`
terms with `Protected_Term_Redefinition`. Sourced definitions retain stable
term ownership and use the importing context's `@vocab` for relative `@id`
values. Expansion, Flattening, and Framing honor `@propagate: false`: nested
node objects restore the previous context, while type-scoped contexts are
non-propagating unless they explicitly set `@propagate: true`.
Expansion and Flattening also retain JSON-LD 1.1 `@direction` on value objects
from default and term mappings. By default, RDF conversion omits that metadata,
as JSON-LD's `rdfDirection: null` mapping requires. Set
`Options.rdf_direction = .I18n_Datatype` to encode directional strings with
the JSON-LD 1.1 i18n datatype; set `Serialize_Options.rdf_direction` (including
`Compact_Options.serializer_options`) to the same mode to restore
`@language`/`@direction` on output. `.Compound_Literal` instead uses and
recognizes the RDF `rdf:value` / `rdf:direction` / optional `rdf:language`
blank-node representation.

`flatten` first expands the document, then atomically produces a deterministic
node-map. It merges embedded nodes by `@id`, allocates bounded blank nodes,
preserves lists and `@index`, normalizes reverse properties, and retains nested
`@graph` objects. Set `Flatten_Options.output_context` to compact that node-map
with a supplied JSON-LD context; set `array_policy = .Preserve` to implement
the standard `compactArrays: false` shape.
`Flatten_Options.max_nodes` defaults to 100,000 and `max_output_bytes` to
32 MiB.

`frame` expands both source and frame, builds the bounded flattened node-map,
and atomically writes the frame context. It matches `@id`, `@type`, ordinary
properties, value patterns, and list patterns; nested property frames embed
matching nodes, while cycles become `@id` references. `@explicit`, defaults,
`@omitDefault`, and `@requireAll` are supported. Embed controls include
boolean values and `@always`, `@never`, `@first`, `@last`, and `@once`.
JSON-LD 1.1 is the default processing mode and emits one framed node directly;
use `.Json_LD_1_0` for legacy `@graph` output, or set both `omit_graph` and
`omit_graph_set` to select graph shape explicitly. `max_nodes`,
`max_embedding_depth` (128), and `max_output_bytes` (32 MiB) bound retained
and materialized state. Basic reverse framing and reverse-term aliases are
supported, as are bounded `@included` selection and named-graph subframes.
`@graph` container terms compact selected local graph members directly; broader
graph storage and the remaining Framing policy matrix remain unsupported.

`serialize` atomically appends deterministic expanded JSON-LD for a complete
dataset, including named graphs. `Serialize_Options.max_quads` defaults to
100,000 and bounds the retained/sorted dataset; exact duplicate quads are
removed. It rejects an identical blank-node label from different source scopes,
because JSON-LD would otherwise merge two RDF nodes. It deliberately does not
compact IRIs or infer a context. `use_rdf_type` preserves `rdf:type` as an IRI
property; `use_native_types` emits valid booleans, integers, and finite doubles
as JSON scalars. Complete and partial RDF lists are collapsed only when their
blank nodes are not shared in another graph. Valid `rdf:JSON` typed literals
are emitted as `@json` values and `@json` value objects parse back to
`rdf:JSON`. `Serialize_Options.rdf_direction = .I18n_Datatype` recognizes
JSON-LD i18n directional datatypes and emits `@direction`; the default keeps
those datatypes explicit.

`compact` adds an atomic context-directed output API. `context_text` accepts a
JSON context definition, context array, or a document containing `@context`.
`Compact_Options.context_options` carries the same base IRI, resource limits,
and opt-in document loader policy as `parse`; `serializer_options` carries the
dataset admission and RDF output choices. The default array policy compacts a
single ordinary value to a scalar and preserves `@list`/`@set` containers;
`Preserve` retains ordinary arrays. Native boolean, integer, and finite double
values are emitted by default; `native_type_policy = .Lexical` retains lexical
value objects. Language containers compact retained RDF language literals as
language maps. Index containers are accepted on input; ordinary `@index`
annotations cannot be reconstructed from a dataset alone, while custom index
properties remain RDF statements. To preserve ordinary index keys, set
`Compact_Options.source_document` to the original JSON-LD input; compaction
uses it only to associate RDF-invisible annotations with the supplied dataset.
It also restores the direct form of one unadorned anonymous `@graph` container
when the source has one anonymous root and one unambiguous graph edge, using
`@included` for multiple graph nodes; graph `@index`, `@id`, and `@set` map
forms are not inferred by that recovery except for one anonymous
`[@graph, @index]` container with one source index key and one anonymous
`[@graph, @id]` or `[@graph, @index]` container's `@none` key, including
`@set`, plus an explicit source ID for `[@graph, @id]` and a named graph's
source `@index` member. When a base IRI is supplied, document-relative
node identifiers and `@id`-coerced values use RFC 3986 relative references;
keyword-like path segments retain an explicit `./` prefix. The CLI exposes the
same operation through
`odin-rdf convert --to jsonld --context context.jsonld`; without `--context`,
it intentionally emits deterministic expanded JSON-LD.

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

`rdfxml.write_triples(builder, triples)` atomically appends one complete,
default-graph RDF/XML document. It intentionally retains no document state:
callers supply the complete graph, and it emits one `rdf:Description` per
triple in source order. Blank nodes receive deterministic XML-safe `rdf:nodeID`
values. IRI predicates must have an XML Name local part after a `#`, `/`, or
`:` namespace boundary; names reserved by RDF/XML and XML 1.0-unrepresentable
characters return a `Write_Error`. `rdf:XMLLiteral` values must be valid XML
fragments. This batch writer is not a streaming conversion target.

```odin
init_document_writer(writer: ^Document_Writer, builder: ^strings.Builder,
                     options: Document_Writer_Options = {}) -> Write_Error
write_document_triple(writer: ^Document_Writer, triple: rdf.Triple) -> Write_Error
finish_document_writer(writer: ^Document_Writer) -> Write_Error
destroy_document_writer(writer: ^Document_Writer)
```

The stateful writer is the separate, explicit-prefix path for long documents.
`Namespace {prefix, iri}` declarations are emitted on the root element; every
non-RDF predicate must split to one of those exact namespace IRIs. A zero
`max_blank_nodes` selects the bounded 100,000-node default, while a negative
value is invalid. The writer copies callback-scoped blank-node labels, so
identity remains stable across calls. `write_document_triple` validates and
buffers each record before appending it, but an initialized document is
inherently streaming: callers must call `finish_document_writer` to close it.
Namespace slices and strings must remain valid until `destroy_document_writer`.

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

`Format` is one of `N_Triples`, `N_Quads`, `Turtle`, `TriG`, `JSON_LD`, or
`RDF_XML`. JSON-LD and RDF/XML are bounded batch output targets. `Options` selects the
input and output formats, `reader_limits: Reader_Limits`, and
`turtle_prefixes: []turtle.Prefix` for explicit Turtle and TriG output
declarations.
`Result` reports `statements` written, `bytes_read`, and an `Error`.

| `Reader_Limits` field | Applies to | Zero value |
| --- | --- | --- |
| `chunk_size` | All source readers | Syntax default (64 KiB). |
| `max_records` | All source readers; required for RDF/XML and JSON-LD output | Unlimited for streaming targets. |
| `max_line_bytes` | N-Triples, N-Quads | Syntax default (16 MiB). |
| `max_statement_bytes` | Turtle | Turtle default (16 MiB). |
| `max_document_bytes` | JSON-LD, RDF/XML, TriG | Syntax default (16 MiB). |

All limit fields must be non-negative. `max_records` maps to triple or quad
records according to the source syntax; it counts before a record is passed to
the destination writer. RDF/XML and JSON-LD output require it to be positive
and use it as the owned dataset admission bound.

`Error.code` distinguishes invalid formats, invalid Turtle/TriG prefix configuration,
source parse errors, a named graph that the selected target cannot represent,
serialization failures, and output-write failures. Source parse errors retain
their one-based `line`, `column`, parser diagnostic in `detail`, and reader
I/O error when available. Other failures have zero line and column.

The adapter streams each validated statement directly to the selected writer,
except for RDF/XML and JSON-LD. Both retain a complete bounded dataset, then
write one document only after parsing and serialization succeed; standard
output remains untouched on a parse or writer failure. N-Triples and Turtle
map to the N-Quads, TriG, RDF/XML, or JSON-LD default graph when those are targets.
N-Quads default-graph statements can map to triples, while a named graph is
rejected for N-Triples, Turtle, and RDF/XML rather than silently losing data.
The adapter does not flush or close either stream.

## Command `cmd/odin-rdf`

```sh
odin-rdf convert INPUT [--from FORMAT] [--to FORMAT] [--output PATH] \
  [--prefix LABEL=NAMESPACE] [--max-records N] [--max-line-bytes N] \
  [--max-statement-bytes N] [--max-document-bytes N]
odin-rdf format INPUT [--from turtle|trig] [--output PATH] \
  [--prefix LABEL=NAMESPACE] [--max-triples N] [--max-quads N] \
  [--no-infer-prefixes]
odin-rdf canon INPUT [--from FORMAT] [--output PATH] \
  [--algorithm sha256|sha384] [--max-quads N] [reader limits]
odin-rdf hash INPUT [--from FORMAT] [--output PATH] \
  [--algorithm sha256|sha384] [--max-quads N] [reader limits]
odin-rdf compare LEFT RIGHT [--from FORMAT] [--base IRI] [--algorithm sha256|sha384] \
  [--max-quads N] [reader limits]
odin-rdf diff BEFORE AFTER [--from FORMAT] [--output PATH] \
  [--algorithm sha256|sha384] [--max-quads N] [reader limits]
```

The command accepts `ntriples`/`nt`, `nquads`/`nq`, `turtle`/`ttl`, `trig`,
`jsonld`/`json-ld`/`json`, and
`rdfxml`/`rdf-xml`/`rdf/xml`/`rdf`/`xml`. RDF/XML output requires
`--max-records N` and is batch-atomic. It infers formats from file paths ending
in `.nt`, `.nq`, `.ttl`, `.jsonld`, `.json`, `.rdfxml`, `.rdf`, `.xml`, or `.trig`; explicit
`--from` and `--to` options override that inference. `INPUT` and `--output`
use `-` for standard input and output, which requires the matching explicit
format option; unrecognized extensions do too. Output files use
a same-directory exclusive temporary path named `<target>.odin-rdf.tmp`; the
target is replaced only after conversion and close succeed. Existing temporary
files are never overwritten. Standard output remains streaming for ordinary
record targets and can contain earlier records if a later parse error occurs;
RDF/XML output is the complete-graph exception and remains empty until success.

`convert` accepts `--max-records N` for all input syntaxes,
`--max-line-bytes N` for N-Triples/N-Quads, and `--max-statement-bytes N` for
Turtle, plus `--max-document-bytes N` for JSON-LD, RDF/XML, and TriG. RDF/XML
and JSON-LD output require `--max-records N`. Each `N` is a positive decimal integer; the CLI maps the values to
`Reader_Limits` before opening the source parser.

`convert --to jsonld --context PATH` reads one local JSON-LD context document
and invokes `jsonld.compact` after bounded dataset collection. `PATH` cannot be
standard input and cannot be the output path. This remains all-or-nothing for
standard output and file targets; `--max-document-bytes` bounds both JSON-LD
input and the context file. Without `--context`, JSON-LD conversion emits the
deterministic expanded form.

`format` accepts Turtle or TriG input, inferring `.ttl` or `.trig` file paths;
standard input requires `--from turtle` or `--from trig`. It retains the
complete graph or dataset and writes grouped, deterministic output in the same
syntax. It does not emit partial output after a parse or formatting failure.
Prefix inference is enabled by default; use `--no-infer-prefixes` to use only
repeated explicit `--prefix` declarations. `--max-triples N` bounds retained
Turtle triples, while `--max-quads N` bounds retained TriG quads. Each is
required to be a positive decimal integer when present and is only valid for
its corresponding input syntax.

`canon`, `hash`, `compare`, and `diff` accept every supported input syntax and collect
one complete, owned dataset before calling `rdf/canon`. Their default
`--max-quads` is 100,000 and bounds both the collector and canonicalization;
reader-limit options have the same syntax-specific behavior as `convert`.
`canon` writes atomic canonical N-Quads and `hash` writes a lowercase
hexadecimal SHA-256 digest by default (SHA-384 with `--algorithm sha384`).
`compare` accepts two file paths, may infer a different format for each, and
accepts `--base IRI` when relative identifiers in a base-aware syntax (including
JSON-LD) must resolve consistently. It prints
`equal` or `different`, and returns exit status 0, 1, or 2 for equal,
different, or an error. `diff` accepts two file paths, may also infer each format
independently, and atomically writes canonical N-Quads lines prefixed with `- `
(before-only) or `+ ` (after-only). It returns 0 when there are no changes, 1
when there are changes, or 2 on any error. Its output is a deterministic
canonical text diff, not a minimum blank-node edit script. They do not implement
signing, storage, or querying.

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
