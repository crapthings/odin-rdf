package rdf

import "core:unicode/utf8"

// OWL_RL_String_Status describes validation for the string datatypes whose
// value mapping differs only by XML Schema's whiteSpace facet. XML name and
// language datatypes are deliberately handled by a separate validator because
// they add XML/BCP47 pattern constraints beyond this common value mapping.
OWL_RL_String_Status :: enum {
	Not_String_Datatype,
	Not_In_Value_Space,
	Valid,
}

@(private) String_Value_Mode :: enum {
	None,
	Raw,
	Replace,
	Collapse,
}

// owl_rl_string_literal_status validates xsd:string, xsd:normalizedString,
// and xsd:token. All three require a sequence of XML characters; their
// different whiteSpace facets alter the mapped value, not its validity.
owl_rl_string_literal_status :: proc(literal: Term) -> OWL_RL_String_Status {
	if literal.kind != .Literal do return .Not_String_Datatype
	if string_value_mode(literal.datatype) == .None do return .Not_String_Datatype
	if !is_xml_character_string(literal.value) do return .Not_In_Value_Space
	return .Valid
}

// owl_rl_string_literals_have_same_value compares mapped string values across
// xsd:string, xsd:normalizedString, and xsd:token. Thus, for example, a
// normalizedString containing a tab can equal a string containing a space.
owl_rl_string_literals_have_same_value :: proc(left, right: Term) -> (compared, same: bool) {
	if owl_rl_string_literal_status(left) != .Valid || owl_rl_string_literal_status(right) != .Valid do return false, false
	left_mode := string_value_mode(left.datatype)
	right_mode := string_value_mode(right.datatype)
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

@(private) string_value_mode :: proc(datatype: string) -> String_Value_Mode {
	switch datatype {
	case "http://www.w3.org/2001/XMLSchema#string":
		return .Raw
	case "http://www.w3.org/2001/XMLSchema#normalizedString":
		return .Replace
	case "http://www.w3.org/2001/XMLSchema#token":
		return .Collapse
	case:
		return .None
	}
}

@(private) is_xml_character_string :: proc(value: string) -> bool {
	if !utf8.valid_string(value) do return false
	for index := 0; index < len(value); {
		character, width := utf8.decode_rune_in_string(value[index:])
		if !is_xml_character(character) do return false
		index += width
	}
	return true
}

@(private) is_xml_character :: proc(character: rune) -> bool {
	return character == '\t' || character == '\n' || character == '\r' ||
		(character >= 0x20 && character <= 0xd7ff) ||
		(character >= 0xe000 && character <= 0xfffd) ||
		(character >= 0x10000 && character <= 0x10ffff)
}

@(private) String_Value_Iterator :: struct {
	value:            string,
	mode:             String_Value_Mode,
	index:            int,
	started:          bool,
	pending_space:    bool,
	has_deferred:     bool,
	deferred:         u8,
}

@(private) next_string_value_byte :: proc(iterator: ^String_Value_Iterator) -> (byte: u8, more: bool) {
	if iterator.has_deferred {
		iterator.has_deferred = false
		return iterator.deferred, true
	}
	for iterator.index < len(iterator.value) {
		byte = iterator.value[iterator.index]
		iterator.index += 1
		if iterator.mode == .Raw do return byte, true
		if byte == '\t' || byte == '\n' || byte == '\r' do byte = ' '
		if iterator.mode == .Replace do return byte, true
		if byte == ' ' {
			if iterator.started do iterator.pending_space = true
			continue
		}
		if iterator.pending_space {
			iterator.pending_space = false
			iterator.deferred = byte
			iterator.has_deferred = true
			return ' ', true
		}
		iterator.started = true
		return byte, true
	}
	return 0, false
}
