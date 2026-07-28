// RDF core vocabulary used by the current data model and RDF syntaxes.
// Constants are ordered from the namespace and model vocabulary through
// collection and legacy reification terms, then literal datatypes.
package vocab

RDF_NAMESPACE :: "http://www.w3.org/1999/02/22-rdf-syntax-ns#"

// Core RDF model vocabulary.
RDF_TYPE     :: RDF_NAMESPACE + "type"
RDF_PROPERTY :: RDF_NAMESPACE + "Property"
RDF_VALUE    :: RDF_NAMESPACE + "value"

// RDF collections.
RDF_LIST  :: RDF_NAMESPACE + "List"
RDF_FIRST :: RDF_NAMESPACE + "first"
RDF_REST  :: RDF_NAMESPACE + "rest"
RDF_NIL   :: RDF_NAMESPACE + "nil"

// Legacy RDF reification vocabulary, actively used by the RDF/XML codec.
RDF_STATEMENT :: RDF_NAMESPACE + "Statement"
RDF_SUBJECT   :: RDF_NAMESPACE + "subject"
RDF_PREDICATE :: RDF_NAMESPACE + "predicate"
RDF_OBJECT    :: RDF_NAMESPACE + "object"

// RDF literal datatypes used by the current data model, RDF/XML codec, and
// OWL RL value-space checks.
RDF_LANG_STRING :: RDF_NAMESPACE + "langString"
RDF_XML_LITERAL :: RDF_NAMESPACE + "XMLLiteral"
RDF_PLAIN_LITERAL :: RDF_NAMESPACE + "PlainLiteral"
