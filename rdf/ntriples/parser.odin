// Package ntriples provides a streaming RDF 1.1 N-Triples parser.
package ntriples

import "core:strings"
import rdf ".."
import termlex "../internal/termlex"

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

@(private) error_at :: proc(s: ^termlex.Scanner, code: Error_Code) -> Parse_Error {
	return Parse_Error{code = code, line = s.line, column = s.column}
}

@(private) map_term_error :: proc(err: termlex.Error) -> Parse_Error {
	code: Error_Code
	switch err.code {
	case .None:                   code = .None
	case .Unexpected_End:         code = .Unexpected_End
	case .Expected_Term:          code = .Expected_Term
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

@(private) skip_horizontal_space :: proc(s: ^termlex.Scanner) -> bool {
	start := s.pos
	for s.pos < len(s.input) && (s.input[s.pos] == ' ' || s.input[s.pos] == '\t') {
		termlex.advance_ascii(s)
	}
	return s.pos != start
}

@(private) skip_line_end :: proc(s: ^termlex.Scanner) -> bool {
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

@(private) skip_comment :: proc(s: ^termlex.Scanner) -> Parse_Error {
	for s.pos < len(s.input) && s.input[s.pos] != '\r' && s.input[s.pos] != '\n' {
		_, width, err := termlex.decode_utf8(s)
		if err.code != .None do return map_term_error(err)
		termlex.advance_bytes(s, width)
	}
	return {}
}

// parse_scoped parses a complete document using a caller-provided blank-node
// scope. It is an advanced adapter for syntax implementations that must preserve
// identity across records. Pass a non-zero scope for document-scoped blank nodes.
// Temporary memory is allocated only for terms that contain escape sequences.
parse_scoped :: proc(input: string, sink: Sink, scope: rdf.Blank_Node_Scope, user_data: rawptr = nil) -> Parse_Error {
	if sink == nil do return Parse_Error{code = .Missing_Sink, line = 1, column = 1}
	s := termlex.Scanner{input = input, line = 1, column = 1, scope = scope}
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
			skip_line_end(&s)
			continue
		}
		if skip_line_end(&s) do continue
		for &builder in builders do strings.builder_reset(&builder)

		subject, term_err := termlex.read_term(&s, &builders[0], &builders[3])
		if term_err.code != .None do return map_term_error(term_err)
		if subject.kind == .Literal do return error_at(&s, .Expected_Term)
		skip_horizontal_space(&s)
		predicate, pred_err := termlex.read_iri(&s, &builders[1])
		if pred_err.code != .None do return map_term_error(pred_err)
		skip_horizontal_space(&s)
		object, obj_err := termlex.read_term(&s, &builders[2], &builders[3])
		if obj_err.code != .None do return map_term_error(obj_err)
		skip_horizontal_space(&s)
		if s.pos >= len(input) || input[s.pos] != '.' do return error_at(&s, .Expected_Dot)
		termlex.advance_ascii(&s)
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
