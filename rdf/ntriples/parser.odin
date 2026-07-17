// Package ntriples provides a streaming RDF 1.1 N-Triples parser.
package ntriples

import "core:strings"
import "core:unicode/utf8"
import rdf ".."

// Error_Code identifies syntax, input, resource-limit, and sink outcomes.
Error_Code :: enum {
	None,
	Unexpected_End,
	Expected_Term,
	Expected_IRI,
	Expected_Dot,
	Trailing_Data,
	Invalid_UTF8,
	Invalid_IRI,
	Invalid_Escape,
	Invalid_Unicode_Escape,
	Invalid_Blank_Node,
	Invalid_Language_Tag,
	Missing_Sink,
	Invalid_Chunk_Size,
	Invalid_Line_Limit,
	Line_Too_Long,
	Triple_Limit,
	Reader_Error,
	No_Progress,
	Stopped,
}

// Parse_Error reports a one-based source location. A zero-value code is success.
Parse_Error :: struct {
	code:   Error_Code,
	line:   int,
	column: int,
}

// parse_error_message returns a stable, allocation-free description.
parse_error_message :: proc(code: Error_Code) -> string {
	switch code {
	case .None:                   return "no error"
	case .Unexpected_End:         return "unexpected end of input"
	case .Expected_Term:          return "expected RDF term"
	case .Expected_IRI:           return "expected IRI"
	case .Expected_Dot:           return "expected terminating dot"
	case .Trailing_Data:          return "unexpected data after triple"
	case .Invalid_UTF8:           return "invalid UTF-8"
	case .Invalid_IRI:            return "invalid absolute IRI"
	case .Invalid_Escape:         return "invalid escape sequence"
	case .Invalid_Unicode_Escape: return "invalid Unicode escape"
	case .Invalid_Blank_Node:     return "invalid blank-node label"
	case .Invalid_Language_Tag:   return "invalid language tag"
	case .Missing_Sink:           return "sink is required"
	case .Invalid_Chunk_Size:     return "chunk size must not be negative"
	case .Invalid_Line_Limit:     return "line limit must not be negative"
	case .Line_Too_Long:          return "line exceeds configured limit"
	case .Triple_Limit:           return "triple limit reached"
	case .Reader_Error:           return "reader error"
	case .No_Progress:            return "reader made no progress"
	case .Stopped:                return "stopped by sink"
	}
	return "unknown error"
}

// Sink is called once for every parsed triple. Returning false stops parsing.
// Unescaped strings point into the input; decoded strings remain valid only for
// the current callback. Consumers must copy or encode terms that need to outlive it.
Sink :: proc(triple: rdf.Triple, user_data: rawptr) -> bool

@(private) Scanner :: struct {
	input:  string,
	pos:    int,
	line:   int,
	column: int,
	scope:  rdf.Blank_Node_Scope,
}

@(private) error_at :: proc(s: ^Scanner, code: Error_Code) -> Parse_Error {
	return Parse_Error{code = code, line = s.line, column = s.column}
}

@(private) advance_bytes :: proc(s: ^Scanner, count: int) {
	s.pos += count
	s.column += 1
}

@(private) advance_ascii :: proc(s: ^Scanner) {
	s.pos += 1
	s.column += 1
}

@(private) skip_horizontal_space :: proc(s: ^Scanner) -> bool {
	start := s.pos
	for s.pos < len(s.input) && (s.input[s.pos] == ' ' || s.input[s.pos] == '\t') {
		advance_ascii(s)
	}
	return s.pos != start
}

@(private) skip_line_end :: proc(s: ^Scanner) -> bool {
	if s.pos >= len(s.input) || (s.input[s.pos] != '\r' && s.input[s.pos] != '\n') do return false
	for s.pos < len(s.input) && (s.input[s.pos] == '\r' || s.input[s.pos] == '\n') {
		if s.input[s.pos] == '\r' && s.pos + 1 < len(s.input) && s.input[s.pos + 1] == '\n' {
			s.pos += 2
		} else {
			s.pos += 1
		}
		s.line += 1
		s.column = 1
	}
	return true
}

@(private) skip_comment :: proc(s: ^Scanner) -> Parse_Error {
	for s.pos < len(s.input) && s.input[s.pos] != '\r' && s.input[s.pos] != '\n' {
		r, width := utf8.decode_rune_in_string(s.input[s.pos:])
		if width == 0 || (r == utf8.RUNE_ERROR && width == 1) do return error_at(s, .Invalid_UTF8)
		advance_bytes(s, width)
	}
	return {}
}

@(private) hex_value :: proc(c: byte) -> (u32, bool) {
	switch {
	case c >= '0' && c <= '9': return u32(c - '0'), true
	case c >= 'a' && c <= 'f': return u32(c - 'a' + 10), true
	case c >= 'A' && c <= 'F': return u32(c - 'A' + 10), true
	}
	return 0, false
}

@(private) read_uchar :: proc(s: ^Scanner) -> (rune, Parse_Error) {
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
	if s.pos + 2 + digits > len(s.input) do return 0, error_at(s, .Unexpected_End)
	value: u32
	for i in 0..<digits {
		nibble, ok := hex_value(s.input[s.pos + 2 + i])
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

@(private) decode_utf8 :: proc(s: ^Scanner) -> (rune, int, Parse_Error) {
	r, width := utf8.decode_rune_in_string(s.input[s.pos:])
	if width == 0 || (r == utf8.RUNE_ERROR && width == 1) {
		return 0, 0, error_at(s, .Invalid_UTF8)
	}
	return r, width, {}
}

@(private) is_absolute_iri :: proc(value: string) -> bool {
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

@(private) read_iri :: proc(s: ^Scanner, decoded: ^strings.Builder) -> (rdf.Term, Parse_Error) {
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

@(private) is_pn_chars_base :: proc(r: rune) -> bool {
	u := u32(r)
	return (u >= 'A' && u <= 'Z') || (u >= 'a' && u <= 'z') ||
		(u >= 0x00c0 && u <= 0x00d6) || (u >= 0x00d8 && u <= 0x00f6) ||
		(u >= 0x00f8 && u <= 0x02ff) || (u >= 0x0370 && u <= 0x037d) ||
		(u >= 0x037f && u <= 0x1fff) || (u >= 0x200c && u <= 0x200d) ||
		(u >= 0x2070 && u <= 0x218f) || (u >= 0x2c00 && u <= 0x2fef) ||
		(u >= 0x3001 && u <= 0xd7ff) || (u >= 0xf900 && u <= 0xfdcf) ||
		(u >= 0xfdf0 && u <= 0xfffd) || (u >= 0x10000 && u <= 0xeffff)
}

@(private) is_pn_chars_u :: proc(r: rune) -> bool { return is_pn_chars_base(r) || r == '_' }

@(private) is_pn_chars :: proc(r: rune) -> bool {
	u := u32(r)
	return is_pn_chars_u(r) || r == '-' || (u >= '0' && u <= '9') || u == 0x00b7 ||
		(u >= 0x0300 && u <= 0x036f) || (u >= 0x203f && u <= 0x2040)
}

@(private) read_blank_node :: proc(s: ^Scanner) -> (rdf.Term, Parse_Error) {
	if s.pos + 2 > len(s.input) || s.input[s.pos:s.pos + 2] != "_:" do return {}, error_at(s, .Expected_Term)
	advance_ascii(s); advance_ascii(s)
	start := s.pos
	r, width, err := decode_utf8(s)
	if err.code != .None do return {}, err
	if !(is_pn_chars_u(r) || (r >= '0' && r <= '9')) do return {}, error_at(s, .Invalid_Blank_Node)
	advance_bytes(s, width)
	last_was_dot := false
	for s.pos < len(s.input) {
		if s.input[s.pos] == '.' {
			// A dot belongs to the label only when followed by another PN_CHARS.
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

@(private) decode_utf8_at :: proc(input: string, pos, line, column: int) -> (rune, int, Parse_Error) {
	tmp := Scanner{input = input, pos = pos, line = line, column = column}
	return decode_utf8(&tmp)
}

@(private) read_language :: proc(s: ^Scanner) -> (string, Parse_Error) {
	advance_ascii(s) // @
	start := s.pos
	letters := 0
	for s.pos < len(s.input) && ((s.input[s.pos] >= 'a' && s.input[s.pos] <= 'z') || (s.input[s.pos] >= 'A' && s.input[s.pos] <= 'Z')) {
		advance_ascii(s); letters += 1
	}
	if letters == 0 do return "", error_at(s, .Invalid_Language_Tag)
	for s.pos < len(s.input) && s.input[s.pos] == '-' {
		advance_ascii(s)
		part := 0
		for s.pos < len(s.input) {
			c := s.input[s.pos]
			if !((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')) do break
			advance_ascii(s); part += 1
		}
		if part == 0 do return "", error_at(s, .Invalid_Language_Tag)
	}
	return s.input[start:s.pos], {}
}

@(private) read_literal :: proc(s: ^Scanner, decoded, datatype_builder: ^strings.Builder) -> (rdf.Term, Parse_Error) {
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
				s.pos += 2; s.column += 2
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
		advance_ascii(s); advance_ascii(s)
		term, iri_err := read_iri(s, datatype_builder)
		if iri_err.code != .None do return {}, iri_err
		datatype = term.value
	}
	if len(language) > 0 do return rdf.language_literal(value, language), {}
	if len(datatype) > 0 do return rdf.typed_literal(value, datatype), {}
	return rdf.literal(value), {}
}

@(private) read_term :: proc(s: ^Scanner, decoded, datatype_builder: ^strings.Builder) -> (rdf.Term, Parse_Error) {
	if s.pos >= len(s.input) do return {}, error_at(s, .Unexpected_End)
	switch s.input[s.pos] {
	case '<': return read_iri(s, decoded)
	case '_': return read_blank_node(s)
	case '"': return read_literal(s, decoded, datatype_builder)
	}
	return {}, error_at(s, .Expected_Term)
}

// parse_scoped parses a complete document using a caller-provided blank-node
// scope. It supports syntax adapters that must preserve identity across records.
// Temporary memory is allocated only for terms that contain escape sequences.
parse_scoped :: proc(input: string, sink: Sink, scope: rdf.Blank_Node_Scope, user_data: rawptr = nil) -> Parse_Error {
	if sink == nil do return Parse_Error{code = .Missing_Sink, line = 1, column = 1}
	s := Scanner{input = input, line = 1, column = 1, scope = scope}
	builders: [4]strings.Builder
	for &builder in builders {
		builder = strings.builder_make()
	}
	defer for &builder in builders do strings.builder_destroy(&builder)
	for s.pos < len(input) {
		skip_horizontal_space(&s)
		if s.pos >= len(input) do break
		if input[s.pos] == '#' {
			if comment_err := skip_comment(&s); comment_err.code != .None do return comment_err
			skip_line_end(&s); continue
		}
		if skip_line_end(&s) do continue
		for &builder in builders do strings.builder_reset(&builder)

		subject, err := read_term(&s, &builders[0], &builders[3])
		if err.code != .None do return err
		if subject.kind == .Literal do return error_at(&s, .Expected_Term)
		skip_horizontal_space(&s)
		predicate, pred_err := read_iri(&s, &builders[1])
		if pred_err.code != .None do return pred_err
		skip_horizontal_space(&s)
		object, obj_err := read_term(&s, &builders[2], &builders[3])
		if obj_err.code != .None do return obj_err
		skip_horizontal_space(&s)
		if s.pos >= len(input) || input[s.pos] != '.' do return error_at(&s, .Expected_Dot)
		advance_ascii(&s)
		skip_horizontal_space(&s)
		if s.pos < len(input) && input[s.pos] == '#' {
			if comment_err := skip_comment(&s); comment_err.code != .None do return comment_err
		}
		if s.pos < len(input) && input[s.pos] != '\r' && input[s.pos] != '\n' do return error_at(&s, .Trailing_Data)
		if !sink(rdf.Triple{subject, predicate, object}, user_data) do return error_at(&s, .Stopped)
		if s.pos < len(input) do skip_line_end(&s)
	}
	return {}
}

// parse parses a complete UTF-8 N-Triples document. Blank-node labels share
// one non-zero scope for this call and are distinct from labels in other calls.
parse :: proc(input: string, sink: Sink, user_data: rawptr = nil) -> Parse_Error {
	return parse_scoped(input, sink, rdf.new_blank_node_scope(), user_data)
}
