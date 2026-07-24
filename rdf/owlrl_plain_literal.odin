package rdf

// OWL_RL_Plain_Literal_Status reports whether an RDF 1.1 literal denotes a
// value in the legacy rdf:PlainLiteral value space required by OWL 2 RL.
OWL_RL_Plain_Literal_Status :: enum {
	Not_Plain_Literal_Value,
	Not_In_Value_Space,
	Valid,
}

// owl_rl_plain_literal_status recognizes the RDF 1.1 representations of the
// rdf:PlainLiteral value space: xsd:string-derived string values and
// rdf:langString values. The latter retain their language tag as part of the
// value, while the former are plain string values. A typed rdf:PlainLiteral
// lexical form is deliberately not accepted: the OWL 2 datatype specification
// requires RDF graph syntaxes to use RDF plain/language literals instead.
owl_rl_plain_literal_status :: proc(literal: Term) -> OWL_RL_Plain_Literal_Status {
	if literal.kind != .Literal do return .Not_Plain_Literal_Value
	if validate_term_structure(literal) != .None || !is_xml_character_string(literal.value) do return .Not_In_Value_Space
	if (is_owl_rl_string_datatype(literal.datatype) || is_owl_rl_pattern_datatype(literal.datatype)) && len(literal.language) == 0 {
		_, valid := string_like_literal_value_mode(literal)
		if valid do return .Valid
		return .Not_In_Value_Space
	}
	if literal.datatype == RDF_LANG_STRING {
		if valid_rdf_language_tag(literal.language) do return .Valid
		return .Not_In_Value_Space
	}
	return .Not_Plain_Literal_Value
}

// valid_rdf_language_tag accepts the RDF 1.1 LANGTAG shape. Its lexical
// constraint is intentionally kept here, rather than borrowed from a syntax
// writer, because datatype entailment must be independent of serialization.
@(private) valid_rdf_language_tag :: proc(value: string) -> bool {
	if len(value) == 0 || !is_ascii_letter(value[0]) do return false
	previous_hyphen := false
	for index := 0; index < len(value); index += 1 {
		character := value[index]
		if character == '-' {
			if previous_hyphen do return false
			previous_hyphen = true
			continue
		}
		if !is_ascii_letter(character) && !is_ascii_digit(character) do return false
		previous_hyphen = false
	}
	return !previous_hyphen
}

@(private) is_ascii_letter :: proc(character: u8) -> bool {
	return (character >= 'A' && character <= 'Z') || (character >= 'a' && character <= 'z')
}
