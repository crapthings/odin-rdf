// Package termlex provides syntax-internal RDF term lexical primitives.
// Document grammars and public parser errors remain owned by syntax packages.
package termlex

import "core:strings"
import "core:unicode/utf8"
import rdf "../.."

Error_Code :: enum {
	None,
	Unexpected_End,
	Expected_Term,
	Expected_IRI,
	Invalid_UTF8,
	Invalid_IRI,
	Invalid_Escape,
	Invalid_Unicode_Escape,
	Invalid_Blank_Node,
	Invalid_Language_Tag,
}

Error :: struct {
	code:   Error_Code,
	line:   int,
	column: int,
}

Scanner :: struct {
	input:  string,
	pos:    int,
	line:   int,
	column: int,
	scope:  rdf.Blank_Node_Scope,
}

error_at :: #force_inline proc(s: ^Scanner, code: Error_Code) -> Error {
	return Error{code = code, line = s.line, column = s.column}
}

advance_bytes :: #force_inline proc(s: ^Scanner, count: int) {
	s.pos += count
	s.column += 1
}

advance_ascii :: #force_inline proc(s: ^Scanner) {
	s.pos += 1
	s.column += 1
}

decode_utf8 :: #force_inline proc(s: ^Scanner) -> (rune, int, Error) {
	r, width := utf8.decode_rune_in_string(s.input[s.pos:])
	if width == 0 || (r == utf8.RUNE_ERROR && width == 1) {
		return 0, 0, error_at(s, .Invalid_UTF8)
	}
	return r, width, {}
}

decode_utf8_at :: proc(input: string, pos, line, column: int) -> (rune, int, Error) {
	tmp := Scanner{input = input, pos = pos, line = line, column = column}
	return decode_utf8(&tmp)
}

hex_value :: proc(c: byte) -> (u32, bool) {
	switch {
	case c >= '0' && c <= '9': return u32(c - '0'), true
	case c >= 'a' && c <= 'f': return u32(c - 'a' + 10), true
	case c >= 'A' && c <= 'F': return u32(c - 'A' + 10), true
	}
	return 0, false
}

read_uchar :: proc(s: ^Scanner) -> (rune, Error) {
	if s.pos + 2 > len(s.input) || s.input[s.pos] != '\\' {
		return 0, error_at(s, .Invalid_Unicode_Escape)
	}
	digits := 0
	if s.input[s.pos + 1] == 'u' {
		digits = 4
	} else if s.input[s.pos + 1] == 'U' {
		digits = 8
	} else {
		return 0, error_at(s, .Invalid_Escape)
	}
	value: u32
	for i in 0..<digits {
		index := s.pos + 2 + i
		if index >= len(s.input) do return 0, error_at(s, .Unexpected_End)
		digit := s.input[index]
		if digit == '\r' || digit == '\n' do return 0, error_at(s, .Unexpected_End)
		nibble, ok := hex_value(digit)
		if !ok do return 0, error_at(s, .Invalid_Unicode_Escape)
		value = value * 16 + nibble
	}
	if value > 0x10ffff || (value >= 0xd800 && value <= 0xdfff) {
		return 0, error_at(s, .Invalid_Unicode_Escape)
	}
	s.pos += 2 + digits
	s.column += 2 + digits
	return rune(value), {}
}

is_absolute_iri :: proc(value: string) -> bool {
	if len(value) < 2 do return false
	first := value[0]
	if !((first >= 'A' && first <= 'Z') || (first >= 'a' && first <= 'z')) do return false
	for i in 1..<len(value) {
		c := value[i]
		if c == ':' do return true
		if !((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '+' || c == '-' || c == '.') {
			return false
		}
	}
	return false
}

read_iri :: proc(s: ^Scanner, decoded: ^strings.Builder) -> (rdf.Term, Error) {
	if s.pos >= len(s.input) || s.input[s.pos] != '<' do return {}, error_at(s, .Expected_IRI)
	advance_ascii(s)
	start := s.pos
	chunk := start
	has_escape := false
	for s.pos < len(s.input) && s.input[s.pos] != '>' {
		c := s.input[s.pos]
		if c == '\\' {
			has_escape = true
			strings.write_string(decoded, s.input[chunk:s.pos])
			r, err := read_uchar(s)
			if err.code != .None do return {}, err
			strings.write_rune(decoded, r)
			chunk = s.pos
			continue
		}
		if c <= ' ' || c == '<' || c == '"' || c == '{' || c == '}' || c == '|' || c == '^' || c == '`' {
			return {}, error_at(s, .Expected_IRI)
		}
		_, width, err := decode_utf8(s)
		if err.code != .None do return {}, err
		advance_bytes(s, width)
	}
	if s.pos >= len(s.input) do return {}, error_at(s, .Unexpected_End)
	value := s.input[start:s.pos]
	if has_escape {
		strings.write_string(decoded, s.input[chunk:s.pos])
		value = strings.to_string(decoded^)
	}
	if !is_absolute_iri(value) do return {}, error_at(s, .Invalid_IRI)
	advance_ascii(s)
	return rdf.iri(value), {}
}

is_pn_chars_base :: proc(r: rune) -> bool {
	u := u32(r)
	return (u >= 'A' && u <= 'Z') || (u >= 'a' && u <= 'z') ||
		(u >= 0x00c0 && u <= 0x00d6) || (u >= 0x00d8 && u <= 0x00f6) ||
		(u >= 0x00f8 && u <= 0x02ff) || (u >= 0x0370 && u <= 0x037d) ||
		(u >= 0x037f && u <= 0x1fff) || (u >= 0x200c && u <= 0x200d) ||
		(u >= 0x2070 && u <= 0x218f) || (u >= 0x2c00 && u <= 0x2fef) ||
		(u >= 0x3001 && u <= 0xd7ff) || (u >= 0xf900 && u <= 0xfdcf) ||
		(u >= 0xfdf0 && u <= 0xfffd) || (u >= 0x10000 && u <= 0xeffff)
}

is_pn_chars_u :: #force_inline proc(r: rune) -> bool { return is_pn_chars_base(r) || r == '_' }

is_pn_chars :: #force_inline proc(r: rune) -> bool {
	u := u32(r)
	return is_pn_chars_u(r) || r == '-' || (u >= '0' && u <= '9') || u == 0x00b7 ||
		(u >= 0x0300 && u <= 0x036f) || (u >= 0x203f && u <= 0x2040)
}

read_blank_node :: proc(s: ^Scanner) -> (rdf.Term, Error) {
	if s.pos + 2 > len(s.input) || s.input[s.pos:s.pos + 2] != "_:" do return {}, error_at(s, .Expected_Term)
	advance_ascii(s)
	advance_ascii(s)
	start := s.pos
	r, width, err := decode_utf8(s)
	if err.code != .None do return {}, err
	if !(is_pn_chars_u(r) || (r >= '0' && r <= '9')) do return {}, error_at(s, .Invalid_Blank_Node)
	advance_bytes(s, width)
	last_was_dot := false
	for s.pos < len(s.input) {
		if s.input[s.pos] == '.' {
			if s.pos + 1 >= len(s.input) do break
			next, _, next_err := decode_utf8_at(s.input, s.pos + 1, s.line, s.column + 1)
			if next_err.code != .None || !is_pn_chars(next) do break
			advance_ascii(s)
			last_was_dot = true
			continue
		}
		r, width, err = decode_utf8(s)
		if err.code != .None do return {}, err
		if !is_pn_chars(r) do break
		advance_bytes(s, width)
		last_was_dot = false
	}
	if last_was_dot do return {}, error_at(s, .Invalid_Blank_Node)
	return rdf.blank_node(s.input[start:s.pos], s.scope), {}
}

read_language :: proc(s: ^Scanner) -> (string, Error) {
	advance_ascii(s)
	start := s.pos
	letters := 0
	for s.pos < len(s.input) && ((s.input[s.pos] >= 'a' && s.input[s.pos] <= 'z') || (s.input[s.pos] >= 'A' && s.input[s.pos] <= 'Z')) {
		advance_ascii(s)
		letters += 1
	}
	if letters == 0 do return "", error_at(s, .Invalid_Language_Tag)
	for s.pos < len(s.input) && s.input[s.pos] == '-' {
		advance_ascii(s)
		part := 0
		for s.pos < len(s.input) {
			c := s.input[s.pos]
			if !((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')) do break
			advance_ascii(s)
			part += 1
		}
		if part == 0 do return "", error_at(s, .Invalid_Language_Tag)
	}
	return s.input[start:s.pos], {}
}

read_literal :: proc(s: ^Scanner, decoded, datatype_builder: ^strings.Builder) -> (rdf.Term, Error) {
	if s.pos >= len(s.input) || s.input[s.pos] != '"' do return {}, error_at(s, .Expected_Term)
	advance_ascii(s)
	start := s.pos
	chunk := start
	has_escape := false
	for s.pos < len(s.input) && s.input[s.pos] != '"' {
		if s.input[s.pos] == '\r' || s.input[s.pos] == '\n' do return {}, error_at(s, .Expected_Term)
		if s.input[s.pos] == '\\' {
			has_escape = true
			strings.write_string(decoded, s.input[chunk:s.pos])
			if s.pos + 1 >= len(s.input) do return {}, error_at(s, .Unexpected_End)
			next := s.input[s.pos + 1]
			if next == 'u' || next == 'U' {
				r, err := read_uchar(s)
				if err.code != .None do return {}, err
				strings.write_rune(decoded, r)
			} else {
				mapped: byte
				switch next {
				case 't': mapped = '\t'
				case 'b': mapped = '\b'
				case 'n': mapped = '\n'
				case 'r': mapped = '\r'
				case 'f': mapped = '\f'
				case '"': mapped = '"'
				case '\'': mapped = '\''
				case '\\': mapped = '\\'
				case: return {}, error_at(s, .Invalid_Escape)
				}
				strings.write_byte(decoded, mapped)
				s.pos += 2
				s.column += 2
			}
			chunk = s.pos
			continue
		}
		_, width, err := decode_utf8(s)
		if err.code != .None do return {}, err
		advance_bytes(s, width)
	}
	if s.pos >= len(s.input) do return {}, error_at(s, .Unexpected_End)
	value := s.input[start:s.pos]
	if has_escape {
		strings.write_string(decoded, s.input[chunk:s.pos])
		value = strings.to_string(decoded^)
	}
	advance_ascii(s)
	language, datatype := "", ""
	if s.pos < len(s.input) && s.input[s.pos] == '@' {
		lang, lang_err := read_language(s)
		if lang_err.code != .None do return {}, lang_err
		language = lang
	} else if s.pos + 2 <= len(s.input) && s.input[s.pos:s.pos + 2] == "^^" {
		advance_ascii(s)
		advance_ascii(s)
		term, iri_err := read_iri(s, datatype_builder)
		if iri_err.code != .None do return {}, iri_err
		datatype = term.value
	}
	if len(language) > 0 do return rdf.language_literal(value, language), {}
	if len(datatype) > 0 do return rdf.typed_literal(value, datatype), {}
	return rdf.literal(value), {}
}

read_term :: proc(s: ^Scanner, decoded, datatype_builder: ^strings.Builder) -> (rdf.Term, Error) {
	if s.pos >= len(s.input) do return {}, error_at(s, .Unexpected_End)
	switch s.input[s.pos] {
	case '<': return read_iri(s, decoded)
	case '_': return read_blank_node(s)
	case '"': return read_literal(s, decoded, datatype_builder)
	}
	return {}, error_at(s, .Expected_Term)
}
