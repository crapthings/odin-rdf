package rdf

import "core:testing"

@(test)
test_owl_rl_numeric_value_space_membership :: proc(t: ^testing.T) {
	integer := "http://www.w3.org/2001/XMLSchema#integer"
	decimal := "http://www.w3.org/2001/XMLSchema#decimal"
	unsigned_byte := "http://www.w3.org/2001/XMLSchema#unsignedByte"
	non_negative := "http://www.w3.org/2001/XMLSchema#nonNegativeInteger"

	testing.expect_value(t, owl_rl_literal_value_membership(typed_literal("1.00", decimal), integer), OWL_RL_Value_Space_Membership.Yes)
	testing.expect_value(t, owl_rl_literal_value_membership(typed_literal("1.10", decimal), integer), OWL_RL_Value_Space_Membership.No)
	testing.expect_value(t, owl_rl_literal_value_membership(typed_literal("256", integer), unsigned_byte), OWL_RL_Value_Space_Membership.No)
	testing.expect_value(t, owl_rl_literal_value_membership(typed_literal("-0.0", decimal), non_negative), OWL_RL_Value_Space_Membership.Yes)
	testing.expect_value(t, owl_rl_literal_value_membership(typed_literal("invalid", integer), integer), OWL_RL_Value_Space_Membership.No)
	testing.expect_value(t, owl_rl_literal_value_membership(literal("1"), integer), OWL_RL_Value_Space_Membership.Unknown)
}

@(test)
test_owl_rl_string_and_any_uri_value_space_membership :: proc(t: ^testing.T) {
	string_datatype := "http://www.w3.org/2001/XMLSchema#string"
	normalized_string := "http://www.w3.org/2001/XMLSchema#normalizedString"
	token := "http://www.w3.org/2001/XMLSchema#token"
	any_uri := "http://www.w3.org/2001/XMLSchema#anyURI"
	rdfs_literal := "http://www.w3.org/2000/01/rdf-schema#Literal"

	testing.expect_value(t, owl_rl_literal_value_membership(typed_literal("a\tb", string_datatype), normalized_string), OWL_RL_Value_Space_Membership.No)
	testing.expect_value(t, owl_rl_literal_value_membership(typed_literal("a\tb", normalized_string), token), OWL_RL_Value_Space_Membership.Yes)
	testing.expect_value(t, owl_rl_literal_value_membership(typed_literal(" a b ", string_datatype), token), OWL_RL_Value_Space_Membership.No)
	testing.expect_value(t, owl_rl_literal_value_membership(typed_literal("a", token), string_datatype), OWL_RL_Value_Space_Membership.Yes)
	testing.expect_value(t, owl_rl_literal_value_membership(typed_literal("../relative", any_uri), any_uri), OWL_RL_Value_Space_Membership.Yes)
	testing.expect_value(t, owl_rl_literal_value_membership(literal("value"), any_uri), OWL_RL_Value_Space_Membership.Unknown)
	testing.expect_value(t, owl_rl_literal_value_membership(literal("value"), rdfs_literal), OWL_RL_Value_Space_Membership.Yes)
}
