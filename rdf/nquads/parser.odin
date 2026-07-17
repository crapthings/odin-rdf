// Package nquads provides a streaming RDF 1.1 N-Quads parser.
package nquads

import "core:strings"
import "core:unicode/utf8"
import rdf ".."
import termlex "../internal/termlex"

// Error_Code identifies syntax, input, resource-limit, and sink outcomes.
Error_Code :: enum {
	None,
	Unexpected_End,
	Expected_Quad,
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
	Invalid_Graph,
	Missing_Sink,
	Invalid_Chunk_Size,
	Invalid_Line_Limit,
	Line_Too_Long,
	Quad_Limit,
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
	case .Expected_Quad:          return "expected N-Quads statement"
	case .Expected_Term:          return "expected RDF term"
	case .Expected_IRI:           return "expected IRI"
	case .Expected_Dot:           return "expected terminating dot"
	case .Trailing_Data:          return "unexpected data after quad"
	case .Invalid_UTF8:           return "invalid UTF-8"
	case .Invalid_IRI:            return "invalid absolute IRI"
	case .Invalid_Escape:         return "invalid escape sequence"
	case .Invalid_Unicode_Escape: return "invalid Unicode escape"
	case .Invalid_Blank_Node:     return "invalid blank-node label"
	case .Invalid_Language_Tag:   return "invalid language tag"
	case .Invalid_Graph:          return "graph name must be an IRI or blank node"
	case .Missing_Sink:           return "sink is required"
	case .Invalid_Chunk_Size:     return "chunk size must not be negative"
	case .Invalid_Line_Limit:     return "line limit must not be negative"
	case .Line_Too_Long:          return "line exceeds configured limit"
	case .Quad_Limit:             return "quad limit reached"
	case .Reader_Error:           return "reader error"
	case .No_Progress:            return "reader made no progress"
	case .Stopped:                return "stopped by sink"
	}
	return "unknown error"
}

// Sink is called once for every parsed quad. Returning false stops parsing.
// Input-backed and decoded term strings remain valid only for this callback.
Sink :: proc(quad: rdf.Quad, user_data: rawptr) -> bool

@(private) error_at :: proc(s: ^termlex.Scanner, code: Error_Code) -> Parse_Error {
	return Parse_Error{code = code, line = s.line, column = s.column}
}

@(private) map_lexer_error :: proc(err: termlex.Error) -> Parse_Error {
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

@(private) map_term_read_error :: proc(err: termlex.Error, start_column: int, leading: byte) -> Parse_Error {
	mapped := map_lexer_error(err)
	// The removed record tokenizer reported incomplete lexical forms at the
	// beginning of the term, including a literal with an incomplete datatype.
	if err.code == .Unexpected_End || (leading == '"' && err.code == .Expected_IRI) {
		mapped.code = .Unexpected_End
		mapped.column = start_column
	}
	return mapped
}

@(private) skip_horizontal_space :: proc(s: ^termlex.Scanner) {
	for s.pos < len(s.input) && (s.input[s.pos] == ' ' || s.input[s.pos] == '\t') {
		termlex.advance_ascii(s)
	}
}

@(private) at_dot :: proc(s: ^termlex.Scanner) -> bool {
	return s.pos < len(s.input) && s.input[s.pos] == '.'
}

@(private) missing_term_error :: proc(s: ^termlex.Scanner) -> Parse_Error {
	if s.pos >= len(s.input) do return error_at(s, .Expected_Dot)
	if at_dot(s) do return Parse_Error{code = .Expected_Quad, line = 1, column = 1}
	return {}
}

@(private) parse_line :: proc(input: string, sink: Sink, scope: rdf.Blank_Node_Scope, user_data: rawptr) -> Parse_Error {
	// Preserve the original parser's invalid-UTF-8 code and line-relative column.
	if !utf8.valid_string(input) do return Parse_Error{code = .Invalid_UTF8, line = 1, column = 1}
	s := termlex.Scanner{input = input, line = 1, column = 1, scope = scope}
	skip_horizontal_space(&s)
	if s.pos >= len(input) || input[s.pos] == '#' do return {}
	if at_dot(&s) do return Parse_Error{code = .Expected_Quad, line = 1, column = 1}

	builders: [5]strings.Builder
	for &builder in builders do builder = strings.builder_make()
	defer for &builder in builders do strings.builder_destroy(&builder)

	subject_column := s.column
	subject_leading := input[s.pos]
	subject, subject_err := termlex.read_term(&s, &builders[0], &builders[4])
	if subject_err.code != .None do return map_term_read_error(subject_err, subject_column, subject_leading)
	if subject.kind == .Literal do return error_at(&s, .Expected_Term)
	skip_horizontal_space(&s)
	if missing := missing_term_error(&s); missing.code != .None do return missing

	predicate_column := s.column
	predicate_leading := input[s.pos]
	predicate, predicate_err := termlex.read_iri(&s, &builders[1])
	if predicate_err.code != .None do return map_term_read_error(predicate_err, predicate_column, predicate_leading)
	skip_horizontal_space(&s)
	if missing := missing_term_error(&s); missing.code != .None do return missing

	object_column := s.column
	object_leading := input[s.pos]
	object, object_err := termlex.read_term(&s, &builders[2], &builders[4])
	if object_err.code != .None do return map_term_read_error(object_err, object_column, object_leading)
	skip_horizontal_space(&s)

	triple := rdf.Triple{subject, predicate, object}
	quad := rdf.default_graph_quad(triple)
	stop_column := 1
	if !at_dot(&s) {
		if s.pos >= len(input) do return error_at(&s, .Expected_Dot)
		graph_column := s.column
		graph_leading := input[s.pos]
		graph, graph_err := termlex.read_term(&s, &builders[3], &builders[4])
		if graph_err.code != .None do return map_term_read_error(graph_err, graph_column, graph_leading)
		if graph.kind != .IRI && graph.kind != .Blank_Node {
			return Parse_Error{code = .Invalid_Graph, line = 1, column = graph_column}
		}
		quad = rdf.named_graph_quad(triple, graph)
		stop_column = graph_column
		skip_horizontal_space(&s)
		if !at_dot(&s) {
			if s.pos >= len(input) do return error_at(&s, .Expected_Dot)
			return error_at(&s, .Trailing_Data)
		}
	}

	termlex.advance_ascii(&s)
	skip_horizontal_space(&s)
	if s.pos < len(input) && input[s.pos] != '#' do return error_at(&s, .Trailing_Data)
	if !sink(quad, user_data) do return Parse_Error{code = .Stopped, line = 1, column = stop_column}
	return {}
}

// parse parses a complete UTF-8 N-Quads document. Blank-node labels share one
// non-zero scope across triple terms and graph names for this call.
parse :: proc(input: string, sink: Sink, user_data: rawptr = nil) -> Parse_Error {
	if sink == nil do return Parse_Error{code = .Missing_Sink, line = 1, column = 1}
	scope := rdf.new_blank_node_scope()
	line, start, line_number := 0, 0, 1
	for line < len(input) {
		if input[line] != '\r' && input[line] != '\n' {
			line += 1
			continue
		}
		if err := parse_line(input[start:line], sink, scope, user_data); err.code != .None {
			err.line = line_number
			return err
		}
		if input[line] == '\r' && line + 1 < len(input) && input[line + 1] == '\n' do line += 1
		line += 1
		start = line
		line_number += 1
	}
	if start < len(input) {
		err := parse_line(input[start:], sink, scope, user_data)
		err.line = line_number
		return err
	}
	return {}
}
