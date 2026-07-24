package rdf

import "core:testing"

@(test)
test_owl_rl_floating_literal_status :: proc(t: ^testing.T) {
	testing.expect_value(t, owl_rl_floating_literal_status(typed_literal("-.5E+2", "http://www.w3.org/2001/XMLSchema#double")), OWL_RL_Floating_Status.Valid)
	testing.expect_value(t, owl_rl_floating_literal_status(typed_literal("+INF", "http://www.w3.org/2001/XMLSchema#float")), OWL_RL_Floating_Status.Valid)
	testing.expect_value(t, owl_rl_floating_literal_status(typed_literal("NaN", "http://www.w3.org/2001/XMLSchema#float")), OWL_RL_Floating_Status.Valid)
	testing.expect_value(t, owl_rl_floating_literal_status(typed_literal("Infinity", "http://www.w3.org/2001/XMLSchema#double")), OWL_RL_Floating_Status.Not_In_Value_Space)
	testing.expect_value(t, owl_rl_floating_literal_status(typed_literal("1e", "http://www.w3.org/2001/XMLSchema#double")), OWL_RL_Floating_Status.Not_In_Value_Space)
}

@(test)
test_owl_rl_floating_value_equality :: proc(t: ^testing.T) {
	compared, same := owl_rl_floating_literals_have_same_value(
		typed_literal("-0", "http://www.w3.org/2001/XMLSchema#double"),
		typed_literal("0.0", "http://www.w3.org/2001/XMLSchema#double"),
	)
	testing.expect(t, compared)
	testing.expect(t, same)

	compared, same = owl_rl_floating_literals_have_same_value(
		typed_literal("INF", "http://www.w3.org/2001/XMLSchema#float"),
		typed_literal("1e999", "http://www.w3.org/2001/XMLSchema#float"),
	)
	testing.expect(t, compared)
	testing.expect(t, same)

	compared, same = owl_rl_floating_literals_have_same_value(
		typed_literal("NaN", "http://www.w3.org/2001/XMLSchema#float"),
		typed_literal("NaN", "http://www.w3.org/2001/XMLSchema#float"),
	)
	testing.expect(t, compared)
	testing.expect(t, !same)

	compared, same = owl_rl_floating_literals_have_same_value(
		typed_literal("-1e-999999", "http://www.w3.org/2001/XMLSchema#double"),
		typed_literal("0", "http://www.w3.org/2001/XMLSchema#double"),
	)
	testing.expect(t, compared)
	testing.expect(t, same)
}
