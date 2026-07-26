// Package vocab defines the small shared RDF vocabulary surface.
//
// Values are immutable IRI strings; this package does not construct terms,
// parse RDF, retain memory, or depend on reasoning or query packages.
package vocab

RDF_NAMESPACE  :: "http://www.w3.org/1999/02/22-rdf-syntax-ns#"
RDFS_NAMESPACE :: "http://www.w3.org/2000/01/rdf-schema#"
XSD_NAMESPACE  :: "http://www.w3.org/2001/XMLSchema#"

// RDF terms shared by the current syntax, reasoning, and query paths.
RDF_TYPE        :: RDF_NAMESPACE + "type"
RDF_FIRST       :: RDF_NAMESPACE + "first"
RDF_REST        :: RDF_NAMESPACE + "rest"
RDF_NIL         :: RDF_NAMESPACE + "nil"
RDF_LANG_STRING :: RDF_NAMESPACE + "langString"

// XSD datatypes shared by the current syntax and query paths.
XSD_STRING  :: XSD_NAMESPACE + "string"
XSD_BOOLEAN :: XSD_NAMESPACE + "boolean"
XSD_INTEGER :: XSD_NAMESPACE + "integer"
XSD_DECIMAL :: XSD_NAMESPACE + "decimal"
XSD_DOUBLE  :: XSD_NAMESPACE + "double"
XSD_FLOAT   :: XSD_NAMESPACE + "float"
