# N-Quads design

N-Quads extends the RDF core from triples to dataset statements without treating
the default graph as an RDF term. `rdf.Quad` therefore stores an explicit
`has_graph` flag next to a graph term:

```odin
Quad :: struct {
    subject:   Term,
    predicate: Term,
    object:    Term,
    graph:     Term,
    has_graph: bool,
}
```

When `has_graph` is false, the statement belongs to the default graph and the
`graph` field is ignored. When it is true, the graph name must be an IRI or blank
node. This matches the RDF dataset model and avoids inventing an empty IRI or
sentinel term for the default graph.

## Parser boundary

The `rdf/nquads` package mirrors the stable N-Triples shape:

- `parse(input, sink)` for complete UTF-8 documents;
- `parse_reader(reader, sink, options)` for bounded-memory streaming;
- `write_quad(builder, quad)` for atomic validated serialization;
- one blank-node scope per complete document, shared by subject, object, and
  graph-name labels;
- stable error codes, exact locations, and allocation-free error messages.

N-Triples and N-Quads retain independent document grammars. N-Quads parses its
three triple positions and optional graph name directly through the internal
shared term lexer. A caller-provided document scope keeps blank-node identity
stable across statement positions and reader chunks without constructing or
reparsing synthetic N-Triples statements.

## Conformance gate

The repository pins the W3C RDF 1.1 test suite at the same upstream commit used
for N-Triples. The N-Quads manifest contains 53 positive and 34 negative syntax
tests. Both in-memory and bounded-reader entry points must pass all 87 manifest
cases, and positive cases must additionally pass parse-write-parse round trips.
