// Package trig provides RDF 1.1 TriG parsing.
package trig

import "core:strings"
import "core:strconv"
import rdf ".."
import termlex "../internal/termlex"

@(private) RDF_TYPE :: "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
@(private) RDF_FIRST :: "http://www.w3.org/1999/02/22-rdf-syntax-ns#first"
@(private) RDF_REST :: "http://www.w3.org/1999/02/22-rdf-syntax-ns#rest"
@(private) RDF_NIL :: "http://www.w3.org/1999/02/22-rdf-syntax-ns#nil"
@(private) XSD_INTEGER :: "http://www.w3.org/2001/XMLSchema#integer"
@(private) XSD_DECIMAL :: "http://www.w3.org/2001/XMLSchema#decimal"
@(private) XSD_DOUBLE :: "http://www.w3.org/2001/XMLSchema#double"
@(private) XSD_BOOLEAN :: "http://www.w3.org/2001/XMLSchema#boolean"

// Error_Code identifies TriG syntax, input, resource-limit, I/O, and sink outcomes.
Error_Code :: enum {
	None,
	Unexpected_End,
	Expected_Subject,
	Expected_Predicate,
	Expected_Object,
	Expected_IRI,
	Expected_Dot,
	Expected_Closing_Delimiter,
	Invalid_UTF8,
	Invalid_IRI,
	Invalid_Base_IRI,
	Invalid_Escape,
	Invalid_Unicode_Escape,
	Invalid_Blank_Node,
	Invalid_Language_Tag,
	Invalid_Prefixed_Name,
	Undefined_Prefix,
	Missing_Base,
	Missing_Sink,
	Invalid_Option,
	Invalid_Chunk_Size,
	Prefix_Limit,
	Prefix_Bytes_Limit,
	Token_Limit,
	Nesting_Limit,
	Document_Too_Large,
	Pending_Quad_Limit,
	Quad_Limit,
	Out_Of_Memory,
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
	case .None:                       return "no error"
	case .Unexpected_End:             return "unexpected end of input"
	case .Expected_Subject:            return "expected TriG subject"
	case .Expected_Predicate:          return "expected TriG predicate"
	case .Expected_Object:             return "expected TriG object"
	case .Expected_IRI:                return "expected IRI"
	case .Expected_Dot:                return "expected terminating dot"
	case .Expected_Closing_Delimiter:  return "expected closing delimiter"
	case .Invalid_UTF8:                return "invalid UTF-8"
	case .Invalid_IRI:                 return "invalid IRI reference"
	case .Invalid_Base_IRI:            return "base IRI must be absolute"
	case .Invalid_Escape:              return "invalid escape sequence"
	case .Invalid_Unicode_Escape:      return "invalid Unicode escape"
	case .Invalid_Blank_Node:          return "invalid blank-node label"
	case .Invalid_Language_Tag:        return "invalid language tag"
	case .Invalid_Prefixed_Name:       return "invalid prefixed name"
	case .Undefined_Prefix:            return "undefined prefix"
	case .Missing_Base:                return "relative IRI requires a base IRI"
	case .Missing_Sink:                return "sink is required"
	case .Invalid_Option:              return "parser limits must not be negative"
	case .Invalid_Chunk_Size:          return "chunk size must not be negative"
	case .Prefix_Limit:                return "prefix limit reached"
	case .Prefix_Bytes_Limit:          return "prefix table exceeds configured byte limit"
	case .Token_Limit:                 return "token exceeds configured limit"
	case .Nesting_Limit:               return "nesting depth limit reached"
	case .Document_Too_Large:          return "document exceeds configured limit"
	case .Pending_Quad_Limit:          return "pending quad limit reached"
	case .Quad_Limit:                  return "quad limit reached"
	case .Out_Of_Memory:               return "memory allocation failed"
	case .Reader_Error:                return "reader error"
	case .No_Progress:                 return "reader made no progress"
	case .Stopped:                     return "stopped by sink"
	}
	return "unknown error"
}

// Sink receives quads after their complete top-level TriG statement has
// been validated. Term strings remain valid only for the current callback.
// Returning false stops parsing.
Sink :: proc(quad: rdf.Quad, user_data: rawptr) -> bool

// Parse_Options controls document state and resource limits. Zero limit values
// select documented defaults, except max_quads where zero disables the limit.
Parse_Options :: struct {
	// Initial absolute base IRI used before any base directive.
	base_iri:            string,
	// Maximum decoded bytes in one lexical token.
	max_token_bytes:     int,
	// Maximum number of distinct prefix labels.
	max_prefixes:        int,
	// Maximum combined bytes retained by the prefix table.
	max_prefix_bytes:    int,
	// Maximum nested property-list and collection depth.
	max_nesting_depth:   int,
	// Maximum expanded quads buffered before one statement commits.
	max_pending_quads: int,
	// Maximum quads emitted by the document. Zero disables the limit.
	max_quads:           int,
}

DEFAULT_MAX_TOKEN_BYTES     :: 16 * 1024 * 1024
DEFAULT_MAX_PREFIXES        :: 1024
DEFAULT_MAX_PREFIX_BYTES    :: 16 * 1024 * 1024
DEFAULT_MAX_NESTING_DEPTH   :: 256
DEFAULT_MAX_PENDING_QUADS   :: 100_000
DEFAULT_MAX_DOCUMENT_BYTES  :: 16 * 1024 * 1024

@(private) Parser :: struct {
	scanner:             termlex.Scanner,
	sink:                Sink,
	user_data:           rawptr,
	base_iri:            string,
	prefixes:            map[string]string,
	owned:               [dynamic]string,
	graph_owned:         [dynamic]string,
	pending:             [dynamic]rdf.Quad,
	max_token_bytes:     int,
	max_prefixes:        int,
	max_prefix_bytes:    int,
	prefix_bytes:        int,
	max_nesting_depth:   int,
	max_pending_quads: int,
	max_quads:           int,
	emitted:             int,
	depth:               int,
	generated:           u64,
	graph:               rdf.Term,
	has_graph:           bool,
	property_subject:    bool,
	graph_label_compound: bool,
}

@(private) error_at :: #force_inline proc(p: ^Parser, code: Error_Code) -> Parse_Error {
	return Parse_Error{code = code, line = p.scanner.line, column = p.scanner.column}
}

@(private) map_term_error :: proc(err: termlex.Error) -> Parse_Error {
	code: Error_Code
	switch err.code {
	case .None:                   code = .None
	case .Unexpected_End:         code = .Unexpected_End
	case .Expected_Term:          code = .Expected_Object
	case .Expected_IRI:           code = .Expected_IRI
	case .Invalid_UTF8:           code = .Invalid_UTF8
	case .Invalid_IRI:            code = .Invalid_IRI
	case .Invalid_Escape:         code = .Invalid_Escape
	case .Invalid_Unicode_Escape: code = .Invalid_Unicode_Escape
	case .Invalid_Blank_Node:     code = .Invalid_Blank_Node
	case .Invalid_Language_Tag:   code = .Invalid_Language_Tag
	}
	return Parse_Error{code = code, line = err.line, column = err.column}
}

@(private) own :: proc(p: ^Parser, value: string) -> (string, Parse_Error) {
	cloned, alloc_error := strings.clone(value)
	if alloc_error != nil do return "", error_at(p, .Out_Of_Memory)
	append(&p.owned, cloned)
	return cloned, {}
}

@(private) clear_owned :: proc(p: ^Parser) {
	for value in p.owned do delete(value)
	clear(&p.owned)
}

@(private) clear_graph_owned :: proc(p: ^Parser) {
	for value in p.graph_owned do delete(value)
	clear(&p.graph_owned)
}

@(private) clone_persistent :: proc(p: ^Parser, value: string) -> (string, Parse_Error) {
	cloned, alloc_error := strings.clone(value)
	if alloc_error != nil do return "", error_at(p, .Out_Of_Memory)
	return cloned, {}
}

@(private) own_term :: proc(p: ^Parser, term: rdf.Term) -> (rdf.Term, Parse_Error) {
	result := term
	value, err := own(p, term.value)
	if err.code != .None do return {}, err
	result.value = value
	if len(term.language) > 0 {
		result.language, err = own(p, term.language)
		if err.code != .None do return {}, err
	}
	if len(term.datatype) > 0 && term.datatype != rdf.XSD_STRING && term.datatype != rdf.RDF_LANG_STRING {
		result.datatype, err = own(p, term.datatype)
		if err.code != .None do return {}, err
	}
	return result, {}
}

@(private) own_graph_term :: proc(p: ^Parser, term: rdf.Term) -> (rdf.Term, Parse_Error) {
	result := term
	value, alloc_error := strings.clone(term.value)
	if alloc_error != nil do return {}, error_at(p, .Out_Of_Memory)
	append(&p.graph_owned, value)
	result.value = value
	return result, {}
}

@(private) skip_space_and_comments :: proc(p: ^Parser) -> Parse_Error {
	s := &p.scanner
	for s.pos < len(s.input) {
		c := s.input[s.pos]
		if c == ' ' || c == '\t' {
			termlex.advance_ascii(s)
			continue
		}
		if c == '\r' || c == '\n' {
			if c == '\r' && s.pos + 1 < len(s.input) && s.input[s.pos + 1] == '\n' do s.pos += 1
			s.pos += 1
			s.line += 1
			s.column = 1
			continue
		}
		if c == '#' {
			for s.pos < len(s.input) && s.input[s.pos] != '\r' && s.input[s.pos] != '\n' {
				_, width, utf8_err := termlex.decode_utf8(s)
				if utf8_err.code != .None do return map_term_error(utf8_err)
				termlex.advance_bytes(s, width)
			}
			continue
		}
		break
	}
	return {}
}

@(private) keyword_at :: proc(p: ^Parser, keyword: string, insensitive := false) -> bool {
	s := &p.scanner
	if s.pos + len(keyword) > len(s.input) do return false
	for c, index in keyword {
		actual := s.input[s.pos + index]
		expected := byte(c)
		if insensitive {
			if actual >= 'a' && actual <= 'z' do actual -= 'a' - 'A'
			if expected >= 'a' && expected <= 'z' do expected -= 'a' - 'A'
		}
		if expected != actual do return false
	}
	end := s.pos + len(keyword)
	if end < len(s.input) {
		c := s.input[end]
		if (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_' || c == ':' do return false
	}
	return true
}

@(private) consume_keyword :: proc(p: ^Parser, keyword: string) {
	for _ in keyword do termlex.advance_ascii(&p.scanner)
}

@(private) resolve_iriref :: proc(p: ^Parser, value: string) -> (string, Parse_Error) {
	if termlex.is_absolute_iri(value) do return own(p, value)
	if len(p.base_iri) == 0 do return "", error_at(p, .Missing_Base)
	resolved, ok := resolve_iri_reference(p.base_iri, value)
	if !ok do return "", error_at(p, .Invalid_IRI)
	append(&p.owned, resolved)
	return resolved, {}
}

@(private) read_iriref :: proc(p: ^Parser) -> (rdf.Term, Parse_Error) {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	value, lex_err := termlex.read_iriref(&p.scanner, &builder)
	if lex_err.code != .None do return {}, map_term_error(lex_err)
	for c in value {
		if c <= ' ' || c == '<' || c == '>' || c == '"' || c == '{' || c == '}' || c == '|' || c == '^' || c == '`' do return {}, error_at(p, .Invalid_IRI)
	}
	if len(value) > p.max_token_bytes do return {}, error_at(p, .Token_Limit)
	resolved, err := resolve_iriref(p, value)
	if err.code != .None do return {}, err
	return rdf.iri(resolved), {}
}

@(private) read_prefix_label :: proc(p: ^Parser) -> (string, Parse_Error) {
	s := &p.scanner
	start := s.pos
	if s.pos < len(s.input) && s.input[s.pos] == ':' {
		termlex.advance_ascii(s)
		return "", {}
	}
	r, width, utf8_err := termlex.decode_utf8(s)
	if utf8_err.code != .None do return "", map_term_error(utf8_err)
	if !termlex.is_pn_chars_base(r) do return "", error_at(p, .Invalid_Prefixed_Name)
	termlex.advance_bytes(s, width)
	last_dot := false
	for s.pos < len(s.input) && s.input[s.pos] != ':' {
		if s.input[s.pos] == '.' {
			last_dot = true
			termlex.advance_ascii(s)
			continue
		}
		r, width, utf8_err = termlex.decode_utf8(s)
		if utf8_err.code != .None do return "", map_term_error(utf8_err)
		if !termlex.is_pn_chars(r) do return "", error_at(p, .Invalid_Prefixed_Name)
		last_dot = false
		termlex.advance_bytes(s, width)
	}
	if last_dot || s.pos >= len(s.input) || s.input[s.pos] != ':' do return "", error_at(p, .Invalid_Prefixed_Name)
	label := s.input[start:s.pos]
	if len(label) > p.max_token_bytes do return "", error_at(p, .Token_Limit)
	termlex.advance_ascii(s)
	return label, {}
}

@(private) is_local_escape :: proc(c: byte) -> bool {
	switch c {
	case '_', '~', '.', '-', '!', '$', '&', '\'', '(', ')', '*', '+', ',', ';', '=', '/', '?', '#', '@', '%': return true
	}
	return false
}

@(private) read_prefixed_name :: proc(p: ^Parser) -> (rdf.Term, Parse_Error) {
	prefix, prefix_err := read_prefix_label(p)
	if prefix_err.code != .None do return {}, prefix_err
	namespace, defined := p.prefixes[prefix]
	if !defined do return {}, error_at(p, .Undefined_Prefix)
	s := &p.scanner
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	first_local := true
	for s.pos < len(s.input) {
		if len(builder.buf) > p.max_token_bytes do return {}, error_at(p, .Token_Limit)
		c := s.input[s.pos]
		if c == '\\' {
			if s.pos + 1 >= len(s.input) || !is_local_escape(s.input[s.pos + 1]) do return {}, error_at(p, .Invalid_Escape)
			strings.write_byte(&builder, s.input[s.pos + 1])
			s.pos += 2
			s.column += 2
			first_local = false
			continue
		}
		if c == '%' {
			if s.pos + 2 >= len(s.input) do return {}, error_at(p, .Invalid_Prefixed_Name)
			_, first := termlex.hex_value(s.input[s.pos + 1])
			_, second := termlex.hex_value(s.input[s.pos + 2])
			if !first || !second do return {}, error_at(p, .Invalid_Prefixed_Name)
			strings.write_string(&builder, s.input[s.pos:s.pos + 3])
			s.pos += 3
			s.column += 3
			first_local = false
			continue
		}
		if c == ':' {
			strings.write_byte(&builder, c)
			termlex.advance_ascii(s)
			first_local = false
			continue
		}
		if c == '.' {
			if s.pos + 1 >= len(s.input) do break
			next := s.input[s.pos + 1]
			if next == ' ' || next == '\t' || next == '\r' || next == '\n' || next == ';' || next == ',' || next == ']' || next == ')' || next == '}' || next == '#' do break
			strings.write_byte(&builder, c)
			termlex.advance_ascii(s)
			continue
		}
			r, width, utf8_err := termlex.decode_utf8(s)
		if utf8_err.code != .None do return {}, map_term_error(utf8_err)
		if first_local {
			if !(termlex.is_pn_chars_u(r) || (r >= '0' && r <= '9')) do break
		} else if !termlex.is_pn_chars(r) do break
		strings.write_string(&builder, s.input[s.pos:s.pos + width])
		termlex.advance_bytes(s, width)
		first_local = false
		if len(builder.buf) > p.max_token_bytes do return {}, error_at(p, .Token_Limit)
	}
	combined := strings.builder_make()
	defer strings.builder_destroy(&combined)
	strings.write_string(&combined, namespace)
	strings.write_string(&combined, strings.to_string(builder))
	value, own_err := own(p, strings.to_string(combined))
	if own_err.code != .None do return {}, own_err
	return rdf.iri(value), {}
}

@(private) looks_like_prefixed_name :: proc(p: ^Parser) -> bool {
	s := &p.scanner
	if s.pos < len(s.input) && s.input[s.pos] == ':' do return true
	for i := s.pos; i < len(s.input); i += 1 {
		c := s.input[i]
		if c == ':' do return true
		if c <= ' ' || c == ';' || c == ',' || c == ']' || c == ')' || c == '}' || c == '[' || c == '(' || c == '<' || c == '>' || c == '"' || c == '\'' do return false
	}
	return false
}

@(private) read_quoted_literal :: proc(p: ^Parser) -> (rdf.Term, Parse_Error) {
	s := &p.scanner
	quote := s.input[s.pos]
	long := s.pos + 2 < len(s.input) && s.input[s.pos + 1] == quote && s.input[s.pos + 2] == quote
	count := 1
	if long do count = 3
	for _ in 0..<count do termlex.advance_ascii(s)
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	for {
		if len(builder.buf) > p.max_token_bytes do return {}, error_at(p, .Token_Limit)
		if s.pos >= len(s.input) do return {}, error_at(p, .Unexpected_End)
		if s.input[s.pos] == quote {
			matched := 1
			if long {
				matched = 0
				for matched < 3 && s.pos + matched < len(s.input) && s.input[s.pos + matched] == quote do matched += 1
				if matched < 3 {
					for _ in 0..<matched {
						strings.write_byte(&builder, quote)
						termlex.advance_ascii(s)
					}
					continue
				}
			}
			for _ in 0..<count do termlex.advance_ascii(s)
			break
		}
		if s.input[s.pos] == '\r' || s.input[s.pos] == '\n' {
			if !long do return {}, error_at(p, .Expected_Closing_Delimiter)
			if s.input[s.pos] == '\r' && s.pos + 1 < len(s.input) && s.input[s.pos + 1] == '\n' {
				strings.write_string(&builder, "\r\n")
				s.pos += 2
			} else {
				strings.write_byte(&builder, s.input[s.pos])
				s.pos += 1
			}
			s.line += 1
			s.column = 1
			continue
		}
		if s.input[s.pos] == '\\' {
			if s.pos + 1 >= len(s.input) do return {}, error_at(p, .Unexpected_End)
			next := s.input[s.pos + 1]
			if next == 'u' || next == 'U' {
				r, unicode_err := termlex.read_uchar(s)
				if unicode_err.code != .None do return {}, map_term_error(unicode_err)
				strings.write_rune(&builder, r)
				continue
			}
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
			case: return {}, error_at(p, .Invalid_Escape)
			}
			strings.write_byte(&builder, mapped)
			s.pos += 2
			s.column += 2
			continue
		}
		_, width, utf8_err := termlex.decode_utf8(s)
		if utf8_err.code != .None do return {}, map_term_error(utf8_err)
		strings.write_string(&builder, s.input[s.pos:s.pos + width])
		termlex.advance_bytes(s, width)
		if len(builder.buf) > p.max_token_bytes do return {}, error_at(p, .Token_Limit)
	}
	value, own_err := own(p, strings.to_string(builder))
	if own_err.code != .None do return {}, own_err
	if s.pos < len(s.input) && s.input[s.pos] == '@' {
		language, language_err := termlex.read_language(s)
		if language_err.code != .None do return {}, map_term_error(language_err)
		owned_language, language_own_err := own(p, language)
		if language_own_err.code != .None do return {}, language_own_err
		return rdf.language_literal(value, owned_language), {}
	}
	if s.pos + 1 < len(s.input) && s.input[s.pos:s.pos + 2] == "^^" {
		s.pos += 2
		s.column += 2
		datatype, datatype_err := read_term(p, false)
		if datatype_err.code != .None || datatype.kind != .IRI do return {}, error_at(p, .Expected_IRI)
		return rdf.typed_literal(value, datatype.value), {}
	}
	return rdf.literal(value), {}
}

@(private) numeric_kind :: proc(token: string) -> (string, bool) {
	if len(token) == 0 do return "", false
	i := 0
	if token[i] == '+' || token[i] == '-' { i += 1; if i == len(token) do return "", false }
	digits_before := 0
	for i < len(token) && token[i] >= '0' && token[i] <= '9' { i += 1; digits_before += 1 }
	has_dot := false
	digits_after := 0
	if i < len(token) && token[i] == '.' {
		has_dot = true
		i += 1
		for i < len(token) && token[i] >= '0' && token[i] <= '9' { i += 1; digits_after += 1 }
	}
	has_exponent := false
	if i < len(token) && (token[i] == 'e' || token[i] == 'E') {
		has_exponent = true
		i += 1
		if i < len(token) && (token[i] == '+' || token[i] == '-') do i += 1
		exponent_digits := 0
		for i < len(token) && token[i] >= '0' && token[i] <= '9' { i += 1; exponent_digits += 1 }
		if exponent_digits == 0 do return "", false
	}
	if i != len(token) do return "", false
	if has_exponent && (digits_before > 0 || digits_after > 0) do return XSD_DOUBLE, true
	if has_dot && digits_after > 0 do return XSD_DECIMAL, true
	if !has_dot && digits_before > 0 do return XSD_INTEGER, true
	return "", false
}

@(private) read_bare_literal :: proc(p: ^Parser) -> (rdf.Term, Parse_Error) {
	s := &p.scanner
	start := s.pos
	for s.pos < len(s.input) {
		c := s.input[s.pos]
		if c == ' ' || c == '\t' || c == '\r' || c == '\n' || c == ';' || c == ',' || c == ']' || c == ')' || c == '}' || c == '#' do break
		if c == '.' {
			if s.pos + 1 >= len(s.input) || s.input[s.pos + 1] == ' ' || s.input[s.pos + 1] == '\t' || s.input[s.pos + 1] == '\r' || s.input[s.pos + 1] == '\n' || s.input[s.pos + 1] == '}' || s.input[s.pos + 1] == '#' do break
		}
		termlex.advance_ascii(s)
	}
	token := s.input[start:s.pos]
	if len(token) > p.max_token_bytes do return {}, error_at(p, .Token_Limit)
	if token == "true" || token == "false" {
		value, err := own(p, token)
		if err.code != .None do return {}, err
		return rdf.typed_literal(value, XSD_BOOLEAN), {}
	}
	if datatype, ok := numeric_kind(token); ok {
		value, err := own(p, token)
		if err.code != .None do return {}, err
		return rdf.typed_literal(value, datatype), {}
	}
	return {}, error_at(p, .Expected_Object)
}

@(private) fresh_blank_node :: proc(p: ^Parser) -> (rdf.Term, Parse_Error) {
	buffer: [32]byte
	number := strconv.write_int(buffer[:], i64(p.generated), 10)
	p.generated += 1
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	strings.write_string(&builder, "trig-genid-")
	strings.write_string(&builder, number)
	value, err := own(p, strings.to_string(builder))
	if err.code != .None do return {}, err
	return rdf.blank_node(value, p.scanner.scope), {}
}

@(private) enter_nesting :: proc(p: ^Parser) -> Parse_Error {
	if p.depth >= p.max_nesting_depth do return error_at(p, .Nesting_Limit)
	p.depth += 1
	return {}
}

@(private) read_blank_node_property_list :: proc(p: ^Parser, object: bool) -> (rdf.Term, Parse_Error) {
	if err := enter_nesting(p); err.code != .None do return {}, err
	defer p.depth -= 1
	termlex.advance_ascii(&p.scanner)
	if err := skip_space_and_comments(p); err.code != .None do return {}, err
	node, node_err := fresh_blank_node(p)
	if node_err.code != .None do return {}, node_err
	if p.scanner.pos < len(p.scanner.input) && p.scanner.input[p.scanner.pos] == ']' {
		termlex.advance_ascii(&p.scanner)
		return node, {}
	}
	if err := parse_predicate_object_list(p, node); err.code != .None do return {}, err
	if err := skip_space_and_comments(p); err.code != .None do return {}, err
	if p.scanner.pos >= len(p.scanner.input) || p.scanner.input[p.scanner.pos] != ']' do return {}, error_at(p, .Expected_Closing_Delimiter)
	termlex.advance_ascii(&p.scanner)
	if !object do p.property_subject = true
	return node, {}
}

@(private) read_collection :: proc(p: ^Parser, object: bool) -> (rdf.Term, Parse_Error) {
	if err := enter_nesting(p); err.code != .None do return {}, err
	defer p.depth -= 1
	termlex.advance_ascii(&p.scanner)
	if err := skip_space_and_comments(p); err.code != .None do return {}, err
	if p.scanner.pos < len(p.scanner.input) && p.scanner.input[p.scanner.pos] == ')' {
		termlex.advance_ascii(&p.scanner)
		if !object do p.graph_label_compound = true
		return rdf.iri(RDF_NIL), {}
	}
	head, head_err := fresh_blank_node(p)
	if head_err.code != .None do return {}, head_err
	current := head
	for {
		item, item_err := read_term(p, true)
		if item_err.code != .None do return {}, item_err
		if err := append_pending(p, rdf.Triple{current, rdf.iri(RDF_FIRST), item}); err.code != .None do return {}, err
		if err := skip_space_and_comments(p); err.code != .None do return {}, err
		if p.scanner.pos >= len(p.scanner.input) do return {}, error_at(p, .Expected_Closing_Delimiter)
		if p.scanner.input[p.scanner.pos] == ')' {
			if err := append_pending(p, rdf.Triple{current, rdf.iri(RDF_REST), rdf.iri(RDF_NIL)}); err.code != .None do return {}, err
			termlex.advance_ascii(&p.scanner)
			break
		}
		next, next_err := fresh_blank_node(p)
		if next_err.code != .None do return {}, next_err
		if err := append_pending(p, rdf.Triple{current, rdf.iri(RDF_REST), next}); err.code != .None do return {}, err
		current = next
	}
	if !object do p.graph_label_compound = true
	return head, {}
}

@(private) read_term :: proc(p: ^Parser, object: bool) -> (rdf.Term, Parse_Error) {
	s := &p.scanner
	if s.pos >= len(s.input) {
		if object do return {}, error_at(p, .Expected_Object)
		return {}, error_at(p, .Expected_Subject)
	}
	switch s.input[s.pos] {
	case '<': return read_iriref(p)
	case '_':
		term, lex_err := termlex.read_blank_node(s)
		if lex_err.code != .None do return {}, map_term_error(lex_err)
		if len(term.value) > p.max_token_bytes do return {}, error_at(p, .Token_Limit)
		return own_term(p, term)
	case '"', '\'':
		if !object do return {}, error_at(p, .Expected_Subject)
		return read_quoted_literal(p)
	case '[': return read_blank_node_property_list(p, object)
	case '(': return read_collection(p, object)
	}
	if looks_like_prefixed_name(p) do return read_prefixed_name(p)
	if object do return read_bare_literal(p)
	if object do return {}, error_at(p, .Expected_Object)
	return {}, error_at(p, .Expected_Subject)
}

@(private) read_verb :: proc(p: ^Parser) -> (rdf.Term, Parse_Error) {
	if keyword_at(p, "a") {
		consume_keyword(p, "a")
		return rdf.iri(RDF_TYPE), {}
	}
	term, err := read_term(p, false)
	if err.code != .None do return {}, Parse_Error{code = .Expected_Predicate, line = err.line, column = err.column}
	if term.kind != .IRI do return {}, error_at(p, .Expected_Predicate)
	return term, {}
}

@(private) append_pending :: proc(p: ^Parser, triple: rdf.Triple) -> Parse_Error {
	if len(p.pending) >= p.max_pending_quads do return error_at(p, .Pending_Quad_Limit)
	append(&p.pending, rdf.Quad{subject = triple.subject, predicate = triple.predicate, object = triple.object, graph = p.graph, has_graph = p.has_graph})
	return {}
}

@(private) commit_pending :: proc(p: ^Parser) -> Parse_Error {
	if p.max_quads > 0 && p.emitted + len(p.pending) > p.max_quads do return error_at(p, .Quad_Limit)
	for quad in p.pending {
		if !p.sink(quad, p.user_data) do return error_at(p, .Stopped)
		p.emitted += 1
	}
	clear(&p.pending)
	return {}
}

@(private) parse_object_list :: proc(p: ^Parser, subject, predicate: rdf.Term) -> Parse_Error {
	for {
		if err := skip_space_and_comments(p); err.code != .None do return err
		object, object_err := read_term(p, true)
		if object_err.code != .None do return object_err
		if err := append_pending(p, rdf.Triple{subject, predicate, object}); err.code != .None do return err
		if err := skip_space_and_comments(p); err.code != .None do return err
		if p.scanner.pos >= len(p.scanner.input) || p.scanner.input[p.scanner.pos] != ',' do break
		termlex.advance_ascii(&p.scanner)
	}
	return {}
}

@(private) parse_predicate_object_list :: proc(p: ^Parser, subject: rdf.Term) -> Parse_Error {
	for {
		if err := skip_space_and_comments(p); err.code != .None do return err
		predicate, predicate_err := read_verb(p)
		if predicate_err.code != .None do return predicate_err
		if err := skip_space_and_comments(p); err.code != .None do return err
		if err := parse_object_list(p, subject, predicate); err.code != .None do return err
		if err := skip_space_and_comments(p); err.code != .None do return err
		if p.scanner.pos >= len(p.scanner.input) || p.scanner.input[p.scanner.pos] != ';' do break
		for p.scanner.pos < len(p.scanner.input) && p.scanner.input[p.scanner.pos] == ';' {
			termlex.advance_ascii(&p.scanner)
			if err := skip_space_and_comments(p); err.code != .None do return err
		}
		// A predicate-object list may end before an enclosing blank-node
		// property list's closing delimiter. TriG inherits Turtle's permitted
		// trailing ';' form: [ ex:p ex:o ; ].
		if p.scanner.pos >= len(p.scanner.input) || p.scanner.input[p.scanner.pos] == '.' || p.scanner.input[p.scanner.pos] == ']' || p.scanner.input[p.scanner.pos] == '}' do break
	}
	return {}
}

@(private) read_directive_iri :: proc(p: ^Parser) -> (string, Parse_Error) {
	if err := skip_space_and_comments(p); err.code != .None do return "", err
	term, err := read_iriref(p)
	if err.code != .None do return "", err
	return term.value, {}
}

@(private) parse_prefix_directive :: proc(p: ^Parser, sparql: bool) -> Parse_Error {
	if sparql do consume_keyword(p, "PREFIX")
	else {
		consume_keyword(p, "@prefix")
		if p.scanner.pos >= len(p.scanner.input) || (p.scanner.input[p.scanner.pos] != ' ' && p.scanner.input[p.scanner.pos] != '\t') do return error_at(p, .Invalid_Prefixed_Name)
	}
	if err := skip_space_and_comments(p); err.code != .None do return err
	prefix, prefix_err := read_prefix_label(p)
	if prefix_err.code != .None do return prefix_err
	if err := skip_space_and_comments(p); err.code != .None do return err
	namespace_term, iri_err := read_iriref(p)
	if iri_err.code != .None do return iri_err
	if _, exists := p.prefixes[prefix]; !exists && len(p.prefixes) >= p.max_prefixes do return error_at(p, .Prefix_Limit)
	stored_prefix := prefix
	old_namespace, exists := p.prefixes[prefix]
	new_prefix_bytes := p.prefix_bytes + len(namespace_term.value)
	if exists do new_prefix_bytes -= len(old_namespace)
	else do new_prefix_bytes += len(prefix)
	if new_prefix_bytes > p.max_prefix_bytes do return error_at(p, .Prefix_Bytes_Limit)
	if !exists {
		own_err: Parse_Error
		stored_prefix, own_err = clone_persistent(p, prefix)
		if own_err.code != .None do return own_err
	}
	stored_namespace, namespace_own_err := clone_persistent(p, namespace_term.value)
	if namespace_own_err.code != .None {
		if !exists do delete(stored_prefix)
		return namespace_own_err
	}
	if exists do delete(old_namespace)
	p.prefixes[stored_prefix] = stored_namespace
	p.prefix_bytes = new_prefix_bytes
	if err := skip_space_and_comments(p); err.code != .None do return err
	if sparql do return {}
	if p.scanner.pos >= len(p.scanner.input) || p.scanner.input[p.scanner.pos] != '.' do return error_at(p, .Expected_Dot)
	termlex.advance_ascii(&p.scanner)
	return {}
}

@(private) parse_base_directive :: proc(p: ^Parser, sparql: bool) -> Parse_Error {
	if sparql do consume_keyword(p, "BASE")
	else {
		consume_keyword(p, "@base")
		if p.scanner.pos >= len(p.scanner.input) || (p.scanner.input[p.scanner.pos] != ' ' && p.scanner.input[p.scanner.pos] != '\t') do return error_at(p, .Expected_IRI)
	}
	base, iri_err := read_directive_iri(p)
	if iri_err.code != .None do return iri_err
	stored_base, own_err := clone_persistent(p, base)
	if own_err.code != .None do return own_err
	if len(p.base_iri) > 0 do delete(p.base_iri)
	p.base_iri = stored_base
	if err := skip_space_and_comments(p); err.code != .None do return err
	if sparql do return {}
	if p.scanner.pos >= len(p.scanner.input) || p.scanner.input[p.scanner.pos] != '.' do return error_at(p, .Expected_Dot)
	termlex.advance_ascii(&p.scanner)
	return {}
}

@(private) parse_triples_from_subject :: proc(p: ^Parser, subject: rdf.Term, closing_brace: bool) -> Parse_Error {
	if subject.kind == .Literal do return error_at(p, .Expected_Subject)
	if err := skip_space_and_comments(p); err.code != .None do return err
	can_close := closing_brace && p.scanner.pos < len(p.scanner.input) && p.scanner.input[p.scanner.pos] == '}'
	if !(p.property_subject && (can_close || p.scanner.pos < len(p.scanner.input) && p.scanner.input[p.scanner.pos] == '.')) {
		if err := parse_predicate_object_list(p, subject); err.code != .None do return err
	}
	if err := skip_space_and_comments(p); err.code != .None do return err
	if p.scanner.pos < len(p.scanner.input) && p.scanner.input[p.scanner.pos] == '.' {
		termlex.advance_ascii(&p.scanner)
	} else if !(closing_brace && p.scanner.pos < len(p.scanner.input) && p.scanner.input[p.scanner.pos] == '}') {
		return error_at(p, .Expected_Dot)
	}
	if err := commit_pending(p); err.code != .None do return err
	clear_owned(p)
	return {}
}

@(private) parse_triples :: proc(p: ^Parser, closing_brace: bool) -> Parse_Error {
	clear(&p.pending)
	p.property_subject = false
	p.graph_label_compound = false
	subject, subject_err := read_term(p, false)
	if subject_err.code != .None do return subject_err
	return parse_triples_from_subject(p, subject, closing_brace)
}

@(private) parse_graph_block :: proc(p: ^Parser, graph: rdf.Term, has_graph: bool) -> Parse_Error {
	if p.scanner.pos >= len(p.scanner.input) || p.scanner.input[p.scanner.pos] != '{' do return error_at(p, .Expected_Closing_Delimiter)
	termlex.advance_ascii(&p.scanner)
	stable_graph := graph
	if has_graph {
		graph_err: Parse_Error
		stable_graph, graph_err = own_graph_term(p, graph)
		if graph_err.code != .None do return graph_err
	}
	previous_graph, previous_has_graph := p.graph, p.has_graph
	p.graph, p.has_graph = stable_graph, has_graph
	defer {
		p.graph, p.has_graph = previous_graph, previous_has_graph
		clear_graph_owned(p)
	}
	for {
		if err := skip_space_and_comments(p); err.code != .None do return err
		if p.scanner.pos >= len(p.scanner.input) do return error_at(p, .Expected_Closing_Delimiter)
		if p.scanner.input[p.scanner.pos] == '}' {
			termlex.advance_ascii(&p.scanner)
			return {}
		}
		if err := parse_triples(p, true); err.code != .None do return err
	}
}

@(private) parse_document :: proc(p: ^Parser) -> Parse_Error {
	for {
		if err := skip_space_and_comments(p); err.code != .None do return err
		if p.scanner.pos >= len(p.scanner.input) do return {}
		if keyword_at(p, "@prefix") {
			if err := parse_prefix_directive(p, false); err.code != .None do return err
			clear_owned(p)
			continue
		}
		if keyword_at(p, "@base") {
			if err := parse_base_directive(p, false); err.code != .None do return err
			clear_owned(p)
			continue
		}
		if keyword_at(p, "PREFIX", true) {
			if err := parse_prefix_directive(p, true); err.code != .None do return err
			clear_owned(p)
			continue
		}
		if keyword_at(p, "BASE", true) {
			if err := parse_base_directive(p, true); err.code != .None do return err
			clear_owned(p)
			continue
		}
		if p.scanner.input[p.scanner.pos] == '{' {
			if err := parse_graph_block(p, {}, false); err.code != .None do return err
			continue
		}
		if keyword_at(p, "GRAPH", true) {
			consume_keyword(p, "GRAPH")
			if err := skip_space_and_comments(p); err.code != .None do return err
			clear(&p.pending)
			p.property_subject = false
			p.graph_label_compound = false
			graph, graph_err := read_term(p, false)
			if graph_err.code != .None do return graph_err
			if p.property_subject || p.graph_label_compound || graph.kind == .Literal do return error_at(p, .Expected_Subject)
			if err := skip_space_and_comments(p); err.code != .None do return err
			if err := parse_graph_block(p, graph, true); err.code != .None do return err
			clear_owned(p)
			continue
		}
		p.graph, p.has_graph = {}, false
		clear(&p.pending)
		p.property_subject = false
		p.graph_label_compound = false
		subject, subject_err := read_term(p, false)
		if subject_err.code != .None do return subject_err
		if err := skip_space_and_comments(p); err.code != .None do return err
		if p.scanner.pos < len(p.scanner.input) && p.scanner.input[p.scanner.pos] == '{' {
			if p.property_subject || p.graph_label_compound || subject.kind == .Literal do return error_at(p, .Expected_Subject)
			if err := parse_graph_block(p, subject, true); err.code != .None do return err
			clear_owned(p)
			continue
		}
		if err := parse_triples_from_subject(p, subject, false); err.code != .None do return err
	}
}

@(private) init_parser :: proc(input: string, sink: Sink, options: Parse_Options, user_data: rawptr) -> (Parser, Parse_Error) {
	if sink == nil do return {}, Parse_Error{code = .Missing_Sink, line = 1, column = 1}
	if options.max_token_bytes < 0 || options.max_prefixes < 0 || options.max_prefix_bytes < 0 || options.max_nesting_depth < 0 || options.max_pending_quads < 0 || options.max_quads < 0 {
		return {}, Parse_Error{code = .Invalid_Option, line = 1, column = 1}
	}
	if len(options.base_iri) > 0 && !termlex.is_absolute_iri(options.base_iri) {
		return {}, Parse_Error{code = .Invalid_Base_IRI, line = 1, column = 1}
	}
	p := Parser{
		scanner = termlex.Scanner{input = input, line = 1, column = 1, scope = rdf.new_blank_node_scope()},
		sink = sink,
		user_data = user_data,
		prefixes = make(map[string]string),
		owned = make([dynamic]string),
		graph_owned = make([dynamic]string),
		pending = make([dynamic]rdf.Quad),
		max_token_bytes = options.max_token_bytes,
		max_prefixes = options.max_prefixes,
		max_prefix_bytes = options.max_prefix_bytes,
		max_nesting_depth = options.max_nesting_depth,
		max_pending_quads = options.max_pending_quads,
		max_quads = options.max_quads,
	}
	if p.max_token_bytes == 0 do p.max_token_bytes = DEFAULT_MAX_TOKEN_BYTES
	if p.max_prefixes == 0 do p.max_prefixes = DEFAULT_MAX_PREFIXES
	if p.max_prefix_bytes == 0 do p.max_prefix_bytes = DEFAULT_MAX_PREFIX_BYTES
	if p.max_nesting_depth == 0 do p.max_nesting_depth = DEFAULT_MAX_NESTING_DEPTH
	if p.max_pending_quads == 0 do p.max_pending_quads = DEFAULT_MAX_PENDING_QUADS
	if len(options.base_iri) > 0 {
		base, err := clone_persistent(&p, options.base_iri)
		if err.code != .None do return p, err
		p.base_iri = base
	}
	return p, {}
}

@(private) destroy_parser :: proc(p: ^Parser) {
	for prefix, namespace in p.prefixes {
		delete(prefix)
		delete(namespace)
	}
	delete(p.prefixes)
	if len(p.base_iri) > 0 do delete(p.base_iri)
	delete(p.pending)
	clear_owned(p)
	delete(p.owned)
	clear_graph_owned(p)
	delete(p.graph_owned)
}

// parse parses a complete RDF 1.1 TriG document already held in memory.
// Blank-node labels and generated nodes share one non-zero document scope.
parse :: proc(input: string, sink: Sink, options: Parse_Options = {}, user_data: rawptr = nil) -> Parse_Error {
	p, init_err := init_parser(input, sink, options, user_data)
	if init_err.code != .None {
		if p.prefixes != nil do destroy_parser(&p)
		return init_err
	}
	defer destroy_parser(&p)
	return parse_document(&p)
}
