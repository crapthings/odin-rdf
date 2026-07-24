package rdf

// OWL_RL_Binary_Status describes validation of the two OWL 2 RL binary
// datatypes. XML Schema's fixed whiteSpace=collapse facet is applied before
// inspecting either lexical form.
OWL_RL_Binary_Status :: enum {
	Not_Binary_Datatype,
	Not_In_Value_Space,
	Valid,
}

// owl_rl_binary_literal_status validates xsd:hexBinary and xsd:base64Binary.
// Empty binary values are valid values for both datatypes.
owl_rl_binary_literal_status :: proc(literal: Term) -> OWL_RL_Binary_Status {
	if literal.kind != .Literal do return .Not_Binary_Datatype
	switch literal.datatype {
	case "http://www.w3.org/2001/XMLSchema#hexBinary":
		if is_hex_binary_lexical(literal.value) do return .Valid
	case "http://www.w3.org/2001/XMLSchema#base64Binary":
		if is_base64_binary_lexical(literal.value) do return .Valid
	case:
		return .Not_Binary_Datatype
	}
	return .Not_In_Value_Space
}

// owl_rl_binary_literals_have_same_value compares the decoded octet sequences
// of valid xsd:hexBinary and xsd:base64Binary literals. The first result is
// false unless both inputs are valid binary datatype literals.
owl_rl_binary_literals_have_same_value :: proc(left, right: Term) -> (compared, same: bool) {
	if owl_rl_binary_literal_status(left) != .Valid || owl_rl_binary_literal_status(right) != .Valid do return false, false

	left_is_hex := left.datatype == "http://www.w3.org/2001/XMLSchema#hexBinary"
	right_is_hex := right.datatype == "http://www.w3.org/2001/XMLSchema#hexBinary"
	if left_is_hex && right_is_hex do return true, hex_binary_equal(left.value, right.value)
	if !left_is_hex && !right_is_hex do return true, base64_binary_equal(left.value, right.value)
	if left_is_hex do return true, hex_and_base64_binary_equal(left.value, right.value)
	return true, hex_and_base64_binary_equal(right.value, left.value)
}

@(private) is_xml_schema_whitespace :: proc(character: u8) -> bool {
	return character == ' ' || character == '\t' || character == '\n' || character == '\r'
}

@(private) hex_value :: proc(character: u8) -> (value: u8, valid: bool) {
	switch character {
	case '0'..='9': return character - '0', true
	case 'A'..='F': return character - 'A' + 10, true
	case 'a'..='f': return character - 'a' + 10, true
	}
	return 0, false
}

@(private) is_hex_binary_lexical :: proc(value: string) -> bool {
	digit_count := 0
	for character in value {
		byte_value := u8(character)
		if is_xml_schema_whitespace(byte_value) do continue
		if _, valid := hex_value(byte_value); !valid do return false
		digit_count += 1
	}
	return digit_count % 2 == 0
}

@(private) hex_binary_equal :: proc(left, right: string) -> bool {
	left_index, right_index := 0, 0
	for {
		left_nibble, left_more := next_hex_nibble(left, &left_index)
		right_nibble, right_more := next_hex_nibble(right, &right_index)
		if left_more != right_more do return false
		if !left_more do return true
		if left_nibble != right_nibble do return false
	}
}

@(private) next_hex_nibble :: proc(value: string, index: ^int) -> (nibble: u8, more: bool) {
	for index^ < len(value) {
		character := value[index^]
		index^ += 1
		if is_xml_schema_whitespace(character) do continue
		nibble, _ = hex_value(character)
		return nibble, true
	}
	return 0, false
}

@(private) base64_value :: proc(character: u8) -> (value: u8, valid: bool) {
	switch character {
	case 'A'..='Z': return character - 'A', true
	case 'a'..='z': return character - 'a' + 26, true
	case '0'..='9': return character - '0' + 52, true
	case '+':       return 62, true
	case '/':       return 63, true
	}
	return 0, false
}

@(private) is_base64_binary_lexical :: proc(value: string) -> bool {
	character_count, padding_count := 0, 0
	seen_padding := false
	for character in value {
		byte_value := u8(character)
		if is_xml_schema_whitespace(byte_value) do continue
		character_count += 1
		if byte_value == '=' {
			seen_padding = true
			padding_count += 1
			if padding_count > 2 do return false
			continue
		}
		if seen_padding do return false
		if _, valid := base64_value(byte_value); !valid do return false
	}
	if character_count == 0 do return true
	if character_count % 4 != 0 do return false
	if padding_count == 1 do return character_count >= 4
	if padding_count == 2 do return character_count >= 4
	return true
}

@(private) base64_binary_equal :: proc(left, right: string) -> bool {
	left_count := binary_non_whitespace_count(left)
	right_count := binary_non_whitespace_count(right)
	left_padding := base64_padding_count(left)
	right_padding := base64_padding_count(right)
	if left_count / 4 * 3 - left_padding != right_count / 4 * 3 - right_padding do return false

	left_index, right_index := 0, 0
	for group_index := 0; group_index < left_count / 4; group_index += 1 {
		left_group := next_base64_group(left, &left_index)
		right_group := next_base64_group(right, &right_index)
		left_bytes, left_byte_count := decode_base64_group(left_group)
		right_bytes, right_byte_count := decode_base64_group(right_group)
		if left_byte_count != right_byte_count do return false
		for byte_index := 0; byte_index < left_byte_count; byte_index += 1 {
			if left_bytes[byte_index] != right_bytes[byte_index] do return false
		}
	}
	return true
}

@(private) Base64_Byte_Iterator :: struct {
	value:       string,
	input_index: int,
	bytes:       [3]u8,
	byte_index:  int,
	byte_count:  int,
}

@(private) hex_and_base64_binary_equal :: proc(hex, base64: string) -> bool {
	if binary_non_whitespace_count(hex) / 2 != binary_non_whitespace_count(base64) / 4 * 3 - base64_padding_count(base64) do return false

	hex_index := 0
	base64_iterator := Base64_Byte_Iterator{value = base64}
	for {
		first_nibble, more := next_hex_nibble(hex, &hex_index)
		if !more do break
		second_nibble, second_more := next_hex_nibble(hex, &hex_index)
		if !second_more do return false
		base64_byte, base64_more := next_base64_byte(&base64_iterator)
		if !base64_more || first_nibble << 4 | second_nibble != base64_byte do return false
	}
	_, base64_more := next_base64_byte(&base64_iterator)
	return !base64_more
}

@(private) next_base64_byte :: proc(iterator: ^Base64_Byte_Iterator) -> (byte: u8, more: bool) {
	if iterator.byte_index == iterator.byte_count {
		if iterator.input_index == len(iterator.value) do return 0, false
		group := next_base64_group(iterator.value, &iterator.input_index)
		iterator.bytes, iterator.byte_count = decode_base64_group(group)
		iterator.byte_index = 0
	}
	byte = iterator.bytes[iterator.byte_index]
	iterator.byte_index += 1
	return byte, true
}

@(private) binary_non_whitespace_count :: proc(value: string) -> int {
	count := 0
	for character in value {
		if !is_xml_schema_whitespace(u8(character)) do count += 1
	}
	return count
}

@(private) base64_padding_count :: proc(value: string) -> int {
	count := 0
	for character in value {
		if u8(character) == '=' do count += 1
	}
	return count
}

@(private) next_base64_group :: proc(value: string, index: ^int) -> [4]u8 {
	group: [4]u8
	group_index := 0
	for group_index < len(group) {
		character := value[index^]
		index^ += 1
		if is_xml_schema_whitespace(character) do continue
		group[group_index] = character
		group_index += 1
	}
	return group
}

@(private) decode_base64_group :: proc(group: [4]u8) -> (bytes: [3]u8, byte_count: int) {
	first, _ := base64_value(group[0])
	second, _ := base64_value(group[1])
	third, _ := base64_value(group[2])
	fourth, _ := base64_value(group[3])
	bytes[0] = first << 2 | second >> 4
	if group[2] == '=' do return bytes, 1
	bytes[1] = second << 4 | third >> 2
	if group[3] == '=' do return bytes, 2
	bytes[2] = third << 6 | fourth
	return bytes, 3
}
