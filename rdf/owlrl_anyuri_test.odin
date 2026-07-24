package rdf

import "core:testing"

@(test)
test_owl_rl_any_uri_literal_status :: proc(t: ^testing.T) {
	datatype := "http://www.w3.org/2001/XMLSchema#anyURI"
	testing.expect_value(t, owl_rl_any_uri_literal_status(typed_literal("../relative path", datatype)), OWL_RL_AnyURI_Status.Valid)
	testing.expect_value(t, owl_rl_any_uri_literal_status(typed_literal("https://example.test/#part", datatype)), OWL_RL_AnyURI_Status.Valid)
	testing.expect_value(t, owl_rl_any_uri_literal_status(typed_literal("\x00", datatype)), OWL_RL_AnyURI_Status.Not_In_Value_Space)
}

@(test)
test_owl_rl_any_uri_value_equality :: proc(t: ^testing.T) {
	datatype := "http://www.w3.org/2001/XMLSchema#anyURI"
	compared, same := owl_rl_any_uri_literals_have_same_value(
		typed_literal("  ../a\n b  ", datatype),
		typed_literal("../a b", datatype),
	)
	testing.expect(t, compared)
	testing.expect(t, same)
}
