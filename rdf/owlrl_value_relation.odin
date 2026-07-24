package rdf

// OWL_RL_Literal_Value_Relation is the exact data-value relation currently
// known for two RDF literals. Unknown deliberately prevents an OWL RL caller
// from deriving equality or inequality for a datatype pair without a complete
// lexical-to-value model.
OWL_RL_Literal_Value_Relation :: enum {
	Unknown,
	Same,
	Different,
}

// owl_rl_literal_value_relation compares the data values denoted by two
// literals. It covers the datatype families whose exact value mappings are
// already implemented: decimal/integer, float/double, string descendants and
// RDF 1.1 language literals, boolean, binary, and anyURI. It is intentionally
// silent for XMLLiteral and temporal values until their identity semantics are
// complete; temporal equality alone is insufficient for OWL RL dt-eq.
owl_rl_literal_value_relation :: proc(left, right: Term) -> OWL_RL_Literal_Value_Relation {
	if left.kind != .Literal || right.kind != .Literal do return .Unknown

	if compared, same := owl_rl_numeric_literals_have_same_value(left, right); compared do return .Same if same else .Different
	// XSD's equality relation deliberately makes NaN unequal to itself, whereas
	// OWL RL's dt-eq/dt-diff are phrased in terms of *data-value identity*.
	// Do not substitute one notion for the other until this datatype-map edge is
	// represented explicitly.
	if literal_is_floating_nan(left) || literal_is_floating_nan(right) do return .Unknown
	if compared, same := owl_rl_floating_literals_have_same_value(left, right); compared do return .Same if same else .Different
	if compared, same := string_like_literals_have_same_value(left, right); compared do return .Same if same else .Different
	if compared, same := rdf_language_literals_have_same_value(left, right); compared do return .Same if same else .Different
	if compared, same := owl_rl_boolean_literals_have_same_value(left, right); compared do return .Same if same else .Different
	if compared, same := owl_rl_binary_literals_have_same_value(left, right); compared do return .Same if same else .Different
	if compared, same := owl_rl_any_uri_literals_have_same_value(left, right); compared do return .Same if same else .Different
	return .Unknown
}

@(private) literal_is_floating_nan :: proc(literal: Term) -> bool {
	return literal.value == "NaN" && (literal.datatype == "http://www.w3.org/2001/XMLSchema#float" || literal.datatype == "http://www.w3.org/2001/XMLSchema#double")
}

@(private) string_like_literals_have_same_value :: proc(left, right: Term) -> (compared, same: bool) {
	left_mode, left_valid := string_like_literal_value_mode(left)
	right_mode, right_valid := string_like_literal_value_mode(right)
	if !left_valid || !right_valid do return false, false
	left_iterator := String_Value_Iterator{value = left.value, mode = left_mode}
	right_iterator := String_Value_Iterator{value = right.value, mode = right_mode}
	for {
		left_byte, left_more := next_string_value_byte(&left_iterator)
		right_byte, right_more := next_string_value_byte(&right_iterator)
		if left_more != right_more do return true, false
		if !left_more do return true, true
		if left_byte != right_byte do return true, false
	}
}

@(private) rdf_language_literals_have_same_value :: proc(left, right: Term) -> (compared, same: bool) {
	left_language := left.datatype == RDF_LANG_STRING
	right_language := right.datatype == RDF_LANG_STRING
	if !left_language && !right_language do return false, false
	if left_language && owl_rl_plain_literal_status(left) != .Valid do return false, false
	if right_language && owl_rl_plain_literal_status(right) != .Valid do return false, false

	// A language-tagged plain literal is a pair (string, lower-cased language),
	// whereas every string-derived datatype denotes a bare string.
	if left_language != right_language {
		if (left_language && string_like_literal_is_valid(right)) || (right_language && string_like_literal_is_valid(left)) do return true, false
		return false, false
	}
	return true, left.value == right.value && language_tags_equal_case_insensitively(left.language, right.language)
}

@(private) string_like_literal_is_valid :: proc(literal: Term) -> bool {
	_, valid := string_like_literal_value_mode(literal)
	return valid
}

@(private) language_tags_equal_case_insensitively :: proc(left, right: string) -> bool {
	if len(left) != len(right) do return false
	for index := 0; index < len(left); index += 1 {
		if ascii_lower(left[index]) != ascii_lower(right[index]) do return false
	}
	return true
}

@(private) ascii_lower :: proc(value: u8) -> u8 {
	if value >= 'A' && value <= 'Z' do return value + ('a' - 'A')
	return value
}
