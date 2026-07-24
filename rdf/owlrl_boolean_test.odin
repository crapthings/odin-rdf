package rdf

import "core:testing"

@(test)
test_owl_rl_boolean_literal_status :: proc(t: ^testing.T) {
	testing.expect_value(t, owl_rl_boolean_literal_status(typed_literal("true", "http://www.w3.org/2001/XMLSchema#boolean")), OWL_RL_Boolean_Status.Valid)
	testing.expect_value(t, owl_rl_boolean_literal_status(typed_literal("0", "http://www.w3.org/2001/XMLSchema#boolean")), OWL_RL_Boolean_Status.Valid)
	testing.expect_value(t, owl_rl_boolean_literal_status(typed_literal("TRUE", "http://www.w3.org/2001/XMLSchema#boolean")), OWL_RL_Boolean_Status.Not_In_Value_Space)
	testing.expect_value(t, owl_rl_boolean_literal_status(typed_literal("yes", "http://www.w3.org/2001/XMLSchema#boolean")), OWL_RL_Boolean_Status.Not_In_Value_Space)
}

@(test)
test_owl_rl_boolean_value_equality :: proc(t: ^testing.T) {
	compared, same := owl_rl_boolean_literals_have_same_value(
		typed_literal("true", "http://www.w3.org/2001/XMLSchema#boolean"),
		typed_literal("1", "http://www.w3.org/2001/XMLSchema#boolean"),
	)
	testing.expect(t, compared)
	testing.expect(t, same)

	compared, same = owl_rl_boolean_literals_have_same_value(
		typed_literal("false", "http://www.w3.org/2001/XMLSchema#boolean"),
		typed_literal("1", "http://www.w3.org/2001/XMLSchema#boolean"),
	)
	testing.expect(t, compared)
	testing.expect(t, !same)
}
