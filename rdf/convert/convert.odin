// Package convert adapts the streaming RDF syntax packages without retaining a graph.
package convert

import "core:io"
import "core:strings"
import rdf ".."
import jsonld "../jsonld"
import nquads "../nquads"
import ntriples "../ntriples"
import turtle "../turtle"

// Format identifies one RDF syntax supported by the converter.
Format :: enum {
	N_Triples,
	N_Quads,
	Turtle,
	JSON_LD,
}

// format_name returns the stable command-line spelling for a format.
format_name :: proc(format: Format) -> string {
	switch format {
	case .N_Triples: return "ntriples"
	case .N_Quads:   return "nquads"
	case .Turtle:    return "turtle"
	case .JSON_LD:   return "jsonld"
	}
	return "unknown"
}

// Reader_Limits applies syntax-neutral resource bounds to the input reader.
// Zero leaves a limit disabled or selects the syntax reader's documented
// default. max_line_bytes applies to N-Triples and N-Quads; max_statement_bytes
// applies to Turtle's top-level production framing.
Reader_Limits :: struct {
	chunk_size:          int,
	max_records:         int,
	max_line_bytes:      int,
	max_statement_bytes: int,
	max_document_bytes:  int,
}

// Options selects the source and destination syntax. Turtle output uses only
// explicitly supplied prefixes; it never infers namespaces from input terms.
Options :: struct {
	input:           Format,
	output:          Format,
	reader_limits:   Reader_Limits,
	turtle_prefixes: []turtle.Prefix,
}

// Error_Code identifies a conversion failure. Source_Parse_Error includes the
// source parser's stable diagnostic in Error.detail. A named N-Quads graph is
// rejected when the requested target has no graph representation.
Error_Code :: enum {
	None,
	Unsupported_Input_Format,
	Unsupported_Output_Format,
	Invalid_Reader_Limits,
	Invalid_Turtle_Prefixes,
	Source_Parse_Error,
	Named_Graph_Not_Supported,
	Serialization_Error,
	Output_Write_Error,
}

// error_message returns a stable, allocation-free description.
error_message :: proc(code: Error_Code) -> string {
	switch code {
	case .None:                      return "no error"
	case .Unsupported_Input_Format:  return "unsupported input format"
	case .Unsupported_Output_Format: return "unsupported output format"
	case .Invalid_Reader_Limits:     return "reader limits must not be negative"
	case .Invalid_Turtle_Prefixes:   return "invalid Turtle prefix configuration"
	case .Source_Parse_Error:        return "source parse error"
	case .Named_Graph_Not_Supported: return "named graphs cannot be represented by the output format"
	case .Serialization_Error:       return "output serialization error"
	case .Output_Write_Error:        return "output write error"
	}
	return "unknown error"
}

@(private) valid_reader_limits :: proc(limits: Reader_Limits) -> bool {
	return limits.chunk_size >= 0 && limits.max_records >= 0 && limits.max_line_bytes >= 0 && limits.max_statement_bytes >= 0 && limits.max_document_bytes >= 0
}

// Error reports the conversion outcome. line and column are one-based for a
// source parse error and zero when the failure does not have a source location.
// detail is a stable parser or writer diagnostic; io_error preserves a reader
// or writer failure where one exists.
Error :: struct {
	code:     Error_Code,
	line:     int,
	column:   int,
	detail:   string,
	io_error: io.Error,
}

// Result reports successfully written statements and source bytes consumed.
// On a failure, statements counts only complete destination records written.
Result :: struct {
	error:      Error,
	statements: u64,
	bytes_read: u64,
}

@(private) State :: struct {
	output:          io.Writer,
	format:          Format,
	turtle_options:  turtle.Writer_Options,
	builder:         strings.Builder,
	error:           Error,
	statements:      u64,
}

@(private) write_all :: proc(output: io.Writer, text: string) -> io.Error {
	bytes := transmute([]byte)text
	for len(bytes) > 0 {
		count, err := io.write(output, bytes)
		if count < 0 || count > len(bytes) do return .Invalid_Write
		bytes = bytes[count:]
		if err != .None do return err
		if count == 0 do return .Short_Write
	}
	return .None
}

@(private) set_serialization_error :: proc(state: ^State, detail: string) {
	state.error = Error{code = .Serialization_Error, detail = detail}
}

@(private) write_destination_triple :: proc(triple: rdf.Triple, data: rawptr) -> bool {
	state := cast(^State)data
	strings.builder_reset(&state.builder)

	switch state.format {
	case .N_Triples:
		if err := ntriples.write_triple(&state.builder, triple); err != .None {
			set_serialization_error(state, ntriples.write_error_message(err))
			return false
		}
	case .N_Quads:
		if err := nquads.write_quad(&state.builder, rdf.default_graph_quad(triple)); err != .None {
			set_serialization_error(state, nquads.write_error_message(err))
			return false
		}
	case .Turtle:
		if err := turtle.write_triple(&state.builder, triple, state.turtle_options); err != .None {
			set_serialization_error(state, turtle.write_error_message(err))
			return false
		}
	case .JSON_LD:
		state.error = Error{code = .Unsupported_Output_Format}
		return false
	case:
		state.error = Error{code = .Unsupported_Output_Format}
		return false
	}

	if write_err := write_all(state.output, strings.to_string(state.builder)); write_err != .None {
		state.error = Error{code = .Output_Write_Error, io_error = write_err}
		return false
	}
	state.statements += 1
	return true
}

@(private) write_destination_quad :: proc(quad: rdf.Quad, data: rawptr) -> bool {
	state := cast(^State)data
	if state.format != .N_Quads && quad.has_graph {
		state.error = Error{code = .Named_Graph_Not_Supported}
		return false
	}
	if state.format != .N_Quads do return write_destination_triple(rdf.triple(quad), data)

	strings.builder_reset(&state.builder)
	if err := nquads.write_quad(&state.builder, quad); err != .None {
		set_serialization_error(state, nquads.write_error_message(err))
		return false
	}
	if write_err := write_all(state.output, strings.to_string(state.builder)); write_err != .None {
		state.error = Error{code = .Output_Write_Error, io_error = write_err}
		return false
	}
	state.statements += 1
	return true
}

@(private) set_parse_error :: proc(state: ^State, line, column: int, detail: string, io_error: io.Error = .None) {
	state.error = Error{
		code = .Source_Parse_Error,
		line = line,
		column = column,
		detail = detail,
		io_error = io_error,
	}
}

// convert parses reader with the selected source syntax and writes each valid
// RDF statement to output immediately. It does not retain a graph. N-Quads
// named graphs may only target N-Quads; all other requested conversions fail
// before the named statement is written. Reader ownership remains with the
// caller, as does output flushing and closing.
convert :: proc(reader: io.Reader, output: io.Writer, options: Options) -> Result {
	result: Result
	if options.output != .N_Triples && options.output != .N_Quads && options.output != .Turtle {
		result.error.code = .Unsupported_Output_Format
		return result
	}
	if options.input != .N_Triples && options.input != .N_Quads && options.input != .Turtle && options.input != .JSON_LD {
		result.error.code = .Unsupported_Input_Format
		return result
	}
	if !valid_reader_limits(options.reader_limits) {
		result.error.code = .Invalid_Reader_Limits
		return result
	}

	state := State{
		output = output,
		format = options.output,
		turtle_options = turtle.Writer_Options{prefixes = options.turtle_prefixes},
		builder = strings.builder_make(),
	}
	defer strings.builder_destroy(&state.builder)

	if options.output == .Turtle {
		if prefix_err := turtle.write_prefixes(&state.builder, options.turtle_prefixes); prefix_err != .None {
			result.error = Error{code = .Invalid_Turtle_Prefixes, detail = turtle.write_error_message(prefix_err)}
			return result
		}
		if write_err := write_all(output, strings.to_string(state.builder)); write_err != .None {
			result.error = Error{code = .Output_Write_Error, io_error = write_err}
			return result
		}
		strings.builder_reset(&state.builder)
	}

	switch options.input {
	case .N_Triples:
		parsed := ntriples.parse_reader(reader, write_destination_triple, ntriples.Reader_Options{
			chunk_size = options.reader_limits.chunk_size,
			max_line_bytes = options.reader_limits.max_line_bytes,
			max_triples = u64(options.reader_limits.max_records),
		}, &state)
		result.bytes_read = parsed.bytes_read
		if state.error.code == .None && parsed.error.code != .None {
			set_parse_error(&state, parsed.error.line, parsed.error.column, ntriples.parse_error_message(parsed.error.code), parsed.reader_error)
		}
	case .N_Quads:
		parsed := nquads.parse_reader(reader, write_destination_quad, nquads.Reader_Options{
			chunk_size = options.reader_limits.chunk_size,
			max_line_bytes = options.reader_limits.max_line_bytes,
			max_quads = u64(options.reader_limits.max_records),
		}, &state)
		result.bytes_read = parsed.bytes_read
		if state.error.code == .None && parsed.error.code != .None {
			set_parse_error(&state, parsed.error.line, parsed.error.column, nquads.parse_error_message(parsed.error.code), parsed.reader_error)
		}
	case .Turtle:
		parsed := turtle.parse_reader(reader, write_destination_triple, turtle.Reader_Options{
			parse = turtle.Parse_Options{max_triples = options.reader_limits.max_records},
			chunk_size = options.reader_limits.chunk_size,
			max_statement_bytes = options.reader_limits.max_statement_bytes,
		}, &state)
		result.bytes_read = parsed.bytes_read
		if state.error.code == .None && parsed.error.code != .None {
			set_parse_error(&state, parsed.error.line, parsed.error.column, turtle.parse_error_message(parsed.error.code), parsed.reader_error)
		}
	case .JSON_LD:
		parsed := jsonld.parse_reader(reader, write_destination_quad, jsonld.Reader_Options{
			chunk_size = options.reader_limits.chunk_size,
			max_document_bytes = options.reader_limits.max_document_bytes,
			parse = jsonld.Options{max_quads = options.reader_limits.max_records},
		}, &state)
		result.bytes_read = parsed.bytes_read
		if state.error.code == .None && parsed.error.code != .None {
			set_parse_error(&state, parsed.error.line, parsed.error.column, jsonld.parse_error_message(parsed.error.code), parsed.reader_error)
		}
	}
	result.error = state.error
	result.statements = state.statements
	return result
}
