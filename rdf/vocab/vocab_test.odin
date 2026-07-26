package vocab

import "core:testing"

@(test)
test_shared_vocabulary_iris_are_exact :: proc(t: ^testing.T) {
	testing.expect_value(t, RDF_NAMESPACE, "http://www.w3.org/1999/02/22-rdf-syntax-ns#")
	testing.expect_value(t, RDFS_NAMESPACE, "http://www.w3.org/2000/01/rdf-schema#")
	testing.expect_value(t, XSD_NAMESPACE, "http://www.w3.org/2001/XMLSchema#")
	testing.expect_value(t, RDF_TYPE, RDF_NAMESPACE + "type")
	testing.expect_value(t, RDF_FIRST, RDF_NAMESPACE + "first")
	testing.expect_value(t, RDF_REST, RDF_NAMESPACE + "rest")
	testing.expect_value(t, RDF_NIL, RDF_NAMESPACE + "nil")
	testing.expect_value(t, RDF_LANG_STRING, RDF_NAMESPACE + "langString")
	testing.expect_value(t, XSD_STRING, XSD_NAMESPACE + "string")
	testing.expect_value(t, XSD_BOOLEAN, XSD_NAMESPACE + "boolean")
	testing.expect_value(t, XSD_INTEGER, XSD_NAMESPACE + "integer")
	testing.expect_value(t, XSD_DECIMAL, XSD_NAMESPACE + "decimal")
	testing.expect_value(t, XSD_DOUBLE, XSD_NAMESPACE + "double")
	testing.expect_value(t, XSD_FLOAT, XSD_NAMESPACE + "float")
}
