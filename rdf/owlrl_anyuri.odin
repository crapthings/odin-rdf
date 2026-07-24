package rdf

// OWL_RL_AnyURI_Status describes xsd:anyURI lexical-space validation.
OWL_RL_AnyURI_Status :: enum {
	Not_AnyURI_Datatype,
	Not_In_Value_Space,
	Valid,
}

// owl_rl_any_uri_literal_status validates xsd:anyURI. XML Schema 1.1 permits
// both absolute and relative IRI references and defines its lexical space as
// all XML character sequences; it must not be restricted to RDF IRI terms.
owl_rl_any_uri_literal_status :: proc(literal: Term) -> OWL_RL_AnyURI_Status {
	if literal.kind != .Literal || literal.datatype != "http://www.w3.org/2001/XMLSchema#anyURI" do return .Not_AnyURI_Datatype
	if !is_xml_character_string(literal.value) do return .Not_In_Value_Space
	return .Valid
}

// owl_rl_any_uri_literals_have_same_value compares xsd:anyURI values after
// their fixed XML Schema whiteSpace=collapse normalization. Relative values
// remain relative and are never resolved against a document base.
owl_rl_any_uri_literals_have_same_value :: proc(left, right: Term) -> (compared, same: bool) {
	if owl_rl_any_uri_literal_status(left) != .Valid || owl_rl_any_uri_literal_status(right) != .Valid do return false, false
	left_iterator := String_Value_Iterator{value = left.value, mode = .Collapse}
	right_iterator := String_Value_Iterator{value = right.value, mode = .Collapse}
	for {
		left_byte, left_more := next_string_value_byte(&left_iterator)
		right_byte, right_more := next_string_value_byte(&right_iterator)
		if left_more != right_more do return true, false
		if !left_more do return true, true
		if left_byte != right_byte do return true, false
	}
}
