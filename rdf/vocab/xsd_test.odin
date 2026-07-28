package vocab

import "core:testing"

@(test)
test_shared_xsd_datatype_iris_are_exact :: proc(t: ^testing.T) {
	testing.expect_value(t, XSD_NAMESPACE, "http://www.w3.org/2001/XMLSchema#")
	testing.expect_value(t, XSD_STRING, XSD_NAMESPACE + "string")
	testing.expect_value(t, XSD_BOOLEAN, XSD_NAMESPACE + "boolean")
	testing.expect_value(t, XSD_INTEGER, XSD_NAMESPACE + "integer")
	testing.expect_value(t, XSD_DECIMAL, XSD_NAMESPACE + "decimal")
	testing.expect_value(t, XSD_DOUBLE, XSD_NAMESPACE + "double")
	testing.expect_value(t, XSD_FLOAT, XSD_NAMESPACE + "float")
}
