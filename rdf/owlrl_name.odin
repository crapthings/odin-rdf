package rdf

import "core:unicode/utf8"

// OWL_RL_Pattern_Status describes the OWL 2 RL string datatypes with a
// pattern facet in addition to whiteSpace=collapse.
OWL_RL_Pattern_Status :: enum {
	Not_Pattern_Datatype,
	Not_In_Value_Space,
	Valid,
}

// owl_rl_pattern_literal_status validates xsd:language, xsd:Name,
// xsd:NCName, and xsd:NMTOKEN. These datatypes inherit whiteSpace=collapse;
// validation is therefore performed on the one non-whitespace token left by
// that facet.
owl_rl_pattern_literal_status :: proc(literal: Term) -> OWL_RL_Pattern_Status {
	if literal.kind != .Literal do return .Not_Pattern_Datatype
	if !is_xml_character_string(literal.value) do return .Not_In_Value_Space
	start, end, one_token := collapsed_single_token(literal.value)
	if !one_token do return .Not_In_Value_Space
	value := literal.value[start:end]
	switch literal.datatype {
	case "http://www.w3.org/2001/XMLSchema#language":
		if is_xsd_language(value) do return .Valid
	case "http://www.w3.org/2001/XMLSchema#Name":
		if is_xml_name(value) do return .Valid
	case "http://www.w3.org/2001/XMLSchema#NCName":
		if is_xml_ncname(value) do return .Valid
	case "http://www.w3.org/2001/XMLSchema#NMTOKEN":
		if is_xml_nmtoken(value) do return .Valid
	case:
		return .Not_Pattern_Datatype
	}
	return .Not_In_Value_Space
}

@(private) collapsed_single_token :: proc(value: string) -> (start, end: int, valid: bool) {
	for start < len(value) && is_xml_schema_whitespace(value[start]) do start += 1
	if start == len(value) do return 0, 0, false
	end = start
	for end < len(value) && !is_xml_schema_whitespace(value[end]) do end += 1
	for trailing := end; trailing < len(value); trailing += 1 {
		if !is_xml_schema_whitespace(value[trailing]) do return 0, 0, false
	}
	return start, end, true
}

@(private) is_xsd_language :: proc(value: string) -> bool {
	if len(value) == 0 do return false
	part_start := 0
	part_index := 0
	for character, index in value {
		if character == '-' {
			if !valid_xsd_language_part(value[part_start:index], part_index == 0) do return false
			part_index += 1
			part_start = index + 1
		}
	}
	return valid_xsd_language_part(value[part_start:], part_index == 0)
}

@(private) valid_xsd_language_part :: proc(value: string, primary: bool) -> bool {
	if len(value) == 0 || len(value) > 8 do return false
	for character in value {
		if (character >= 'A' && character <= 'Z') || (character >= 'a' && character <= 'z') do continue
		if !primary && character >= '0' && character <= '9' do continue
		return false
	}
	return true
}

@(private) is_xml_name_start :: proc(character: rune, allow_colon: bool) -> bool {
	return (allow_colon && character == ':') || (character >= 'A' && character <= 'Z') || (character >= 'a' && character <= 'z') || character == '_' ||
		(character >= 0xc0 && character <= 0xd6) || (character >= 0xd8 && character <= 0xf6) ||
		(character >= 0xf8 && character <= 0x2ff) || (character >= 0x370 && character <= 0x37d) ||
		(character >= 0x37f && character <= 0x1fff) || (character >= 0x200c && character <= 0x200d) ||
		(character >= 0x2070 && character <= 0x218f) || (character >= 0x2c00 && character <= 0x2fef) ||
		(character >= 0x3001 && character <= 0xd7ff) || (character >= 0xf900 && character <= 0xfdcf) ||
		(character >= 0xfdf0 && character <= 0xfffd) || (character >= 0x10000 && character <= 0xeffff)
}

@(private) is_xml_name_character :: proc(character: rune, allow_colon: bool) -> bool {
	return is_xml_name_start(character, allow_colon) || (character >= '0' && character <= '9') || character == '-' || character == '.' ||
		character == 0xb7 || (character >= 0x300 && character <= 0x36f) || (character >= 0x203f && character <= 0x2040)
}

@(private) is_xml_name :: proc(value: string) -> bool {
	return is_xml_name_with_colon_mode(value, true)
}

@(private) is_xml_ncname :: proc(value: string) -> bool {
	return is_xml_name_with_colon_mode(value, false)
}

@(private) is_xml_name_with_colon_mode :: proc(value: string, allow_colon: bool) -> bool {
	if len(value) == 0 || !utf8.valid_string(value) do return false
	first, width := utf8.decode_rune_in_string(value)
	if !is_xml_name_start(first, allow_colon) do return false
	for index := width; index < len(value); {
		character, next_width := utf8.decode_rune_in_string(value[index:])
		if !is_xml_name_character(character, allow_colon) do return false
		index += next_width
	}
	return true
}

@(private) is_xml_nmtoken :: proc(value: string) -> bool {
	if len(value) == 0 || !utf8.valid_string(value) do return false
	for index := 0; index < len(value); {
		character, width := utf8.decode_rune_in_string(value[index:])
		if !is_xml_name_character(character, true) do return false
		index += width
	}
	return true
}
