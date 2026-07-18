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
`rdf:parseType="Collection"`, text-only `rdf:parseType="Literal"`, and RDF
reification from `rdf:ID`. Relative references use the caller's `base_iri` or
an inherited `xml:base`; no IRI is silently guessed.

`Options` has byte, element, attribute, nesting-depth, and quad limits. The
reader entry point additionally bounds its read buffer and preserves underlying
I/O failures. The implementation has no HTTP dependency, never fetches DTDs,
schemas, or remote documents, and rejects unsupported XML parser features.

## Explicitly deferred

Markup-bearing XML Literals require canonical XML to preserve RDF/XML value
semantics. The package accepts text-only `rdf:parseType="Literal"` but returns
`Unsupported_Feature` when that property contains child markup; it does not
emit an approximate `rdf:XMLLiteral`. Full XML Name grammar coverage and an
RDF/XML writer are also separate milestones.

## Conformance gate

`scripts/run-w3c-rdfxml-tests.sh` pins `w3c/rdf-tests` at the repository-wide
test revision and runs 128 evaluation cases plus 41 negative cases. Evaluation
output is compared to expected N-Triples using test-only RDF graph isomorphism;
every case also runs through 1-byte, 7-byte, and default reader chunks. The
four excluded evaluations are precisely the nested-markup XML Literal cases
described above. This is a documented core selection, not a claim of complete
RDF/XML conformance.
