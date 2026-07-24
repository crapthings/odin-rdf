package rdf

import "core:testing"

@(test)
test_owl_rl_numeric_literal_status :: proc(t: ^testing.T) {
	testing.expect_value(t, owl_rl_numeric_literal_status(typed_literal("+001", "http://www.w3.org/2001/XMLSchema#integer")), OWL_RL_Numeric_Status.Valid)
	testing.expect_value(t, owl_rl_numeric_literal_status(typed_literal("1e2", "http://www.w3.org/2001/XMLSchema#decimal")), OWL_RL_Numeric_Status.Not_In_Value_Space)
	testing.expect_value(t, owl_rl_numeric_literal_status(typed_literal("-1", "http://www.w3.org/2001/XMLSchema#unsignedByte")), OWL_RL_Numeric_Status.Not_In_Value_Space)
	testing.expect_value(t, owl_rl_numeric_literal_status(typed_literal("255", "http://www.w3.org/2001/XMLSchema#unsignedByte")), OWL_RL_Numeric_Status.Valid)
	testing.expect_value(t, owl_rl_numeric_literal_status(typed_literal("256", "http://www.w3.org/2001/XMLSchema#unsignedByte")), OWL_RL_Numeric_Status.Not_In_Value_Space)
	testing.expect_value(t, owl_rl_numeric_literal_status(typed_literal("9223372036854775808", "http://www.w3.org/2001/XMLSchema#long")), OWL_RL_Numeric_Status.Not_In_Value_Space)
	testing.expect_value(t, owl_rl_numeric_literal_status(typed_literal("-9223372036854775808", "http://www.w3.org/2001/XMLSchema#long")), OWL_RL_Numeric_Status.Valid)
	testing.expect_value(t, owl_rl_numeric_literal_status(typed_literal("-9223372036854775809", "http://www.w3.org/2001/XMLSchema#long")), OWL_RL_Numeric_Status.Not_In_Value_Space)
}

@(test)
test_owl_rl_numeric_value_equality :: proc(t: ^testing.T) {
	left := typed_literal("+001", "http://www.w3.org/2001/XMLSchema#integer")
	right := typed_literal("1.00", "http://www.w3.org/2001/XMLSchema#decimal")
	compared, same := owl_rl_numeric_literals_have_same_value(left, right)
	testing.expect(t, compared)
	testing.expect(t, same)

	compared, same = owl_rl_numeric_literals_have_same_value(
		typed_literal("-0.0", "http://www.w3.org/2001/XMLSchema#decimal"),
		typed_literal("0", "http://www.w3.org/2001/XMLSchema#integer"),
	)
	testing.expect(t, compared)
	testing.expect(t, same)

	compared, same = owl_rl_numeric_literals_have_same_value(
		typed_literal("1.01", "http://www.w3.org/2001/XMLSchema#decimal"),
		typed_literal("1", "http://www.w3.org/2001/XMLSchema#integer"),
	)
	testing.expect(t, compared)
	testing.expect(t, !same)
}
