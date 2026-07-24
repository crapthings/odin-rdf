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
	if !is_owl_rl_numeric_datatype(target_datatype) do return .Unknown
	status := owl_rl_numeric_literal_status(literal)
	if status == .Not_Numeric_Datatype do return .Unknown
	if status == .Not_In_Value_Space do return .No

	if target_datatype == "http://www.w3.org/2001/XMLSchema#decimal" do return .Yes
	integer, is_integer := numeric_integer_value(literal)
	if !is_integer do return .No
	if integer_value_in_numeric_target(integer, target_datatype) do return .Yes
	return .No
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
