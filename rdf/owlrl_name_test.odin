package rdf

import "core:testing"

@(test)
test_owl_rl_pattern_literal_status :: proc(t: ^testing.T) {
	testing.expect_value(t, owl_rl_pattern_literal_status(typed_literal(" en-US ", "http://www.w3.org/2001/XMLSchema#language")), OWL_RL_Pattern_Status.Valid)
	testing.expect_value(t, owl_rl_pattern_literal_status(typed_literal("en--US", "http://www.w3.org/2001/XMLSchema#language")), OWL_RL_Pattern_Status.Not_In_Value_Space)
	testing.expect_value(t, owl_rl_pattern_literal_status(typed_literal("  ns:node  ", "http://www.w3.org/2001/XMLSchema#Name")), OWL_RL_Pattern_Status.Valid)
	testing.expect_value(t, owl_rl_pattern_literal_status(typed_literal("ns:node", "http://www.w3.org/2001/XMLSchema#NCName")), OWL_RL_Pattern_Status.Not_In_Value_Space)
	testing.expect_value(t, owl_rl_pattern_literal_status(typed_literal("_n-1", "http://www.w3.org/2001/XMLSchema#NCName")), OWL_RL_Pattern_Status.Valid)
	testing.expect_value(t, owl_rl_pattern_literal_status(typed_literal("  :1.\u00b7  ", "http://www.w3.org/2001/XMLSchema#NMTOKEN")), OWL_RL_Pattern_Status.Valid)
	testing.expect_value(t, owl_rl_pattern_literal_status(typed_literal("first second", "http://www.w3.org/2001/XMLSchema#Name")), OWL_RL_Pattern_Status.Not_In_Value_Space)
}
