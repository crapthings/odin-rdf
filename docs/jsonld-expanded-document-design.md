# Expanded JSON-LD document core

This document defines the next JSON-LD implementation boundary. It exists so
`expand`, `flatten`, and eventually `frame` share one document-level model
instead of attempting to reconstruct JSON-LD-only information from RDF.

## Why a separate layer is required

RDF conversion intentionally discards ordinary `@index` annotations and other
document presentation choices. That is correct for RDF, but it means the
existing `parse` plus `serialize` path is not a replacement for JSON-LD
Expansion or Flattening. The document core therefore runs before RDF emission
and preserves expanded JSON-LD constructs such as `@index`, `@graph`, lists,
reverse maps, and container-generated values.

## Public operations

The staged public surface is:

```odin
expand(builder: ^strings.Builder, input: string,
       options: Expand_Options = {}) -> Expand_Error
flatten(builder: ^strings.Builder, input: string,
        options: Flatten_Options = {}) -> Flatten_Error
frame(builder: ^strings.Builder, input, frame: string,
      options: Frame_Options = {}) -> Frame_Error
```

`expand` is implemented as the first bounded document-level operation. Its
current core is guarded by 106 pinned W3C Expand cases and covers aliases,
value/type/language expansion, lists, sets, transparent nesting, language/index
containers, reverse maps, default/named graph expansion, and document-level
`@graph`, `@id`, and `@type` containers. Property- and type-scoped contexts,
including `@propagate: false`, are part of the current profile.

`flatten` expands first, then builds a bounded deterministic node-map that
merges embedded nodes, allocates blank nodes, preserves list/index values,
converts reverse maps into forward node references, and retains nested graph
objects in their enclosing graph map. It consumes the same document-level
container profile as Expansion.

`frame` consumes that same node-map and returns a context-directed document.
It supports `@id`, `@type`, property, value, and list matching; recursive
embedding with standard embed modes; `@explicit`, defaults, and
`@requireAll`, and basic reverse framing. Cycles fall back to `@id`
references. Bounded `@included` selection and named-graph subframes are
supported; the remaining Framing policy matrix stays outside this profile.

All three operations accept a complete bounded JSON-LD document and atomically
append output only after successful processing. They use the existing opt-in
document loader contract; neither adds implicit network I/O.

`serialize` remains the RDF-dataset-to-expanded-JSON-LD operation. It is not
renamed or treated as a JSON-LD `expand` implementation.

## Resource and ownership model

- Input byte, nesting, local-context, and remote-context limits reuse the
  existing JSON-LD options.
- The new options add an explicit expanded-document output-byte bound and
  node-map entry bound. Zero selects documented defaults; negative values are
  invalid.
- Intermediate strings and node-map state are owned by the operation and are
  released before it returns. The destination builder is unchanged on failure.
- Deterministic JSON member ordering is required for reproducible CLI and test
  output, although JSON-LD semantic arrays remain unordered unless they are
  `@list` values.

## Delivery gates

1. Expansion core: implemented for aliases, `@id`, `@type`, scalar and value
   expansion, lists, `@set`, `@nest`, language and index maps, `@reverse`, and `@graph`.
2. A 106-case pinned W3C Expand core selection with structural JSON comparison.
3. Default-graph Flatten node-map generation: implemented.
4. A 35-case pinned W3C Flatten selection with structural JSON
   comparison: implemented.
5. Framing over the same representation: implemented with an 87-case W3C
   regression gate. Its bounded initial profile is specified in the
   [JSON-LD Framing delivery design](jsonld-framing-design.md).

The existing JSON-LD to-RDF, RDF-to-JSON-LD, and context-directed compaction
gates remain mandatory for every stage.
