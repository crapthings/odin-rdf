package vocab

import "core:testing"

@(test)
test_rdf_core_vocabulary_iris_are_exact :: proc(t: ^testing.T) {
	testing.expect_value(t, RDF_NAMESPACE, "http://www.w3.org/1999/02/22-rdf-syntax-ns#")
	testing.expect_value(t, RDF_TYPE, RDF_NAMESPACE + "type")
	testing.expect_value(t, RDF_PROPERTY, RDF_NAMESPACE + "Property")
	testing.expect_value(t, RDF_VALUE, RDF_NAMESPACE + "value")
	testing.expect_value(t, RDF_LIST, RDF_NAMESPACE + "List")
	testing.expect_value(t, RDF_FIRST, RDF_NAMESPACE + "first")
	testing.expect_value(t, RDF_REST, RDF_NAMESPACE + "rest")
	testing.expect_value(t, RDF_NIL, RDF_NAMESPACE + "nil")
	testing.expect_value(t, RDF_STATEMENT, RDF_NAMESPACE + "Statement")
	testing.expect_value(t, RDF_SUBJECT, RDF_NAMESPACE + "subject")
	testing.expect_value(t, RDF_PREDICATE, RDF_NAMESPACE + "predicate")
	testing.expect_value(t, RDF_OBJECT, RDF_NAMESPACE + "object")
	testing.expect_value(t, RDF_LANG_STRING, RDF_NAMESPACE + "langString")
	testing.expect_value(t, RDF_XML_LITERAL, RDF_NAMESPACE + "XMLLiteral")
	testing.expect_value(t, RDF_PLAIN_LITERAL, RDF_NAMESPACE + "PlainLiteral")
}
