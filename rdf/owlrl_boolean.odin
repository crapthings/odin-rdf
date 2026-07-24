package rdf

// OWL_RL_Boolean_Status describes xsd:boolean value-space validation.
OWL_RL_Boolean_Status :: enum {
	Not_Boolean_Datatype,
	Not_In_Value_Space,
	Valid,
}

// owl_rl_boolean_literal_status validates the four XML Schema boolean lexical
// representations: true, false, 1, and 0.
owl_rl_boolean_literal_status :: proc(literal: Term) -> OWL_RL_Boolean_Status {
	if literal.kind != .Literal || literal.datatype != "http://www.w3.org/2001/XMLSchema#boolean" do return .Not_Boolean_Datatype
	switch literal.value {
	case "true", "false", "1", "0": return .Valid
	}
	return .Not_In_Value_Space
}

// owl_rl_boolean_literals_have_same_value compares valid xsd:boolean values.
// The first result is false unless both inputs are valid boolean literals.
owl_rl_boolean_literals_have_same_value :: proc(left, right: Term) -> (compared, same: bool) {
	if owl_rl_boolean_literal_status(left) != .Valid || owl_rl_boolean_literal_status(right) != .Valid do return false, false
	return true, boolean_value(left.value) == boolean_value(right.value)
}

@(private) boolean_value :: proc(lexical: string) -> bool {
	return lexical == "true" || lexical == "1"
}
