package rdf

// OWL_RL_Value_Space_Membership reports whether the value denoted by a literal
// belongs to a requested OWL 2 RL datatype. Unknown is intentional: callers
// must not infer a result until that datatype family has exact support.
OWL_RL_Value_Space_Membership :: enum {
	Unknown,
	No,
	Yes,
}

// owl_rl_literal_value_membership determines membership in the target
// datatype value space. This initial dispatcher covers the complete exact
// decimal/integer family, including cross-datatype cases such as
// "1.00"^^xsd:decimal belonging to xsd:integer.
owl_rl_literal_value_membership :: proc(literal: Term, target_datatype: string) -> OWL_RL_Value_Space_Membership {
	if is_owl_rl_numeric_datatype(target_datatype) do return numeric_value_membership(literal, target_datatype)
	if is_owl_rl_string_datatype(target_datatype) do return string_value_membership(literal, target_datatype)
	if target_datatype == "http://www.w3.org/2001/XMLSchema#anyURI" do return any_uri_value_membership(literal)
	if target_datatype == "http://www.w3.org/2001/XMLSchema#boolean" do return boolean_value_membership(literal)
	if target_datatype == "http://www.w3.org/2001/XMLSchema#hexBinary" || target_datatype == "http://www.w3.org/2001/XMLSchema#base64Binary" do return binary_value_membership(literal)
	if target_datatype == "http://www.w3.org/2000/01/rdf-schema#Literal" {
		if literal.kind != .Literal do return .No
		if validate_term_structure(literal) == .None do return .Yes
		return .No
	}
	return .Unknown
}

@(private) numeric_value_membership :: proc(literal: Term, target_datatype: string) -> OWL_RL_Value_Space_Membership {
	status := owl_rl_numeric_literal_status(literal)
	if status == .Not_Numeric_Datatype do return .Unknown
	if status == .Not_In_Value_Space do return .No
	if target_datatype == "http://www.w3.org/2001/XMLSchema#decimal" do return .Yes
	integer, is_integer := numeric_integer_value(literal)
	if !is_integer do return .No
	if integer_value_in_numeric_target(integer, target_datatype) do return .Yes
	return .No
}

@(private) is_owl_rl_string_datatype :: proc(datatype: string) -> bool {
	return datatype == "http://www.w3.org/2001/XMLSchema#string" ||
		datatype == "http://www.w3.org/2001/XMLSchema#normalizedString" ||
		datatype == "http://www.w3.org/2001/XMLSchema#token"
}

@(private) string_value_membership :: proc(literal: Term, target_datatype: string) -> OWL_RL_Value_Space_Membership {
	status := owl_rl_string_literal_status(literal)
	if status == .Not_String_Datatype do return .Unknown
	if status == .Not_In_Value_Space do return .No
	if target_datatype == "http://www.w3.org/2001/XMLSchema#string" do return .Yes

	mode := string_value_mode(literal.datatype)
	if target_datatype == "http://www.w3.org/2001/XMLSchema#normalizedString" {
		if string_value_has_replaced_whitespace(literal.value, mode) do return .No
		return .Yes
	}
	if string_value_is_token(literal.value, mode) do return .Yes
	return .No
}

@(private) string_value_has_replaced_whitespace :: proc(value: string, mode: String_Value_Mode) -> bool {
	if mode != .Raw do return false
	for character in value {
		if character == '\t' || character == '\n' || character == '\r' do return true
	}
	return false
}

@(private) string_value_is_token :: proc(value: string, mode: String_Value_Mode) -> bool {
	iterator := String_Value_Iterator{value = value, mode = mode}
	previous_space := false
	first := true
	last_space := false
	for {
		character, more := next_string_value_byte(&iterator)
		if !more do break
		if first && character == ' ' do return false
		first = false
		if character == ' ' && previous_space do return false
		previous_space = character == ' '
		last_space = character == ' '
	}
	return !last_space
}

@(private) any_uri_value_membership :: proc(literal: Term) -> OWL_RL_Value_Space_Membership {
	status := owl_rl_any_uri_literal_status(literal)
	if status == .Not_AnyURI_Datatype do return .Unknown
	if status == .Not_In_Value_Space do return .No
	return .Yes
}

@(private) boolean_value_membership :: proc(literal: Term) -> OWL_RL_Value_Space_Membership {
	status := owl_rl_boolean_literal_status(literal)
	if status == .Not_Boolean_Datatype do return .Unknown
	if status == .Not_In_Value_Space do return .No
	return .Yes
}

@(private) binary_value_membership :: proc(literal: Term) -> OWL_RL_Value_Space_Membership {
	status := owl_rl_binary_literal_status(literal)
	if status == .Not_Binary_Datatype do return .Unknown
	if status == .Not_In_Value_Space do return .No
	return .Yes
}

@(private) is_owl_rl_numeric_datatype :: proc(datatype: string) -> bool {
	switch datatype {
	case "http://www.w3.org/2001/XMLSchema#decimal",
		"http://www.w3.org/2001/XMLSchema#integer",
		"http://www.w3.org/2001/XMLSchema#nonNegativeInteger",
		"http://www.w3.org/2001/XMLSchema#nonPositiveInteger",
		"http://www.w3.org/2001/XMLSchema#positiveInteger",
		"http://www.w3.org/2001/XMLSchema#negativeInteger",
		"http://www.w3.org/2001/XMLSchema#long",
		"http://www.w3.org/2001/XMLSchema#int",
		"http://www.w3.org/2001/XMLSchema#short",
		"http://www.w3.org/2001/XMLSchema#byte",
		"http://www.w3.org/2001/XMLSchema#unsignedLong",
		"http://www.w3.org/2001/XMLSchema#unsignedInt",
		"http://www.w3.org/2001/XMLSchema#unsignedShort",
		"http://www.w3.org/2001/XMLSchema#unsignedByte":
		return true
	}
	return false
}

@(private) numeric_integer_value :: proc(literal: Term) -> (Integer_Parts, bool) {
	if literal.datatype != "http://www.w3.org/2001/XMLSchema#decimal" do return integer_parts(literal.value), true
	decimal := decimal_parts(literal.value)
	if len(decimal.fraction) > 0 do return {}, false
	return Integer_Parts{valid = decimal.valid, sign = decimal.sign, digits = decimal.integral}, true
}

@(private) integer_value_in_numeric_target :: proc(value: Integer_Parts, target_datatype: string) -> bool {
	switch target_datatype {
	case "http://www.w3.org/2001/XMLSchema#integer":
		return true
	case "http://www.w3.org/2001/XMLSchema#nonNegativeInteger":
		return integer_in_range(value, .Zero, "", .Positive, "")
	case "http://www.w3.org/2001/XMLSchema#nonPositiveInteger":
		return integer_in_range(value, .Negative, "", .Zero, "")
	case "http://www.w3.org/2001/XMLSchema#positiveInteger":
		return integer_in_range(value, .Positive, "", .Positive, "")
	case "http://www.w3.org/2001/XMLSchema#negativeInteger":
		return integer_in_range(value, .Negative, "", .Negative, "")
	case "http://www.w3.org/2001/XMLSchema#long":
		return integer_in_range(value, .Negative, "9223372036854775808", .Positive, "9223372036854775807")
	case "http://www.w3.org/2001/XMLSchema#int":
		return integer_in_range(value, .Negative, "2147483648", .Positive, "2147483647")
	case "http://www.w3.org/2001/XMLSchema#short":
		return integer_in_range(value, .Negative, "32768", .Positive, "32767")
	case "http://www.w3.org/2001/XMLSchema#byte":
		return integer_in_range(value, .Negative, "128", .Positive, "127")
	case "http://www.w3.org/2001/XMLSchema#unsignedLong":
		return integer_in_range(value, .Zero, "", .Positive, "18446744073709551615")
	case "http://www.w3.org/2001/XMLSchema#unsignedInt":
		return integer_in_range(value, .Zero, "", .Positive, "4294967295")
	case "http://www.w3.org/2001/XMLSchema#unsignedShort":
		return integer_in_range(value, .Zero, "", .Positive, "65535")
	case "http://www.w3.org/2001/XMLSchema#unsignedByte":
		return integer_in_range(value, .Zero, "", .Positive, "255")
	}
	return false
}

@(private) integer_in_range :: proc(parts: Integer_Parts, minimum_sign: Numeric_Sign, minimum_digits: string, maximum_sign: Numeric_Sign, maximum_digits: string) -> bool {
	return integer_at_least(parts, minimum_sign, minimum_digits) && integer_at_most(parts, maximum_sign, maximum_digits)
}
