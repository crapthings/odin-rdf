package rdf

import "core:testing"

@(test)
test_owl_rl_value_relation_compares_string_and_plain_literal_values :: proc(t: ^testing.T) {
	normalized_string := "http://www.w3.org/2001/XMLSchema#normalizedString"
	token := "http://www.w3.org/2001/XMLSchema#token"

	testing.expect_value(t, owl_rl_literal_value_relation(literal("a b"), typed_literal("a\tb", normalized_string)), OWL_RL_Literal_Value_Relation.Same)
	testing.expect_value(t, owl_rl_literal_value_relation(typed_literal("  a  b  ", token), literal("a b")), OWL_RL_Literal_Value_Relation.Same)
	testing.expect_value(t, owl_rl_literal_value_relation(language_literal("colour", "EN-gb"), language_literal("colour", "en-GB")), OWL_RL_Literal_Value_Relation.Same)
	testing.expect_value(t, owl_rl_literal_value_relation(language_literal("colour", "en"), literal("colour")), OWL_RL_Literal_Value_Relation.Different)
}

@(test)
test_owl_rl_value_relation_compares_floating_cross_datatype_values :: proc(t: ^testing.T) {
	float_datatype := "http://www.w3.org/2001/XMLSchema#float"
	double_datatype := "http://www.w3.org/2001/XMLSchema#double"

	testing.expect_value(t, owl_rl_literal_value_relation(typed_literal("1.5", float_datatype), typed_literal("1.5", double_datatype)), OWL_RL_Literal_Value_Relation.Same)
	testing.expect_value(t, owl_rl_literal_value_relation(typed_literal("0.1", float_datatype), typed_literal("0.1", double_datatype)), OWL_RL_Literal_Value_Relation.Different)
	testing.expect_value(t, owl_rl_literal_value_relation(typed_literal("NaN", float_datatype), typed_literal("NaN", double_datatype)), OWL_RL_Literal_Value_Relation.Unknown)
}

@(test)
test_owl_rl_value_relation_does_not_confuse_datetime_equality_with_identity :: proc(t: ^testing.T) {
	date_time := "http://www.w3.org/2001/XMLSchema#dateTime"

	// These literals denote equal instants but retain different timezone-offset
	// properties, so the W3C datatype map treats their values as nonidentical.
	// Until exact identity mapping is implemented, OWL RL dt-eq/dt-diff must not
	// be derived for either temporal literal.
	testing.expect_value(t, owl_rl_literal_value_relation(
		typed_literal("2024-01-01T00:00:00Z", date_time),
		typed_literal("2023-12-31T19:00:00-05:00", date_time),
	), OWL_RL_Literal_Value_Relation.Unknown)
}
