package rdf

import "core:testing"

test_owl_rl_string_literal_status :: proc(t: ^testing.T) {
	testing.expect_value(t, owl_rl_string_literal_status(typed_literal("a\tb", "http://www.w3.org/2001/XMLSchema#normalizedString")), OWL_RL_String_Status.Valid)
	testing.expect_value(t, owl_rl_string_literal_status(typed_literal("  a\n b  ", "http://www.w3.org/2001/XMLSchema#token")), OWL_RL_String_Status.Valid)
	testing.expect_value(t, owl_rl_string_literal_status(typed_literal("\x00", "http://www.w3.org/2001/XMLSchema#string")), OWL_RL_String_Status.Not_In_Value_Space)
	testing.expect_value(t, owl_rl_string_literal_status(typed_literal("a", "http://www.w3.org/2001/XMLSchema#language")), OWL_RL_String_Status.Not_String_Datatype)
}

test_owl_rl_string_value_equality :: proc(t: ^testing.T) {
	compared, same := owl_rl_string_literals_have_same_value(
		typed_literal("a\tb", "http://www.w3.org/2001/XMLSchema#normalizedString"),
		typed_literal("a b", "http://www.w3.org/2001/XMLSchema#string"),
	)
	testing.expect(t, compared)
	testing.expect(t, same)

	compared, same = owl_rl_string_literals_have_same_value(
		typed_literal("  a\n b  ", "http://www.w3.org/2001/XMLSchema#token"),
		typed_literal("a b", "http://www.w3.org/2001/XMLSchema#string"),
	)
	testing.expect(t, compared)
	testing.expect(t, same)

	compared, same = owl_rl_string_literals_have_same_value(
		typed_literal("a b", "http://www.w3.org/2001/XMLSchema#token"),
		typed_literal("a  b", "http://www.w3.org/2001/XMLSchema#string"),
	)
	testing.expect(t, compared)
	testing.expect(t, !same)
}
