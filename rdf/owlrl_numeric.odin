package rdf

// OWL_RL_Numeric_Status describes the result of inspecting a literal in the
// integer and decimal portion of the OWL 2 RL datatype registry.  It is kept
// separate from the full datatype dispatcher until every supported datatype
// family has an exact value-space implementation.
OWL_RL_Numeric_Status :: enum {
	Not_Numeric_Datatype,
	Not_In_Value_Space,
	Valid,
}

@(private) Numeric_Sign :: enum {
	Negative,
	Zero,
	Positive,
}

// owl_rl_numeric_literal_status validates the XML Schema lexical form and
// value-space bounds for xsd:decimal and the OWL 2 RL integer family. It does
// not accept exponent notation: that notation belongs to float and double,
// not xsd:decimal.
owl_rl_numeric_literal_status :: proc(literal: Term) -> OWL_RL_Numeric_Status {
	if literal.kind != .Literal do return .Not_Numeric_Datatype

	switch literal.datatype {
	case "http://www.w3.org/2001/XMLSchema#decimal":
		if decimal_parts(literal.value).valid do return .Valid
		return .Not_In_Value_Space
	case "http://www.w3.org/2001/XMLSchema#integer":
		if integer_parts(literal.value).valid do return .Valid
		return .Not_In_Value_Space
	case "http://www.w3.org/2001/XMLSchema#nonNegativeInteger":
		return integer_status_in_range(literal.value, .Zero, "", .Positive, "")
	case "http://www.w3.org/2001/XMLSchema#nonPositiveInteger":
		return integer_status_in_range(literal.value, .Negative, "", .Zero, "")
	case "http://www.w3.org/2001/XMLSchema#positiveInteger":
		return integer_status_in_range(literal.value, .Positive, "", .Positive, "")
	case "http://www.w3.org/2001/XMLSchema#negativeInteger":
		return integer_status_in_range(literal.value, .Negative, "", .Negative, "")
	case "http://www.w3.org/2001/XMLSchema#long":
		return integer_status_in_range(literal.value, .Negative, "9223372036854775808", .Positive, "9223372036854775807")
	case "http://www.w3.org/2001/XMLSchema#int":
		return integer_status_in_range(literal.value, .Negative, "2147483648", .Positive, "2147483647")
	case "http://www.w3.org/2001/XMLSchema#short":
		return integer_status_in_range(literal.value, .Negative, "32768", .Positive, "32767")
	case "http://www.w3.org/2001/XMLSchema#byte":
		return integer_status_in_range(literal.value, .Negative, "128", .Positive, "127")
	case "http://www.w3.org/2001/XMLSchema#unsignedLong":
		return integer_status_in_range(literal.value, .Zero, "", .Positive, "18446744073709551615")
	case "http://www.w3.org/2001/XMLSchema#unsignedInt":
		return integer_status_in_range(literal.value, .Zero, "", .Positive, "4294967295")
	case "http://www.w3.org/2001/XMLSchema#unsignedShort":
		return integer_status_in_range(literal.value, .Zero, "", .Positive, "65535")
	case "http://www.w3.org/2001/XMLSchema#unsignedByte":
		return integer_status_in_range(literal.value, .Zero, "", .Positive, "255")
	case:
		return .Not_Numeric_Datatype
	}
}

// owl_rl_numeric_literals_have_same_value compares valid values from the
// xsd:decimal and integer datatype family without narrowing arbitrary-size
// integers to a machine integer. The first result is false when either input
// lies outside this family or has an invalid lexical form.
owl_rl_numeric_literals_have_same_value :: proc(left, right: Term) -> (compared, same: bool) {
	if owl_rl_numeric_literal_status(left) != .Valid || owl_rl_numeric_literal_status(right) != .Valid do return false, false

	left_decimal := left.datatype == "http://www.w3.org/2001/XMLSchema#decimal"
	right_decimal := right.datatype == "http://www.w3.org/2001/XMLSchema#decimal"
	if !left_decimal && !right_decimal {
		left_integer := integer_parts(left.value)
		right_integer := integer_parts(right.value)
		return true, left_integer.sign == right_integer.sign && left_integer.digits == right_integer.digits
	}

	left_value := decimal_value_parts(left.value, left_decimal)
	right_value := decimal_value_parts(right.value, right_decimal)
	return true, left_value.sign == right_value.sign && left_value.integral == right_value.integral && left_value.fraction == right_value.fraction
}

@(private) Integer_Parts :: struct {
	valid:  bool,
	sign:   Numeric_Sign,
	digits: string,
}

@(private) Decimal_Parts :: struct {
	valid:    bool,
	sign:     Numeric_Sign,
	integral: string,
	fraction: string,
}

@(private) integer_parts :: proc(value: string) -> Integer_Parts {
	if len(value) == 0 do return {}
	index := 0
	sign := Numeric_Sign.Positive
	if value[0] == '+' || value[0] == '-' {
		if value[0] == '-' do sign = .Negative
		index = 1
	}
	if index == len(value) do return {}
	for character in value[index:] {
		if character < '0' || character > '9' do return {}
	}
	digits := trim_leading_zeroes(value[index:])
	if len(digits) == 0 do return Integer_Parts{valid = true, sign = .Zero, digits = "0"}
	return Integer_Parts{valid = true, sign = sign, digits = digits}
}

@(private) decimal_parts :: proc(value: string) -> Decimal_Parts {
	if len(value) == 0 do return {}
	index := 0
	sign := Numeric_Sign.Positive
	if value[0] == '+' || value[0] == '-' {
		if value[0] == '-' do sign = .Negative
		index = 1
	}
	if index == len(value) do return {}

	dot_index := -1
	digit_count := 0
	for character, character_index in value[index:] {
		if character >= '0' && character <= '9' {
			digit_count += 1
			continue
		}
		if character == '.' && dot_index < 0 {
			dot_index = index + character_index
			continue
		}
		return {}
	}
	if digit_count == 0 do return {}

	integral := value[index:]
	fraction := ""
	if dot_index >= 0 {
		integral = value[index:dot_index]
		fraction = value[dot_index+1:]
	}
	integral = trim_leading_zeroes(integral)
	fraction = trim_trailing_zeroes(fraction)
	if len(integral) == 0 do integral = "0"
	if integral == "0" && len(fraction) == 0 do sign = .Zero
	return Decimal_Parts{valid = true, sign = sign, integral = integral, fraction = fraction}
}

@(private) decimal_value_parts :: proc(value: string, is_decimal: bool) -> Decimal_Parts {
	if is_decimal do return decimal_parts(value)
	integer := integer_parts(value)
	return Decimal_Parts{valid = integer.valid, sign = integer.sign, integral = integer.digits}
}

@(private) integer_status_in_range :: proc(value: string, minimum_sign: Numeric_Sign, minimum_digits: string, maximum_sign: Numeric_Sign, maximum_digits: string) -> OWL_RL_Numeric_Status {
	parts := integer_parts(value)
	if !parts.valid do return .Not_In_Value_Space
	if !integer_at_least(parts, minimum_sign, minimum_digits) || !integer_at_most(parts, maximum_sign, maximum_digits) do return .Not_In_Value_Space
	return .Valid
}

@(private) integer_at_least :: proc(parts: Integer_Parts, sign: Numeric_Sign, digits: string) -> bool {
	if sign == .Negative && len(digits) == 0 do return true
	if parts.sign != sign do return parts.sign > sign
	if len(digits) == 0 do return true
	return compare_unsigned_digits(parts.digits, digits) >= 0
}

@(private) integer_at_most :: proc(parts: Integer_Parts, sign: Numeric_Sign, digits: string) -> bool {
	if sign == .Positive && len(digits) == 0 do return true
	if parts.sign != sign do return parts.sign < sign
	if len(digits) == 0 do return true
	if sign == .Negative do return compare_unsigned_digits(parts.digits, digits) >= 0
	return compare_unsigned_digits(parts.digits, digits) <= 0
}

@(private) compare_unsigned_digits :: proc(left, right: string) -> int {
	if len(left) < len(right) do return -1
	if len(left) > len(right) do return 1
	for character, character_index in left {
		if character < rune(right[character_index]) do return -1
		if character > rune(right[character_index]) do return 1
	}
	return 0
}

@(private) trim_leading_zeroes :: proc(value: string) -> string {
	for character, index in value {
		if character != '0' do return value[index:]
	}
	return ""
}

@(private) trim_trailing_zeroes :: proc(value: string) -> string {
	for index := len(value)-1; index >= 0; index -= 1 {
		if value[index] != '0' do return value[:index+1]
	}
	return ""
}
