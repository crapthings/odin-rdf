# RDF/XML to RDF design

`rdf/rdfxml` transforms a bounded RDF/XML document into default-graph RDF
quads. It is an input package: N-Triples, N-Quads, and Turtle remain the
supported serialization targets.

## Processing boundary

RDF/XML depends on XML namespace scope, inherited `xml:base` and `xml:lang`,
and nested node/property elements. The package therefore retains one XML
document before emitting quads. This is a deliberate bounded-document
exception to the repository's streaming-first rule, not a graph store.

The core supports RDF/XML node and property elements, typed nodes, property
attributes, `rdf:about`, `rdf:ID`, `rdf:nodeID`, `rdf:resource`,
`rdf:datatype`, `rdf:parseType="Resource"`,
`rdf:parseType="Collection"`, `rdf:parseType="Literal"`, and RDF
reification from `rdf:ID`. Relative references use the caller's `base_iri` or
an inherited `xml:base`; no IRI is silently guessed.

`Options` has byte, element, attribute, nesting-depth, and quad limits. The
reader entry point additionally bounds its read buffer and preserves underlying
I/O failures. The implementation has no HTTP dependency, never fetches DTDs,
schemas, or remote documents, and rejects unsupported XML parser features.

For XML Literals, the parser records the raw content span before constructing
the ordinary XML DOM, because that DOM intentionally discards inter-element
whitespace. The Literal serializer then preserves text, comments, processing
instructions, XML namespace context, and explicit end tags while sorting
ordinary attributes into a stable canonical order. This retained fragment is
still bounded by the document limit and remains valid only for the sink call.

`write_triples` is the corresponding explicit output path for a complete
default graph. It creates an XML document atomically, preserves source triple
order, and maps blank nodes to deterministic XML-safe `rdf:nodeID` values.
It supports IRI, blank-node, language, datatype, and XML Literal objects.
RDF/XML requires property QNames, so a predicate must split at `#`, `/`, or
`:` into an XML Name local part; RDF/XML-reserved property IRIs are rejected.
The writer also rejects XML 1.0-unrepresentable characters and malformed XML
Literal fragments rather than emitting invalid XML.

## Explicitly deferred

Full XML Name grammar coverage, a stateful streaming document writer, and a
batch conversion target are separate milestones.

## Conformance gate

`scripts/run-w3c-rdfxml-tests.sh` pins `w3c/rdf-tests` at the repository-wide
test revision and runs 132 evaluation cases plus 41 negative cases. Evaluation
output is compared to expected N-Triples using test-only RDF graph isomorphism;
every case also runs through 1-byte, 7-byte, and default reader chunks. The
XML Literal cases cover namespace propagation and reification in addition to
the ordinary RDF/XML grammar.
