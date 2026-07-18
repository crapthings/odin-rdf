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
```

Both operations accept a complete bounded JSON-LD document and atomically
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

1. Expansion core: aliases, `@id`, `@type`, scalar and value expansion,
   lists, `@set`, language and index maps, `@reverse`, and `@graph`.
2. A pinned W3C Expand core selection with structural JSON comparison.
3. Flatten node-map generation and graph merging over the expanded document.
4. A pinned W3C Flatten core selection, including index and named-graph cases.
5. Only then add Framing; framing consumes the same node-map representation.

The existing JSON-LD to-RDF, RDF-to-JSON-LD, and context-directed compaction
gates remain mandatory for every stage.
