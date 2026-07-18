# JSON-LD design

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

`Options` bounds document bytes, JSON nesting, processed contexts, remote
contexts, and emitted quads. Its `Document_Loader` is opt-in. The package never
opens URLs itself, so applications choose caching, authentication, redirects,
and network policy explicitly.

## Implemented to-RDF core

The processor accepts strict JSON and handles local contexts, `@base`,
`@vocab`, prefixes, term aliases, `@id`, `@type`, value objects, language and
datatype coercion, arrays and `@list`, reverse properties, `@graph`,
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
does become an RDF statement and is retained. Framing, a built-in HTTP loader,
directional literals, scoped contexts, `@import`, protected terms, and graph
containers remain separate conformance milestones.

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
the 28 non-directional RDF-to-JSON-LD core vectors, including RDF lists, named
graphs, `useNativeTypes`, `useRdfType`, duplicate triples, and `rdf:JSON`.
It compares canonical RDF datasets after parsing the expected and generated
JSON-LD, so irrelevant node/object ordering does not hide or create semantic
differences. The broader 1.1 suite remains the gate for future scoped-context,
direction, graph-container, and generalized RDF work.

`scripts/run-w3c-jsonld-compact-tests.sh` runs 66 local-context compaction
vectors from the same pinned corpus. It parses both generated and expected
documents and compares their RDFC-1.0 canonical RDF datasets, so the gate
checks compaction semantics without requiring meaningless object-key ordering.

The next document-level work is specified in
[Expanded JSON-LD document core](jsonld-expanded-document-design.md). It keeps
JSON-LD expansion and flattening separate from RDF dataset serialization so
that JSON-LD-only metadata is not silently lost.
