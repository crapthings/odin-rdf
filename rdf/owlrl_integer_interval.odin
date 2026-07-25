package rdf

// owl_rl_integer_datatype_intersection_is_subset_of reports whether the
// nonempty intersection of two modeled XML Schema integer datatype value
// spaces is wholly contained in target_datatype. It deliberately excludes
// decimal, float, double, and every datatype family without an exact discrete
// integer interval model.
owl_rl_integer_datatype_intersection_is_subset_of :: proc(left_datatype, right_datatype, target_datatype: string) -> bool {
	left, left_ok := owl_rl_integer_datatype_interval(left_datatype)
	right, right_ok := owl_rl_integer_datatype_interval(right_datatype)
	target, target_ok := owl_rl_integer_datatype_interval(target_datatype)
	if !left_ok || !right_ok || !target_ok do return false
	intersection, nonempty := owl_rl_integer_interval_intersection(left, right)
	if !nonempty do return false
	return owl_rl_integer_interval_is_subset_of(intersection, target)
}

@(private) Integer_Interval_Bound :: struct {
	sign:   Numeric_Sign,
	digits: string,
}

@(private) Integer_Datatype_Interval :: struct {
	has_lower: bool,
	lower:     Integer_Interval_Bound,
	has_upper: bool,
	upper:     Integer_Interval_Bound,
}

@(private) owl_rl_integer_datatype_interval :: proc(datatype: string) -> (Integer_Datatype_Interval, bool) {
	switch datatype {
	case "http://www.w3.org/2001/XMLSchema#integer":
		return {}, true
	case "http://www.w3.org/2001/XMLSchema#nonNegativeInteger":
		return {has_lower = true, lower = {.Zero, "0"}}, true
	case "http://www.w3.org/2001/XMLSchema#nonPositiveInteger":
		return {has_upper = true, upper = {.Zero, "0"}}, true
	case "http://www.w3.org/2001/XMLSchema#positiveInteger":
		return {has_lower = true, lower = {.Positive, "1"}}, true
	case "http://www.w3.org/2001/XMLSchema#negativeInteger":
		return {has_upper = true, upper = {.Negative, "1"}}, true
	case "http://www.w3.org/2001/XMLSchema#long":
		return {has_lower = true, lower = {.Negative, "9223372036854775808"}, has_upper = true, upper = {.Positive, "9223372036854775807"}}, true
	case "http://www.w3.org/2001/XMLSchema#int":
		return {has_lower = true, lower = {.Negative, "2147483648"}, has_upper = true, upper = {.Positive, "2147483647"}}, true
	case "http://www.w3.org/2001/XMLSchema#short":
		return {has_lower = true, lower = {.Negative, "32768"}, has_upper = true, upper = {.Positive, "32767"}}, true
	case "http://www.w3.org/2001/XMLSchema#byte":
		return {has_lower = true, lower = {.Negative, "128"}, has_upper = true, upper = {.Positive, "127"}}, true
	case "http://www.w3.org/2001/XMLSchema#unsignedLong":
		return {has_lower = true, lower = {.Zero, "0"}, has_upper = true, upper = {.Positive, "18446744073709551615"}}, true
	case "http://www.w3.org/2001/XMLSchema#unsignedInt":
		return {has_lower = true, lower = {.Zero, "0"}, has_upper = true, upper = {.Positive, "4294967295"}}, true
	case "http://www.w3.org/2001/XMLSchema#unsignedShort":
		return {has_lower = true, lower = {.Zero, "0"}, has_upper = true, upper = {.Positive, "65535"}}, true
	case "http://www.w3.org/2001/XMLSchema#unsignedByte":
		return {has_lower = true, lower = {.Zero, "0"}, has_upper = true, upper = {.Positive, "255"}}, true
	}
	return {}, false
}

@(private) owl_rl_integer_interval_intersection :: proc(left, right: Integer_Datatype_Interval) -> (Integer_Datatype_Interval, bool) {
	result := left
	if !result.has_lower || (right.has_lower && owl_rl_integer_bound_compare(right.lower, result.lower) > 0) {
		result.has_lower = right.has_lower
		result.lower = right.lower
	}
	if !result.has_upper || (right.has_upper && owl_rl_integer_bound_compare(right.upper, result.upper) < 0) {
		result.has_upper = right.has_upper
		result.upper = right.upper
	}
	if result.has_lower && result.has_upper && owl_rl_integer_bound_compare(result.lower, result.upper) > 0 do return {}, false
	return result, true
}

@(private) owl_rl_integer_interval_is_subset_of :: proc(left, right: Integer_Datatype_Interval) -> bool {
	if right.has_lower && (!left.has_lower || owl_rl_integer_bound_compare(left.lower, right.lower) < 0) do return false
	if right.has_upper && (!left.has_upper || owl_rl_integer_bound_compare(left.upper, right.upper) > 0) do return false
	return true
}

@(private) owl_rl_integer_bound_compare :: proc(left, right: Integer_Interval_Bound) -> int {
	if left.sign < right.sign do return -1
	if left.sign > right.sign do return 1
	comparison := compare_unsigned_digits(left.digits, right.digits)
	if left.sign == .Negative do return -comparison
	return comparison
}
