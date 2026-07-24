package rdf

import "core:testing"

test_owl_rl_datatype_registry :: proc(t: ^testing.T) {
	testing.expect_value(t, len(OWL_RL_DATATYPE_IRIS), 32)
	testing.expect(t, is_owl_rl_datatype("http://www.w3.org/1999/02/22-rdf-syntax-ns#PlainLiteral"))
	testing.expect(t, is_owl_rl_datatype("http://www.w3.org/2001/XMLSchema#dateTimeStamp"))
	testing.expect(t, !is_owl_rl_datatype("http://www.w3.org/2002/07/owl#real"))
	testing.expect(t, !is_owl_rl_datatype("http://www.w3.org/2001/XMLSchema#duration"))
}
