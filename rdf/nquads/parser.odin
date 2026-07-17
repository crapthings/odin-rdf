// Package nquads provides a streaming RDF 1.1 N-Quads parser.
package nquads

import "core:strings"
import "core:unicode/utf8"
import rdf ".."
import ntriples "../ntriples"

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
	case .None:               return "no error"
	case .Unexpected_End:     return "unexpected end of input"
	case .Expected_Quad:      return "expected N-Quads statement"
	case .Expected_Term:      return "expected RDF term"
	case .Expected_IRI:       return "expected IRI"
	case .Expected_Dot:       return "expected terminating dot"
	case .Trailing_Data:      return "unexpected data after quad"
	case .Invalid_UTF8:       return "invalid UTF-8"
	case .Invalid_IRI:        return "invalid absolute IRI"
	case .Invalid_Escape:     return "invalid escape sequence"
	case .Invalid_Unicode_Escape: return "invalid Unicode escape"
	case .Invalid_Blank_Node: return "invalid blank-node label"
	case .Invalid_Language_Tag: return "invalid language tag"
	case .Invalid_Graph:      return "graph name must be an IRI or blank node"
	case .Missing_Sink:       return "sink is required"
	case .Invalid_Chunk_Size: return "chunk size must not be negative"
	case .Invalid_Line_Limit: return "line limit must not be negative"
	case .Line_Too_Long:      return "line exceeds configured limit"
	case .Quad_Limit:         return "quad limit reached"
	case .Reader_Error:       return "reader error"
	case .No_Progress:        return "reader made no progress"
	case .Stopped:            return "stopped by sink"
	}
	return "unknown error"
}

// Sink is called once for every parsed quad. Returning false stops parsing.
// Term strings have the same callback-scoped lifetime as ntriples.Sink strings.
Sink :: proc(quad: rdf.Quad, user_data: rawptr) -> bool

@(private) Token :: struct {
	value:  string,
	column: int,
}

@(private) Record :: struct {
	tokens: [4]Token,
	count:  int,
	empty:  bool,
	dot_column: int,
}

@(private) is_space :: proc(c: byte) -> bool {
	return c == ' ' || c == '\t'
}

@(private) column_at :: proc(input: string, pos: int) -> int {
	return utf8.rune_count_in_string(input[:pos]) + 1
}

@(private) scan_iri_end :: proc(input: string, start: int) -> (int, bool) {
	pos := start + 1
	for pos < len(input) {
		if input[pos] == '\\' {
			pos += 1
			if pos >= len(input) do return len(input), false
		}
		if input[pos] == '>' do return pos + 1, true
		pos += 1
	}
	return pos, false
}

@(private) scan_literal_end :: proc(input: string, start: int) -> (int, bool) {
	pos := start + 1
	closed := false
	for pos < len(input) {
		if input[pos] == '\\' {
			pos += 2
			continue
		}
		if input[pos] == '"' {
			pos += 1
			closed = true
			break
		}
		if input[pos] == '\r' || input[pos] == '\n' do return pos, false
		pos += 1
	}
	if !closed do return pos, false
	if pos < len(input) && input[pos] == '@' {
		pos += 1
		for pos < len(input) {
			c := input[pos]
			if !((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-') do break
			pos += 1
		}
	} else if pos + 2 <= len(input) && input[pos:pos + 2] == "^^" {
		pos += 2
		if pos >= len(input) || input[pos] != '<' do return pos, false
		end, ok := scan_iri_end(input, pos)
		return end, ok
	}
	return pos, true
}

@(private) scan_bare_end :: proc(input: string, start: int) -> int {
	pos := start
	for pos < len(input) {
		c := input[pos]
		if is_space(c) || c == '\r' || c == '\n' || c == '#' || c == '<' || c == '"' do break
		if c == '.' {
			next := pos + 1
			if next >= len(input) || is_space(input[next]) || input[next] == '#' || input[next] == '\r' || input[next] == '\n' do break
		}
		pos += 1
	}
	return pos
}

@(private) tokenize_record :: proc(input: string) -> (Record, Parse_Error) {
	record: Record
	if !utf8.valid_string(input) do return record, Parse_Error{code = .Invalid_UTF8, line = 1, column = 1}
	pos := 0
	for pos < len(input) && is_space(input[pos]) do pos += 1
	if pos >= len(input) || input[pos] == '#' {
		record.empty = true
		return record, {}
	}

	for {
		for pos < len(input) && is_space(input[pos]) do pos += 1
		if pos >= len(input) do return record, Parse_Error{code = .Expected_Dot, line = 1, column = column_at(input, pos)}
		if input[pos] == '.' {
			record.dot_column = column_at(input, pos)
			pos += 1
			break
		}
		if record.count >= len(record.tokens) do return record, Parse_Error{code = .Trailing_Data, line = 1, column = column_at(input, pos)}

		start := pos
		ok := true
		switch input[pos] {
		case '<': pos, ok = scan_iri_end(input, pos)
		case '"': pos, ok = scan_literal_end(input, pos)
		case: pos = scan_bare_end(input, pos)
		}
		if !ok || pos == start do return record, Parse_Error{code = .Unexpected_End, line = 1, column = column_at(input, start)}
		record.tokens[record.count] = Token{value = input[start:pos], column = column_at(input, start)}
		record.count += 1
	}

	for pos < len(input) && is_space(input[pos]) do pos += 1
	if pos < len(input) && input[pos] == '#' do return record, {}
	if pos < len(input) do return record, Parse_Error{code = .Trailing_Data, line = 1, column = column_at(input, pos)}
	if record.count < 3 do return record, Parse_Error{code = .Expected_Quad, line = 1, column = 1}
	return record, {}
}

@(private) Graph_State :: struct {
	triple:    rdf.Triple,
	sink:      Sink,
	user_data: rawptr,
	called:    bool,
	valid:     bool,
	stopped:   bool,
}

@(private) graph_sink :: proc(parsed: rdf.Triple, data: rawptr) -> bool {
	state := cast(^Graph_State)data
	state.called = true
	graph := parsed.object
	if graph.kind != .IRI && graph.kind != .Blank_Node do return true
	state.valid = true
	quad := rdf.named_graph_quad(state.triple, graph)
	if !state.sink(quad, state.user_data) {
		state.stopped = true
		return false
	}
	return true
}

@(private) Triple_State :: struct {
	record:    Record,
	scope:     rdf.Blank_Node_Scope,
	sink:      Sink,
	user_data: rawptr,
	called:    bool,
	error:     Parse_Error,
}

@(private) triple_sink :: proc(parsed: rdf.Triple, data: rawptr) -> bool {
	state := cast(^Triple_State)data
	state.called = true
	if state.record.count == 3 {
		if !state.sink(rdf.default_graph_quad(parsed), state.user_data) {
			state.error = Parse_Error{code = .Stopped, line = 1, column = 1}
			return false
		}
		return true
	}

	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	strings.write_string(&builder, "<urn:odin-rdf:nquads:subject> <urn:odin-rdf:nquads:predicate> ")
	graph_start := utf8.rune_count_in_string(strings.to_string(builder)) + 1
	strings.write_string(&builder, state.record.tokens[3].value)
	strings.write_string(&builder, " .")
	graph_state := Graph_State{triple = parsed, sink = state.sink, user_data = state.user_data}
	err := ntriples.parse_scoped(strings.to_string(builder), graph_sink, state.scope, &graph_state)
	if graph_state.stopped {
		state.error = Parse_Error{code = .Stopped, line = 1, column = state.record.tokens[3].column}
		return false
	}
	if err.code != .None || !graph_state.called || !graph_state.valid {
		column := state.record.tokens[3].column
		if err.column >= graph_start do column += err.column - graph_start
		code := Error_Code.Invalid_Graph
		if err.code != .None do code = map_term_error_code(err.code)
		state.error = Parse_Error{code = code, line = 1, column = column}
		return false
	}
	return true
}

@(private) map_term_error_code :: proc(code: ntriples.Error_Code) -> Error_Code {
	switch code {
	case .None:                   return .None
	case .Unexpected_End:         return .Unexpected_End
	case .Expected_Term:          return .Expected_Term
	case .Expected_IRI:           return .Expected_IRI
	case .Expected_Dot:           return .Expected_Dot
	case .Trailing_Data:          return .Trailing_Data
	case .Invalid_UTF8:           return .Invalid_UTF8
	case .Invalid_IRI:            return .Invalid_IRI
	case .Invalid_Escape:         return .Invalid_Escape
	case .Invalid_Unicode_Escape: return .Invalid_Unicode_Escape
	case .Invalid_Blank_Node:     return .Invalid_Blank_Node
	case .Invalid_Language_Tag:   return .Invalid_Language_Tag
	case .Missing_Sink:           return .Missing_Sink
	case .Invalid_Chunk_Size:     return .Invalid_Chunk_Size
	case .Invalid_Line_Limit:     return .Invalid_Line_Limit
	case .Line_Too_Long:          return .Line_Too_Long
	case .Triple_Limit:           return .Quad_Limit
	case .Reader_Error:           return .Reader_Error
	case .No_Progress:            return .No_Progress
	case .Stopped:                return .Stopped
	}
	return .Expected_Term
}

@(private) map_triple_error :: proc(err: ntriples.Parse_Error, record: Record, synthetic_columns: [3]int) -> Parse_Error {
	code := map_term_error_code(err.code)
	column := record.dot_column
	for i in 0..<3 {
		token := record.tokens[i]
		width := utf8.rune_count_in_string(token.value)
		if err.column >= synthetic_columns[i] && err.column <= synthetic_columns[i] + width {
			column = token.column + err.column - synthetic_columns[i]
			break
		}
	}
	return Parse_Error{code = code, line = 1, column = max(column, 1)}
}

@(private) parse_line :: proc(input: string, sink: Sink, scope: rdf.Blank_Node_Scope, user_data: rawptr) -> Parse_Error {
	record, token_err := tokenize_record(input)
	if token_err.code != .None do return token_err
	if record.empty do return {}

	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	synthetic_columns: [3]int
	for i in 0..<3 {
		if i > 0 do strings.write_byte(&builder, ' ')
		synthetic_columns[i] = utf8.rune_count_in_string(strings.to_string(builder)) + 1
		strings.write_string(&builder, record.tokens[i].value)
	}
	strings.write_string(&builder, " .")
	state := Triple_State{record = record, scope = scope, sink = sink, user_data = user_data}
	err := ntriples.parse_scoped(strings.to_string(builder), triple_sink, scope, &state)
	if state.error.code != .None do return state.error
	if err.code != .None do return map_triple_error(err, record, synthetic_columns)
	if !state.called do return Parse_Error{code = .Expected_Quad, line = 1, column = 1}
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
