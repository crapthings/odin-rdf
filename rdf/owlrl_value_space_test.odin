package rdf

import "core:testing"

@(test)
test_owl_rl_numeric_value_space_membership :: proc(t: ^testing.T) {
	integer := "http://www.w3.org/2001/XMLSchema#integer"
	decimal := "http://www.w3.org/2001/XMLSchema#decimal"
	unsigned_byte := "http://www.w3.org/2001/XMLSchema#unsignedByte"
	non_negative := "http://www.w3.org/2001/XMLSchema#nonNegativeInteger"

	testing.expect_value(t, owl_rl_literal_value_membership(typed_literal("1.00", decimal), integer), OWL_RL_Value_Space_Membership.Yes)
	testing.expect_value(t, owl_rl_literal_value_membership(typed_literal("1.10", decimal), integer), OWL_RL_Value_Space_Membership.No)
	testing.expect_value(t, owl_rl_literal_value_membership(typed_literal("256", integer), unsigned_byte), OWL_RL_Value_Space_Membership.No)
	testing.expect_value(t, owl_rl_literal_value_membership(typed_literal("-0.0", decimal), non_negative), OWL_RL_Value_Space_Membership.Yes)
	testing.expect_value(t, owl_rl_literal_value_membership(typed_literal("invalid", integer), integer), OWL_RL_Value_Space_Membership.No)
	testing.expect_value(t, owl_rl_literal_value_membership(literal("1"), integer), OWL_RL_Value_Space_Membership.Unknown)
}

@(test)
test_owl_rl_string_and_any_uri_value_space_membership :: proc(t: ^testing.T) {
	string_datatype := "http://www.w3.org/2001/XMLSchema#string"
	normalized_string := "http://www.w3.org/2001/XMLSchema#normalizedString"
	token := "http://www.w3.org/2001/XMLSchema#token"
	any_uri := "http://www.w3.org/2001/XMLSchema#anyURI"
	rdfs_literal := "http://www.w3.org/2000/01/rdf-schema#Literal"

	testing.expect_value(t, owl_rl_literal_value_membership(typed_literal("a\tb", string_datatype), normalized_string), OWL_RL_Value_Space_Membership.No)
	testing.expect_value(t, owl_rl_literal_value_membership(typed_literal("a\tb", normalized_string), token), OWL_RL_Value_Space_Membership.Yes)
	testing.expect_value(t, owl_rl_literal_value_membership(typed_literal(" a b ", string_datatype), token), OWL_RL_Value_Space_Membership.No)
	testing.expect_value(t, owl_rl_literal_value_membership(typed_literal("a", token), string_datatype), OWL_RL_Value_Space_Membership.Yes)
	testing.expect_value(t, owl_rl_literal_value_membership(typed_literal("../relative", any_uri), any_uri), OWL_RL_Value_Space_Membership.Yes)
	testing.expect_value(t, owl_rl_literal_value_membership(literal("value"), any_uri), OWL_RL_Value_Space_Membership.Unknown)
	testing.expect_value(t, owl_rl_literal_value_membership(literal("value"), rdfs_literal), OWL_RL_Value_Space_Membership.Yes)
}

@(test)
test_owl_rl_boolean_and_binary_value_space_membership :: proc(t: ^testing.T) {
	boolean := "http://www.w3.org/2001/XMLSchema#boolean"
	hex_binary := "http://www.w3.org/2001/XMLSchema#hexBinary"
	base64_binary := "http://www.w3.org/2001/XMLSchema#base64Binary"

	testing.expect_value(t, owl_rl_literal_value_membership(typed_literal("1", boolean), boolean), OWL_RL_Value_Space_Membership.Yes)
	testing.expect_value(t, owl_rl_literal_value_membership(typed_literal("TRUE", boolean), boolean), OWL_RL_Value_Space_Membership.No)
	testing.expect_value(t, owl_rl_literal_value_membership(typed_literal("4d61", hex_binary), base64_binary), OWL_RL_Value_Space_Membership.Yes)
	testing.expect_value(t, owl_rl_literal_value_membership(typed_literal("TWE=", base64_binary), hex_binary), OWL_RL_Value_Space_Membership.Yes)
	testing.expect_value(t, owl_rl_literal_value_membership(typed_literal("0", hex_binary), base64_binary), OWL_RL_Value_Space_Membership.No)
}

@(test)
test_owl_rl_floating_value_space_membership :: proc(t: ^testing.T) {
	float_datatype := "http://www.w3.org/2001/XMLSchema#float"
	double_datatype := "http://www.w3.org/2001/XMLSchema#double"

	testing.expect_value(t, owl_rl_literal_value_membership(typed_literal("1.5", float_datatype), double_datatype), OWL_RL_Value_Space_Membership.Yes)
	testing.expect_value(t, owl_rl_literal_value_membership(typed_literal("1.5", double_datatype), float_datatype), OWL_RL_Value_Space_Membership.Yes)
	testing.expect_value(t, owl_rl_literal_value_membership(typed_literal("0.1", double_datatype), float_datatype), OWL_RL_Value_Space_Membership.No)
	testing.expect_value(t, owl_rl_literal_value_membership(typed_literal("NaN", double_datatype), float_datatype), OWL_RL_Value_Space_Membership.Yes)
}

@(test)
test_owl_rl_datetime_value_space_membership :: proc(t: ^testing.T) {
	date_time := "http://www.w3.org/2001/XMLSchema#dateTime"
	date_time_stamp := "http://www.w3.org/2001/XMLSchema#dateTimeStamp"

	testing.expect_value(t, owl_rl_literal_value_membership(typed_literal("2024-01-01T00:00:00Z", date_time_stamp), date_time), OWL_RL_Value_Space_Membership.Yes)
	testing.expect_value(t, owl_rl_literal_value_membership(typed_literal("2024-01-01T00:00:00+01:00", date_time), date_time_stamp), OWL_RL_Value_Space_Membership.Yes)
	testing.expect_value(t, owl_rl_literal_value_membership(typed_literal("2024-01-01T00:00:00", date_time), date_time_stamp), OWL_RL_Value_Space_Membership.No)
}
