package vocab

import "core:testing"

@(test)
test_rdfs_core_vocabulary_iris_are_exact :: proc(t: ^testing.T) {
	testing.expect_value(t, RDFS_NAMESPACE, "http://www.w3.org/2000/01/rdf-schema#")
	testing.expect_value(t, RDFS_RESOURCE, RDFS_NAMESPACE + "Resource")
	testing.expect_value(t, RDFS_CLASS, RDFS_NAMESPACE + "Class")
	testing.expect_value(t, RDFS_LITERAL, RDFS_NAMESPACE + "Literal")
	testing.expect_value(t, RDFS_DATATYPE, RDFS_NAMESPACE + "Datatype")
	testing.expect_value(t, RDFS_DOMAIN, RDFS_NAMESPACE + "domain")
	testing.expect_value(t, RDFS_RANGE, RDFS_NAMESPACE + "range")
	testing.expect_value(t, RDFS_SUB_CLASS_OF, RDFS_NAMESPACE + "subClassOf")
	testing.expect_value(t, RDFS_SUB_PROPERTY_OF, RDFS_NAMESPACE + "subPropertyOf")
	testing.expect_value(t, RDFS_LABEL, RDFS_NAMESPACE + "label")
	testing.expect_value(t, RDFS_COMMENT, RDFS_NAMESPACE + "comment")
	testing.expect_value(t, RDFS_SEE_ALSO, RDFS_NAMESPACE + "seeAlso")
	testing.expect_value(t, RDFS_IS_DEFINED_BY, RDFS_NAMESPACE + "isDefinedBy")
}
