package rdf

import "core:testing"

@(test)
test_owl_rl_plain_literal_status_uses_rdf11_literal_forms :: proc(t: ^testing.T) {
	testing.expect_value(t, owl_rl_plain_literal_status(literal("plain")), OWL_RL_Plain_Literal_Status.Valid)
	testing.expect_value(t, owl_rl_plain_literal_status(typed_literal("plain", "http://www.w3.org/2001/XMLSchema#token")), OWL_RL_Plain_Literal_Status.Valid)
	testing.expect_value(t, owl_rl_plain_literal_status(language_literal("colour", "en-GB")), OWL_RL_Plain_Literal_Status.Valid)
	testing.expect_value(t, owl_rl_plain_literal_status(language_literal("colour", "en--GB")), OWL_RL_Plain_Literal_Status.Not_In_Value_Space)
	testing.expect_value(t, owl_rl_plain_literal_status(typed_literal("colour@en", "http://www.w3.org/1999/02/22-rdf-syntax-ns#PlainLiteral")), OWL_RL_Plain_Literal_Status.Not_Plain_Literal_Value)
}
