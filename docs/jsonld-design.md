# JSON-LD design

`rdf/jsonld` is a bounded JSON-LD document processor that emits RDF dataset
quads. It is intentionally not a streaming syntax parser: JSON-LD context
processing, lists, reverse properties, and named graphs require retained
document state.

## Public boundary

```odin
parse(input: string, sink: Sink, options: Options = {}, user_data: rawptr = nil) -> Parse_Error
parse_reader(reader: io.Reader, sink: Sink, options: Reader_Options = {}, user_data: rawptr = nil) -> Reader_Result
expand(builder: ^strings.Builder, input: string, options: Expand_Options = {}) -> Expand_Error
flatten(builder: ^strings.Builder, input: string, options: Flatten_Options = {}) -> Flatten_Error
frame(builder: ^strings.Builder, input, frame: string, options: Frame_Options = {}) -> Frame_Error
```

`parse` and `parse_reader` produce `rdf.Quad` values. String fields are transient and
valid for the callback only. The reader retains at most `max_document_bytes`
(16 MiB by default); it is a bounded document reader, not a record stream.

`expand` is separate from `serialize`: it takes a JSON-LD document and emits
the JSON-LD Expansion form before an RDF conversion could discard ordinary
`@index` annotations. It is atomic, deterministic, and independently bounds
the expanded output at 32 MiB by default. Its first W3C-gated core includes
aliases, value/type/language expansion, `@list`, nested `@set`, `@nest`, language and
index containers, reverse maps, default/named graph expansion, and document-level
`@graph`, `@id`, and `@type` containers including `@graph` composites.

`flatten` consumes that expanded-document boundary and emits a deterministic,
bounded node-map. It merges embedded nodes by identifier, preserves lists and
ordinary `@index`, applies reverse relationships to their referenced nodes,
and retains nested graph objects.

`frame` reuses that bounded node-map and atomically emits a context-directed
`@graph` document. Its first profile matches nodes by `@id`, `@type`, and
required ordinary properties, then recursively embeds values selected by nested
property frames. Cycles are represented by `@id` references. It bounds nodes,
embedding depth (128 by default), and output bytes (32 MiB by default). It
supports `@explicit`, scalar and type defaults, value/list patterns, all
standard embed modes, ordinary-property `@requireAll`, and basic reverse
framing, bounded `@included` selection, and bounded named-graph subframes.
Graph subframes resolve references against a graph-local node view and
graph-container terms compact selected graph members without a synthetic
`@graph` wrapper. Scoped graph storage and the remaining Framing policy matrix
remain later work.

```odin
serialize(builder: ^strings.Builder, quads: []rdf.Quad,
          options: Serialize_Options = {}) -> Serialize_Error
```

`serialize` is the reverse, dataset-to-document boundary. It atomically appends
deterministic expanded JSON-LD, preserves default and named graphs, removes exact
duplicate quads, and defaults to a 100,000-quad admission limit. It rejects a
blank-node label reused by distinct source scopes rather than serializing an
identity-changing document.

`Serialize_Options.use_rdf_type` keeps `rdf:type` as an ordinary IRI property
instead of emitting `@type`. `use_native_types` emits valid `xsd:boolean`,
`xsd:integer`, and finite `xsd:double` lexical forms as JSON scalars; invalid,
non-finite, and all other typed values remain explicit value objects. The
serializer recognizes `rdf:JSON` values and emits their validated JSON payload
with `"@type": "@json"`.

`Options.rdf_direction` and `Serialize_Options.rdf_direction` default to
`.None`, which follows JSON-LD's default RDF mapping and omits `@direction`.
Set both to `.I18n_Datatype` for a lossless RDF round trip: directional strings
map to the JSON-LD 1.1 `https://www.w3.org/ns/i18n#` datatype form and are
restored as `@language` and `@direction` during serialization or compaction.
Set both to `.Compound_Literal` to use the alternative RDF blank-node mapping
with `rdf:value`, `rdf:direction`, and optional `rdf:language` instead.

```odin
compact(builder: ^strings.Builder, quads: []rdf.Quad, context_text: string,
        options: Compact_Options = {}) -> Compact_Error
```

`compact` is the developer-facing output path when a consumer supplies an
explicit JSON-LD context. It first produces the same bounded RDF-to-JSON-LD
dataset view as `serialize`, then compacts it atomically. A context definition,
context array, or an `{"@context": ...}` context document is accepted; remote
context URLs remain opt-in through `Compact_Options.context_options`.
`Compact_Array_Policy.Compact` is the default and emits scalars for one
non-container value. `Preserve` retains arrays. Native booleans, integers, and
finite doubles are on by default for compaction; select
`Compact_Native_Type_Policy.Lexical` for explicit lexical value objects.
Ordinary `@index` keys are not RDF statements, so a dataset-only call cannot
recover them. Set `Compact_Options.source_document` to the original JSON-LD
document when preserving those annotations is required; its RDF meaning is
validated against the supplied dataset during compaction.

`Options` bounds document bytes, JSON nesting, processed contexts, remote
contexts, and emitted quads. Its `Document_Loader` is opt-in. The package never
opens URLs itself, so applications choose caching, authentication, redirects,
and network policy explicitly.

## Implemented to-RDF core

The processor accepts strict JSON and handles local contexts, `@base`,
`@vocab`, prefixes, term aliases, `@id`, `@type`, value objects, language and
datatype coercion, arrays, nested `@set`, and `@list`, reverse properties, `@graph`,
`@included`, `@nest`, and `@json` value objects. It emits default and named graph quads and keeps
explicit blank-node identifiers document-local.

The input processor remains a deliberately bounded JSON-LD 1.1 to-RDF profile.
The serializer supplies the interoperable expanded RDF-to-JSON-LD form: it
handles complete and partial RDF list collapse, shared blank nodes across named
graphs, native scalar options, and graph-node merging. It does not compact IRIs
or infer a context. `compact` adds explicit-context IRI, keyword, typed-value,
language-value, language-map, list-container, `@set`, and named-graph
compaction. The input processor accepts language and index containers,
including their `@set` combinations; an
ordinary `@index` is JSON-LD annotation rather than RDF data, so an RDF
dataset cannot later reproduce its original keys. A custom `@index` property
does become an RDF statement and is retained. Term- and type-scoped local
contexts are supported, as are single-level `@import` source contexts through
the same opt-in document loader. Expansion and Flattening preserve JSON-LD 1.1
base and term `@direction` mappings on expanded value objects. Its opt-in
`.I18n_Datatype` mode maps those values through RDF and restores them in
serialization and compaction; `.Compound_Literal` supplies the standard RDF
blank-node alternative. A built-in HTTP loader and the remaining Framing policy
matrix remain separate conformance milestones.
Document Expansion, Flattening, and Framing honor `@propagate: false` by
rolling back to the previous context for nested node objects; type-scoped
contexts are non-propagating unless they set `@propagate: true`. `@protected`
term definitions are retained across contexts and reject later incompatible
redefinitions; definitions that share the importing context may still override
its sourced terms before protection is applied.

## Conversion and CLI

`convert.Format.JSON_LD` is both an input format and a bounded batch output
target. Every supported RDF source syntax can produce deterministic expanded
JSON-LD through `--to jsonld`; unlike record targets, it requires a positive
`--max-records N` and writes only after the complete dataset succeeds.
Pass `--context context.jsonld` to `odin-rdf convert` to compact that same
bounded dataset with a local context file. The command keeps expanded JSON-LD
as the default because no context has to be guessed; it never fetches a remote
context.
`odin-rdf convert` recognizes `jsonld`, `json-ld`, and `json`, and infers
`.jsonld` and `.json`. `--max-document-bytes N` sets the retained JSON-LD
document limit. CLI conversion intentionally has no document loader, so remote
contexts fail explicitly instead of causing implicit network access.

## Conformance discipline

The repository pins the W3C JSON-LD API test corpus. In addition to the stable
JSON-LD-to-RDF core selection, `scripts/run-w3c-jsonld-fromrdf-tests.sh` runs
46 RDF-to-JSON-LD core vectors, including RDF lists, named graphs,
`useNativeTypes`, `useRdfType`, duplicate triples, `rdf:JSON`, and i18n
directional datatypes and compound literals.
It compares canonical RDF datasets after parsing the expected and generated
JSON-LD, so irrelevant node/object ordering does not hide or create semantic
differences. `scripts/run-w3c-jsonld-tests.sh` runs 162 to-RDF vectors,
including default direction omission, `i18n-datatype`, and compound-literal
output. `scripts/run-w3c-jsonld-compact-tests.sh` runs 246 Compaction cases:
229 positive vectors whose compacted JSON is compared structurally with the
pinned expected output, plus 17 negative cases. The positive gate includes
graph/index and graph/id map keys with `@none` aliases, document-base relative
identifiers, parent paths, query/fragment references, and keyword-like path
segments. This remains a pinned core selection, not a claim of complete JSON-LD
1.1 Compaction conformance.

Each positive vector supplies its original source document to Compaction and
also undergoes RDF-semantic comparison. The structural comparison ignores JSON
object-key order but preserves array order and shape, so it catches
container/array regressions as well as semantic drift. It covers
property-valued index maps, scoped nested nodes, default/term/list/language
containers, direct and aliased `@type` `@set` forms, compact-IRI output,
source-recovered `@graph` and graph-map forms, `@included`, JSON literals,
and nested source structures. RDF-invisible source annotations are restored
only when their association with the serialized dataset is unique.

`scripts/run-w3c-jsonld-framing-tests.sh` runs 87 pinned Framing vectors for
nested and deep-node embedding, type and `@id` selection, value/list patterns,
all embed modes, defaults, `@requireAll`, `@set` containers, protected empty
contexts, `@included` selection, JSON-LD 1.1 graph shape, and invalid frame
paths. It structurally compares the context-directed result.
The selected vectors are the executable boundary for the current framing
profile, not a claim of full JSON-LD Framing conformance.

The Expansion gate includes five sourced-context `@import` vectors. It runs
106 vectors in total and covers
source overrides, relative source identifiers resolved through an importer's
`@vocab`, protected source definitions, and the expected rejection of
incompatible protected-term redefinitions. It also covers property-, type-,
and embedded-context propagation, sourced propagation, and invalid
`@propagate` values. Default and term directions, list and language-map
directions, explicit value directions, and invalid direction forms bring its
current total to 106 cases.

The document core is specified in
[Expanded JSON-LD document core](jsonld-expanded-document-design.md). Future
work extends its framing policy matrix and broader JSON-LD 1.1 conversion
coverage.
