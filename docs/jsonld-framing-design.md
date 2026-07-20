# JSON-LD Framing delivery design

Framing is the document-level JSON-LD operation after Expansion and
Flattening. It must not be approximated through RDF conversion: ordinary
`@index` values, graph objects, and the frame's embedding rules are document
semantics.

## Target API

```odin
frame(builder: ^strings.Builder, input, frame: string,
      options: Frame_Options = {}) -> Frame_Error
```

The operation expands both documents, builds the existing bounded node-map,
matches frame subjects, applies the supported embedding policy, and compacts
the result using the frame's context. It atomically appends the compacted
result only after all steps succeed.

## Initial profile

The implemented first profile is intentionally small and testable:

- match nodes by `@id`, `@type`, and required ordinary properties;
- recursively embed values selected by nested property frames;
- preserve unmatched properties when `@explicit` is absent or false;
- filter unframed properties with `@explicit: true` and retain child IDs with
  boolean `@embed: false`;
- emit scalar `@default` values (or `null`) for missing framed properties and
  honor `@omitDefault: true`;
- apply boolean `@requireAll` to ordinary property matching;
- produce the frame context plus an `@graph` result;
- bound nodes, embedding depth, and output bytes; detect recursive embeds.

Value and list patterns, all standard `@embed` modes, basic reverse framing,
bounded `@included` selection, and bounded named-graph subframes are
implemented. A graph subframe builds a graph-local node view, so same-ID
members in the default graph and a named graph do not leak properties into one
another; graph-container terms compact the selected graph members directly.

## Test source

Framing has its own pinned W3C suite rather than living in `json-ld-api`.
`scripts/fetch-w3c-jsonld-framing-tests.sh` pins
`w3c/json-ld-framing` at `3bf782ba9a40dd1b143435abe386d38df64f2b47`.
The gate selects 87 positive and negative vectors, including empty frames,
`@explicit`, all embed modes, defaults, `@requireAll`, deep node and value
patterns, lists, `@set` containers, protected empty contexts, `@included`,
JSON-LD 1.1 graph shape, named-graph node merging, graph-local subframes,
`@graph` containers, and invalid blank-node/embed frames. It compares compacted
JSON structurally and currently passes 87/87.

## Why compaction is part of framing

The W3C frame result is context-directed JSON-LD, not merely an expanded
node-map. Publishing an expanded-only method as `frame` would make ordinary
users reimplement the most visible part of the algorithm and would not satisfy
the official outputs. The framing implementation therefore lands only with the
compacted output boundary.
