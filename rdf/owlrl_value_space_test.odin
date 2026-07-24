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
