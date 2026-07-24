package rdf

import "core:testing"

@(test)
test_owl_rl_xml_literal_status :: proc(t: ^testing.T) {
	datatype := "http://www.w3.org/1999/02/22-rdf-syntax-ns#XMLLiteral"
	testing.expect_value(t, owl_rl_xml_literal_status(typed_literal(`<item key="x">text</item>`, datatype)), OWL_RL_XML_Literal_Status.Valid)
	testing.expect_value(t, owl_rl_xml_literal_status(typed_literal(`<!-- comment --><![CDATA[x<y]]>`, datatype)), OWL_RL_XML_Literal_Status.Valid)
	testing.expect_value(t, owl_rl_xml_literal_status(typed_literal("<unclosed>", datatype)), OWL_RL_XML_Literal_Status.Not_In_Value_Space)
}
