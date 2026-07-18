// Package convert adapts the streaming RDF syntax packages without retaining a graph.
package convert

import "core:io"
import "core:strings"
import rdf ".."
import dataset "../dataset"
import jsonld "../jsonld"
import nquads "../nquads"
import ntriples "../ntriples"
import rdfxml "../rdfxml"
import trig "../trig"
import turtle "../turtle"

// Format identifies one RDF syntax supported by the converter.
Format :: enum {
	N_Triples,
	N_Quads,
	Turtle,
	JSON_LD,
	RDF_XML,
	TriG,
}

// format_name returns the stable command-line spelling for a format.
format_name :: proc(format: Format) -> string {
	switch format {
	case .N_Triples: return "ntriples"
	case .N_Quads:   return "nquads"
	case .Turtle:    return "turtle"
	case .JSON_LD:   return "jsonld"
	case .RDF_XML:   return "rdfxml"
	case .TriG:      return "trig"
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

// Options selects the source and destination syntax. Turtle and TriG output
// use only explicitly supplied prefixes; they never infer namespaces from
// input terms. RDF/XML and JSON-LD output retain complete datasets and
// therefore require a positive reader_limits.max_records admission bound.
Options :: struct {
	input:           Format,
	output:          Format,
	reader_limits:   Reader_Limits,
	turtle_prefixes: []turtle.Prefix,
}

// Error_Code identifies a conversion failure. Source_Parse_Error includes the
// source parser's stable diagnostic in Error.detail. A named graph is rejected
// when the requested target has no graph representation.
Error_Code :: enum {
	None,
	Unsupported_Input_Format,
	Unsupported_Output_Format,
	Invalid_Reader_Limits,
	RDF_XML_Record_Limit_Required,
	JSON_LD_Record_Limit_Required,
	Invalid_Turtle_Prefixes,
	Source_Parse_Error,
	Named_Graph_Not_Supported,
	Graph_Collection_Error,
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
	case .RDF_XML_Record_Limit_Required: return "RDF/XML output requires a positive max-records limit"
	case .JSON_LD_Record_Limit_Required: return "JSON-LD output requires a positive max-records limit"
	case .Invalid_Turtle_Prefixes:   return "invalid Turtle prefix configuration"
	case .Source_Parse_Error:        return "source parse error"
	case .Named_Graph_Not_Supported: return "named graphs cannot be represented by the output format"
	case .Graph_Collection_Error:    return "graph collection error"
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

@(private) Batch_State :: struct {
	collector: dataset.Collector,
	error:     Error,
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
	case .RDF_XML:
		state.error = Error{code = .Unsupported_Output_Format}
		return false
	case .TriG:
		if err := trig.write_quad(&state.builder, rdf.default_graph_quad(triple), trig.Writer_Options{prefixes = state.turtle_options.prefixes}); err != .None {
			set_serialization_error(state, trig.write_error_message(err))
			return false
		}
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
	if state.format != .N_Quads && state.format != .TriG && quad.has_graph {
		state.error = Error{code = .Named_Graph_Not_Supported}
		return false
	}
	if state.format != .N_Quads && state.format != .TriG do return write_destination_triple(rdf.triple(quad), data)

	strings.builder_reset(&state.builder)
	if state.format == .N_Quads {
		if err := nquads.write_quad(&state.builder, quad); err != .None {
			set_serialization_error(state, nquads.write_error_message(err))
			return false
		}
	} else {
		if err := trig.write_quad(&state.builder, quad, trig.Writer_Options{prefixes = state.turtle_options.prefixes}); err != .None {
			set_serialization_error(state, trig.write_error_message(err))
			return false
		}
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

@(private) set_batch_parse_error :: proc(state: ^Batch_State, line, column: int, detail: string, io_error: io.Error = .None) {
	state.error = Error{
		code = .Source_Parse_Error,
		line = line,
		column = column,
		detail = detail,
		io_error = io_error,
	}
}

@(private) collect_rdfxml_quad :: proc(quad: rdf.Quad, data: rawptr) -> bool {
	state := cast(^Batch_State)data
	if quad.has_graph {
		state.error = Error{code = .Named_Graph_Not_Supported}
		return false
	}
	if collect_err := dataset.add(&state.collector, quad); collect_err != .None {
		state.error = Error{code = .Graph_Collection_Error, detail = dataset.error_message(collect_err)}
		return false
	}
	return true
}

@(private) collect_rdfxml_triple :: proc(triple: rdf.Triple, data: rawptr) -> bool {
	return collect_rdfxml_quad(rdf.default_graph_quad(triple), data)
}

@(private) collect_jsonld_quad :: proc(quad: rdf.Quad, data: rawptr) -> bool {
	state := cast(^Batch_State)data
	if collect_err := dataset.add(&state.collector, quad); collect_err != .None {
		state.error = Error{code = .Graph_Collection_Error, detail = dataset.error_message(collect_err)}
		return false
	}
	return true
}

@(private) collect_jsonld_triple :: proc(triple: rdf.Triple, data: rawptr) -> bool {
	return collect_jsonld_quad(rdf.default_graph_quad(triple), data)
}

@(private) convert_to_rdfxml :: proc(reader: io.Reader, output: io.Writer, options: Options) -> Result {
	result: Result
	state := Batch_State{}
	if init_err := dataset.init(&state.collector, dataset.Options{max_quads = options.reader_limits.max_records}); init_err != .None {
		result.error = Error{code = .Graph_Collection_Error, detail = dataset.error_message(init_err)}
		return result
	}
	defer dataset.destroy(&state.collector)

	switch options.input {
	case .N_Triples:
		parsed := ntriples.parse_reader(reader, collect_rdfxml_triple, ntriples.Reader_Options{
			chunk_size = options.reader_limits.chunk_size,
			max_line_bytes = options.reader_limits.max_line_bytes,
			max_triples = u64(options.reader_limits.max_records),
		}, &state)
		result.bytes_read = parsed.bytes_read
		if state.error.code == .None && parsed.error.code != .None do set_batch_parse_error(&state, parsed.error.line, parsed.error.column, ntriples.parse_error_message(parsed.error.code), parsed.reader_error)
	case .N_Quads:
		parsed := nquads.parse_reader(reader, collect_rdfxml_quad, nquads.Reader_Options{
			chunk_size = options.reader_limits.chunk_size,
			max_line_bytes = options.reader_limits.max_line_bytes,
			max_quads = u64(options.reader_limits.max_records),
		}, &state)
		result.bytes_read = parsed.bytes_read
		if state.error.code == .None && parsed.error.code != .None do set_batch_parse_error(&state, parsed.error.line, parsed.error.column, nquads.parse_error_message(parsed.error.code), parsed.reader_error)
	case .Turtle:
		parsed := turtle.parse_reader(reader, collect_rdfxml_triple, turtle.Reader_Options{
			parse = turtle.Parse_Options{max_triples = options.reader_limits.max_records},
			chunk_size = options.reader_limits.chunk_size,
			max_statement_bytes = options.reader_limits.max_statement_bytes,
		}, &state)
		result.bytes_read = parsed.bytes_read
		if state.error.code == .None && parsed.error.code != .None do set_batch_parse_error(&state, parsed.error.line, parsed.error.column, turtle.parse_error_message(parsed.error.code), parsed.reader_error)
	case .JSON_LD:
		parsed := jsonld.parse_reader(reader, collect_rdfxml_quad, jsonld.Reader_Options{
			chunk_size = options.reader_limits.chunk_size,
			max_document_bytes = options.reader_limits.max_document_bytes,
			parse = jsonld.Options{max_quads = options.reader_limits.max_records},
		}, &state)
		result.bytes_read = parsed.bytes_read
		if state.error.code == .None && parsed.error.code != .None do set_batch_parse_error(&state, parsed.error.line, parsed.error.column, jsonld.parse_error_message(parsed.error.code), parsed.reader_error)
	case .RDF_XML:
		parsed := rdfxml.parse_reader(reader, collect_rdfxml_quad, rdfxml.Reader_Options{
			chunk_size = options.reader_limits.chunk_size,
			max_document_bytes = options.reader_limits.max_document_bytes,
			parse = rdfxml.Options{max_quads = options.reader_limits.max_records},
		}, &state)
		result.bytes_read = parsed.bytes_read
		if state.error.code == .None && parsed.error.code != .None do set_batch_parse_error(&state, parsed.error.line, parsed.error.column, rdfxml.parse_error_message(parsed.error.code), parsed.reader_error)
	case .TriG:
		parsed := trig.parse_reader(reader, collect_rdfxml_quad, trig.Reader_Options{
			chunk_size = options.reader_limits.chunk_size,
			max_document_bytes = options.reader_limits.max_document_bytes,
			parse = trig.Parse_Options{max_quads = options.reader_limits.max_records},
		}, &state)
		result.bytes_read = parsed.bytes_read
		if state.error.code == .None && parsed.error.code != .None do set_batch_parse_error(&state, parsed.error.line, parsed.error.column, trig.parse_error_message(parsed.error.code), parsed.reader_error)
	}
	if state.error.code != .None {
		result.error = state.error
		return result
	}

	triples := make([dynamic]rdf.Triple)
	defer delete(triples)
	for quad in state.collector.quads do append(&triples, rdf.triple(quad))
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	if write_err := rdfxml.write_triples(&builder, triples[:]); write_err != .None {
		result.error = Error{code = .Serialization_Error, detail = rdfxml.write_error_message(write_err)}
		return result
	}
	if output_err := write_all(output, strings.to_string(builder)); output_err != .None {
		result.error = Error{code = .Output_Write_Error, io_error = output_err}
		return result
	}
	result.statements = u64(len(triples))
	return result
}

// convert_to_jsonld retains a bounded complete dataset because expanded JSON-LD
// is one JSON document. It emits nothing until parsing and dataset
// serialization have both succeeded.
@(private) convert_to_jsonld :: proc(reader: io.Reader, output: io.Writer, options: Options) -> Result {
	result: Result
	state := Batch_State{}
	if init_err := dataset.init(&state.collector, dataset.Options{max_quads = options.reader_limits.max_records}); init_err != .None {
		result.error = Error{code = .Graph_Collection_Error, detail = dataset.error_message(init_err)}
		return result
	}
	defer dataset.destroy(&state.collector)

	switch options.input {
	case .N_Triples:
		parsed := ntriples.parse_reader(reader, collect_jsonld_triple, ntriples.Reader_Options{
			chunk_size = options.reader_limits.chunk_size,
			max_line_bytes = options.reader_limits.max_line_bytes,
			max_triples = u64(options.reader_limits.max_records),
		}, &state)
		result.bytes_read = parsed.bytes_read
		if state.error.code == .None && parsed.error.code != .None do set_batch_parse_error(&state, parsed.error.line, parsed.error.column, ntriples.parse_error_message(parsed.error.code), parsed.reader_error)
	case .N_Quads:
		parsed := nquads.parse_reader(reader, collect_jsonld_quad, nquads.Reader_Options{
			chunk_size = options.reader_limits.chunk_size,
			max_line_bytes = options.reader_limits.max_line_bytes,
			max_quads = u64(options.reader_limits.max_records),
		}, &state)
		result.bytes_read = parsed.bytes_read
		if state.error.code == .None && parsed.error.code != .None do set_batch_parse_error(&state, parsed.error.line, parsed.error.column, nquads.parse_error_message(parsed.error.code), parsed.reader_error)
	case .Turtle:
		parsed := turtle.parse_reader(reader, collect_jsonld_triple, turtle.Reader_Options{
			parse = turtle.Parse_Options{max_triples = options.reader_limits.max_records},
			chunk_size = options.reader_limits.chunk_size,
			max_statement_bytes = options.reader_limits.max_statement_bytes,
		}, &state)
		result.bytes_read = parsed.bytes_read
		if state.error.code == .None && parsed.error.code != .None do set_batch_parse_error(&state, parsed.error.line, parsed.error.column, turtle.parse_error_message(parsed.error.code), parsed.reader_error)
	case .JSON_LD:
		parsed := jsonld.parse_reader(reader, collect_jsonld_quad, jsonld.Reader_Options{
			chunk_size = options.reader_limits.chunk_size,
			max_document_bytes = options.reader_limits.max_document_bytes,
			parse = jsonld.Options{max_quads = options.reader_limits.max_records},
		}, &state)
		result.bytes_read = parsed.bytes_read
		if state.error.code == .None && parsed.error.code != .None do set_batch_parse_error(&state, parsed.error.line, parsed.error.column, jsonld.parse_error_message(parsed.error.code), parsed.reader_error)
	case .RDF_XML:
		parsed := rdfxml.parse_reader(reader, collect_jsonld_quad, rdfxml.Reader_Options{
			chunk_size = options.reader_limits.chunk_size,
			max_document_bytes = options.reader_limits.max_document_bytes,
			parse = rdfxml.Options{max_quads = options.reader_limits.max_records},
		}, &state)
		result.bytes_read = parsed.bytes_read
		if state.error.code == .None && parsed.error.code != .None do set_batch_parse_error(&state, parsed.error.line, parsed.error.column, rdfxml.parse_error_message(parsed.error.code), parsed.reader_error)
	case .TriG:
		parsed := trig.parse_reader(reader, collect_jsonld_quad, trig.Reader_Options{
			chunk_size = options.reader_limits.chunk_size,
			max_document_bytes = options.reader_limits.max_document_bytes,
			parse = trig.Parse_Options{max_quads = options.reader_limits.max_records},
		}, &state)
		result.bytes_read = parsed.bytes_read
		if state.error.code == .None && parsed.error.code != .None do set_batch_parse_error(&state, parsed.error.line, parsed.error.column, trig.parse_error_message(parsed.error.code), parsed.reader_error)
	}
	if state.error.code != .None {
		result.error = state.error
		return result
	}

	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	if serialize_err := jsonld.serialize(&builder, state.collector.quads[:], jsonld.Serialize_Options{max_quads = options.reader_limits.max_records}); serialize_err != .None {
		result.error = Error{code = .Serialization_Error, detail = jsonld.serialize_error_message(serialize_err)}
		return result
	}
	if output_err := write_all(output, strings.to_string(builder)); output_err != .None {
		result.error = Error{code = .Output_Write_Error, io_error = output_err}
		return result
	}
	result.statements = u64(len(state.collector.quads))
	return result
}

// convert parses reader with the selected source syntax. Most targets write
// each valid RDF statement immediately. RDF/XML is the intentional exception:
// it retains one max_records-bounded default graph, then writes one complete
// document only after parsing succeeds. Named graphs can target N-Quads or
// TriG; other requested conversions fail before a named statement is written.
// Reader ownership remains with the caller, as does output flushing and closing.
convert :: proc(reader: io.Reader, output: io.Writer, options: Options) -> Result {
	result: Result
	if options.output != .N_Triples && options.output != .N_Quads && options.output != .Turtle && options.output != .JSON_LD && options.output != .RDF_XML && options.output != .TriG {
		result.error.code = .Unsupported_Output_Format
		return result
	}
	if options.input != .N_Triples && options.input != .N_Quads && options.input != .Turtle && options.input != .JSON_LD && options.input != .RDF_XML && options.input != .TriG {
		result.error.code = .Unsupported_Input_Format
		return result
	}
	if !valid_reader_limits(options.reader_limits) {
		result.error.code = .Invalid_Reader_Limits
		return result
	}
	if options.output == .RDF_XML {
		if options.reader_limits.max_records == 0 {
			result.error.code = .RDF_XML_Record_Limit_Required
			return result
		}
		return convert_to_rdfxml(reader, output, options)
	}
	if options.output == .JSON_LD {
		if options.reader_limits.max_records == 0 {
			result.error.code = .JSON_LD_Record_Limit_Required
			return result
		}
		return convert_to_jsonld(reader, output, options)
	}

	state := State{
		output = output,
		format = options.output,
		turtle_options = turtle.Writer_Options{prefixes = options.turtle_prefixes},
		builder = strings.builder_make(),
	}
	defer strings.builder_destroy(&state.builder)

	if options.output == .Turtle || options.output == .TriG {
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
	case .RDF_XML:
		parsed := rdfxml.parse_reader(reader, write_destination_quad, rdfxml.Reader_Options{
			chunk_size = options.reader_limits.chunk_size,
			max_document_bytes = options.reader_limits.max_document_bytes,
			parse = rdfxml.Options{max_quads = options.reader_limits.max_records},
		}, &state)
		result.bytes_read = parsed.bytes_read
		if state.error.code == .None && parsed.error.code != .None {
			set_parse_error(&state, parsed.error.line, parsed.error.column, rdfxml.parse_error_message(parsed.error.code), parsed.reader_error)
		}
	case .TriG:
		parsed := trig.parse_reader(reader, write_destination_quad, trig.Reader_Options{
			chunk_size = options.reader_limits.chunk_size,
			max_document_bytes = options.reader_limits.max_document_bytes,
			parse = trig.Parse_Options{max_quads = options.reader_limits.max_records},
		}, &state)
		result.bytes_read = parsed.bytes_read
		if state.error.code == .None && parsed.error.code != .None {
			set_parse_error(&state, parsed.error.line, parsed.error.column, trig.parse_error_message(parsed.error.code), parsed.reader_error)
		}
	}
	result.error = state.error
	result.statements = state.statements
	return result
}
