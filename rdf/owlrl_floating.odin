package rdf

import "core:strconv"
import "core:math"

// OWL_RL_Floating_Status describes xsd:float and xsd:double lexical-space
// validation. It follows XML Schema's decimal/scientific grammar and its
// exact INF, +INF, -INF, and NaN special representations.
OWL_RL_Floating_Status :: enum {
	Not_Floating_Datatype,
	Not_In_Value_Space,
	Valid,
}

// owl_rl_floating_literal_status validates xsd:float and xsd:double lexical
// forms. A numerically overflowing decimal remains valid: XML Schema maps it
// to the corresponding IEEE infinity.
owl_rl_floating_literal_status :: proc(literal: Term) -> OWL_RL_Floating_Status {
	if literal.kind != .Literal do return .Not_Floating_Datatype
	if literal.datatype != "http://www.w3.org/2001/XMLSchema#float" && literal.datatype != "http://www.w3.org/2001/XMLSchema#double" do return .Not_Floating_Datatype
	if is_xsd_floating_lexical(literal.value) do return .Valid
	return .Not_In_Value_Space
}

// owl_rl_floating_literals_have_same_value compares values within and across
// the IEEE float/double datatypes. A float value is also a double value when
// its widened IEEE representation equals the double value. NaN is deliberately
// unequal to itself, while +0 and -0 compare equal, per XML Schema 1.1.
owl_rl_floating_literals_have_same_value :: proc(left, right: Term) -> (compared, same: bool) {
	if owl_rl_floating_literal_status(left) != .Valid || owl_rl_floating_literal_status(right) != .Valid do return false, false
	if left.value == "NaN" || right.value == "NaN" do return true, false
	if left.datatype == "http://www.w3.org/2001/XMLSchema#float" && right.datatype == "http://www.w3.org/2001/XMLSchema#float" {
		left_value, left_ok := parse_xsd_f32(left.value)
		right_value, right_ok := parse_xsd_f32(right.value)
		return left_ok && right_ok, left_value == right_value
	}
	if left.datatype == "http://www.w3.org/2001/XMLSchema#double" && right.datatype == "http://www.w3.org/2001/XMLSchema#double" {
		left_value, left_ok := parse_xsd_f64(left.value)
		right_value, right_ok := parse_xsd_f64(right.value)
		return left_ok && right_ok, left_value == right_value
	}
	if left.datatype == "http://www.w3.org/2001/XMLSchema#float" {
		left_value, left_ok := parse_xsd_f32(left.value)
		right_value, right_ok := parse_xsd_f64(right.value)
		return left_ok && right_ok, f64(left_value) == right_value
	}
	left_value, left_ok := parse_xsd_f64(left.value)
	right_value, right_ok := parse_xsd_f32(right.value)
	return left_ok && right_ok, left_value == f64(right_value)
}

@(private) is_xsd_floating_lexical :: proc(value: string) -> bool {
	switch value {
	case "INF", "+INF", "-INF", "NaN": return true
	}
	if len(value) == 0 do return false
	index := 0
	if value[0] == '+' || value[0] == '-' do index = 1
	if index == len(value) do return false

	digits := 0
	dot_seen := false
	for index < len(value) {
		character := value[index]
		if character >= '0' && character <= '9' {
			digits += 1
			index += 1
			continue
		}
		if character == '.' && !dot_seen {
			dot_seen = true
			index += 1
			continue
		}
		break
	}
	if digits == 0 do return false
	if index == len(value) do return true
	if value[index] != 'e' && value[index] != 'E' do return false
	index += 1
	if index < len(value) && (value[index] == '+' || value[index] == '-') do index += 1
	exponent_digits := 0
	for index < len(value) {
		if value[index] < '0' || value[index] > '9' do return false
		exponent_digits += 1
		index += 1
	}
	return exponent_digits > 0
}

@(private) parse_xsd_f32 :: proc(value: string) -> (f32, bool) {
	switch value {
	case "INF", "+INF": return strconv.parse_f32("inf")
	case "-INF":         return strconv.parse_f32("-inf")
	}
	parsed, ok := strconv.parse_f32(value)
	if ok do return parsed, true
	return floating_out_of_range_f32(value), true
}

@(private) parse_xsd_f64 :: proc(value: string) -> (f64, bool) {
	switch value {
	case "INF", "+INF": return strconv.parse_f64("inf")
	case "-INF":         return strconv.parse_f64("-inf")
	}
	parsed, ok := strconv.parse_f64(value)
	if ok do return parsed, true
	return floating_out_of_range_f64(value), true
}

@(private) floating_out_of_range_f32 :: proc(value: string) -> f32 {
	if floating_mantissa_is_zero(value) || floating_has_negative_exponent(value) do return f32(0)
	return math.inf_f32(-1 if value[0] == '-' else 1)
}

@(private) floating_out_of_range_f64 :: proc(value: string) -> f64 {
	if floating_mantissa_is_zero(value) || floating_has_negative_exponent(value) do return 0
	return math.inf_f64(-1 if value[0] == '-' else 1)
}

@(private) floating_mantissa_is_zero :: proc(value: string) -> bool {
	for character in value {
		if character == 'e' || character == 'E' do break
		if character >= '1' && character <= '9' do return false
	}
	return true
}

@(private) floating_has_negative_exponent :: proc(value: string) -> bool {
	for index := 0; index < len(value); index += 1 {
		if (value[index] == 'e' || value[index] == 'E') && index + 1 < len(value) do return value[index+1] == '-'
	}
	return false
}
