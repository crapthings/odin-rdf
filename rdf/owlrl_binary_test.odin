package rdf

import "core:testing"

test_owl_rl_binary_literal_status :: proc(t: ^testing.T) {
	testing.expect_value(t, owl_rl_binary_literal_status(typed_literal("0a FF", "http://www.w3.org/2001/XMLSchema#hexBinary")), OWL_RL_Binary_Status.Valid)
	testing.expect_value(t, owl_rl_binary_literal_status(typed_literal("0", "http://www.w3.org/2001/XMLSchema#hexBinary")), OWL_RL_Binary_Status.Not_In_Value_Space)
	testing.expect_value(t, owl_rl_binary_literal_status(typed_literal("T WE=", "http://www.w3.org/2001/XMLSchema#base64Binary")), OWL_RL_Binary_Status.Valid)
	testing.expect_value(t, owl_rl_binary_literal_status(typed_literal("TWE", "http://www.w3.org/2001/XMLSchema#base64Binary")), OWL_RL_Binary_Status.Not_In_Value_Space)
	testing.expect_value(t, owl_rl_binary_literal_status(typed_literal("T=WE", "http://www.w3.org/2001/XMLSchema#base64Binary")), OWL_RL_Binary_Status.Not_In_Value_Space)
}

test_owl_rl_binary_value_equality :: proc(t: ^testing.T) {
	compared, same := owl_rl_binary_literals_have_same_value(
		typed_literal("0aFF", "http://www.w3.org/2001/XMLSchema#hexBinary"),
		typed_literal("0A ff", "http://www.w3.org/2001/XMLSchema#hexBinary"),
	)
	testing.expect(t, compared)
	testing.expect(t, same)

	compared, same = owl_rl_binary_literals_have_same_value(
		typed_literal("TWE=", "http://www.w3.org/2001/XMLSchema#base64Binary"),
		typed_literal("T W E =", "http://www.w3.org/2001/XMLSchema#base64Binary"),
	)
	testing.expect(t, compared)
	testing.expect(t, same)

	compared, same = owl_rl_binary_literals_have_same_value(
		typed_literal("TWE=", "http://www.w3.org/2001/XMLSchema#base64Binary"),
		typed_literal("TWI=", "http://www.w3.org/2001/XMLSchema#base64Binary"),
	)
	testing.expect(t, compared)
	testing.expect(t, !same)

	compared, same = owl_rl_binary_literals_have_same_value(
		typed_literal("4d61", "http://www.w3.org/2001/XMLSchema#hexBinary"),
		typed_literal("TWE=", "http://www.w3.org/2001/XMLSchema#base64Binary"),
	)
	testing.expect(t, compared)
	testing.expect(t, same)
}
