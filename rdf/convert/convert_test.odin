package convert

import "core:strings"
import "core:testing"
import "core:io"
import turtle "../turtle"

@(private) convert_text :: proc(input: string, options: Options) -> (Result, string) {
	input_state: strings.Reader
	reader := strings.to_reader(&input_state, input)
	output := strings.builder_make()
	defer strings.builder_destroy(&output)
	result := convert(reader, strings.to_writer(&output), options)
	return result, strings.to_string(output)
}

@(test)
test_converts_turtle_to_canonical_ntriples :: proc(t: ^testing.T) {
	input := `@prefix ex: <https://example.com/> .
ex:alice ex:name "Alice"@en .`
	result, output := convert_text(input, Options{input = .Turtle, output = .N_Triples})
	testing.expect_value(t, result.error.code, Error_Code.None)
	testing.expect_value(t, result.statements, u64(1))
	testing.expect_value(t, result.bytes_read, u64(len(input)))
	testing.expect_value(t, output, "<https://example.com/alice> <https://example.com/name> \"Alice\"@en .\n")
}

@(test)
test_converts_ntriples_to_turtle_with_explicit_prefixes :: proc(t: ^testing.T) {
	input := "<https://example.com/alice> <https://example.com/vocab/name> \"Alice\"^^<https://example.com/vocab/Name> .\n"
	prefixes := []turtle.Prefix{
		{label = "ex", namespace = "https://example.com/"},
		{label = "v", namespace = "https://example.com/vocab/"},
	}
	result, output := convert_text(input, Options{input = .N_Triples, output = .Turtle, turtle_prefixes = prefixes})
	testing.expect_value(t, result.error.code, Error_Code.None)
	testing.expect_value(t, result.statements, u64(1))
	testing.expect_value(t, output, `@prefix ex: <https://example.com/> .
@prefix v: <https://example.com/vocab/> .
ex:alice v:name "Alice"^^v:Name .
`)
}

@(test)
test_converts_default_graph_nquads_to_ntriples :: proc(t: ^testing.T) {
	input := "<urn:s> <urn:p> <urn:o> .\n"
	result, output := convert_text(input, Options{input = .N_Quads, output = .N_Triples})
	testing.expect_value(t, result.error.code, Error_Code.None)
	testing.expect_value(t, result.statements, u64(1))
	testing.expect_value(t, output, input)
}

@(test)
test_preserves_named_graph_when_nquads_is_the_target :: proc(t: ^testing.T) {
	input := "<urn:s> <urn:p> <urn:o> <urn:g> .\n"
	result, output := convert_text(input, Options{input = .N_Quads, output = .N_Quads})
	testing.expect_value(t, result.error.code, Error_Code.None)
	testing.expect_value(t, result.statements, u64(1))
	testing.expect_value(t, output, input)
}

@(test)
test_converts_triple_syntax_to_default_graph_nquads :: proc(t: ^testing.T) {
	input := "<urn:s> <urn:p> <urn:o> .\n"
	result, output := convert_text(input, Options{input = .N_Triples, output = .N_Quads})
	testing.expect_value(t, result.error.code, Error_Code.None)
	testing.expect_value(t, result.statements, u64(1))
	testing.expect_value(t, output, input)
}

@(test)
test_rejects_named_graph_before_losing_it :: proc(t: ^testing.T) {
	input := "<urn:s> <urn:p> <urn:o> <urn:g> .\n"
	result, output := convert_text(input, Options{input = .N_Quads, output = .Turtle})
	testing.expect_value(t, result.error.code, Error_Code.Named_Graph_Not_Supported)
	testing.expect_value(t, result.statements, u64(0))
	testing.expect_value(t, output, "")
}

@(test)
test_reports_source_location_and_stable_detail :: proc(t: ^testing.T) {
	input := "<urn:s> <urn:p> <urn:o> .\n<urn:broken> <urn:p>"
	result, output := convert_text(input, Options{input = .N_Triples, output = .N_Quads})
	testing.expect_value(t, result.error.code, Error_Code.Source_Parse_Error)
	testing.expect_value(t, result.error.line, 2)
	testing.expect_value(t, result.error.detail, "unexpected end of input")
	testing.expect_value(t, result.statements, u64(1))
	testing.expect_value(t, output, "<urn:s> <urn:p> <urn:o> .\n")
}

@(test)
test_applies_max_records_to_every_source_syntax :: proc(t: ^testing.T) {
	ntriples_input := "<urn:a> <urn:p> <urn:o> .\n<urn:b> <urn:p> <urn:o> .\n"
	ntriples_result, ntriples_output := convert_text(ntriples_input, Options{
		input = .N_Triples,
		output = .N_Quads,
		reader_limits = {max_records = 1},
	})
	testing.expect_value(t, ntriples_result.error.code, Error_Code.Source_Parse_Error)
	testing.expect_value(t, ntriples_result.error.detail, "triple limit reached")
	testing.expect_value(t, ntriples_result.statements, u64(1))
	testing.expect_value(t, ntriples_output, "<urn:a> <urn:p> <urn:o> .\n")

	nquads_input := "<urn:a> <urn:p> <urn:o> .\n<urn:b> <urn:p> <urn:o> .\n"
	nquads_result, nquads_output := convert_text(nquads_input, Options{
		input = .N_Quads,
		output = .N_Triples,
		reader_limits = {max_records = 1},
	})
	testing.expect_value(t, nquads_result.error.code, Error_Code.Source_Parse_Error)
	testing.expect_value(t, nquads_result.error.detail, "quad limit reached")
	testing.expect_value(t, nquads_result.statements, u64(1))
	testing.expect_value(t, nquads_output, "<urn:a> <urn:p> <urn:o> .\n")

	turtle_input := "<urn:a> <urn:p> <urn:o> .\n<urn:b> <urn:p> <urn:o> .\n"
	turtle_result, turtle_output := convert_text(turtle_input, Options{
		input = .Turtle,
		output = .N_Triples,
		reader_limits = {max_records = 1},
	})
	testing.expect_value(t, turtle_result.error.code, Error_Code.Source_Parse_Error)
	testing.expect_value(t, turtle_result.error.detail, "triple limit reached")
	testing.expect_value(t, turtle_result.statements, u64(1))
	testing.expect_value(t, turtle_output, "<urn:a> <urn:p> <urn:o> .\n")
}

@(test)
test_applies_syntax_specific_input_bounds :: proc(t: ^testing.T) {
	line_result, line_output := convert_text("<urn:s> <urn:p> <urn:o> .\n", Options{
		input = .N_Triples,
		output = .N_Quads,
		reader_limits = {max_line_bytes = 8},
	})
	testing.expect_value(t, line_result.error.code, Error_Code.Source_Parse_Error)
	testing.expect_value(t, line_result.error.detail, "line exceeds configured limit")
	testing.expect_value(t, line_output, "")

	statement_result, statement_output := convert_text("<urn:s> <urn:p> <urn:o> .\n", Options{
		input = .Turtle,
		output = .N_Triples,
		reader_limits = {max_statement_bytes = 8},
	})
	testing.expect_value(t, statement_result.error.code, Error_Code.Source_Parse_Error)
	testing.expect_value(t, statement_result.error.detail, "statement exceeds configured limit")
	testing.expect_value(t, statement_output, "")
}

@(test)
test_rejects_negative_reader_limits_before_io :: proc(t: ^testing.T) {
	result, output := convert_text("<urn:s> <urn:p> <urn:o> .\n", Options{
		input = .N_Triples,
		output = .N_Quads,
		reader_limits = {max_records = -1},
	})
	testing.expect_value(t, result.error.code, Error_Code.Invalid_Reader_Limits)
	testing.expect_value(t, output, "")
}

@(test)
test_rejects_invalid_turtle_prefixes_before_reading_or_writing :: proc(t: ^testing.T) {
	result, output := convert_text("<urn:s> <urn:p> <urn:o> .", Options{
		input = .N_Triples,
		output = .Turtle,
		turtle_prefixes = []turtle.Prefix{{label = "bad.", namespace = "urn:example:"}},
	})
	testing.expect_value(t, result.error.code, Error_Code.Invalid_Turtle_Prefixes)
	testing.expect_value(t, result.error.detail, "invalid Turtle prefix label")
	testing.expect_value(t, result.statements, u64(0))
	testing.expect_value(t, output, "")
}

@(private) failing_writer_proc :: proc(_: rawptr, mode: io.Stream_Mode, _: []byte, _: i64, _: io.Seek_From) -> (i64, io.Error) {
	if mode == .Write do return 0, .Unknown
	return 0, .Unsupported
}

@(test)
test_preserves_writer_failure_over_parser_stopped_result :: proc(t: ^testing.T) {
	input_state: strings.Reader
	reader := strings.to_reader(&input_state, "<urn:s> <urn:p> <urn:o> .\n")
	writer := io.Writer{procedure = failing_writer_proc}
	result := convert(reader, writer, Options{input = .N_Triples, output = .N_Quads})
	testing.expect_value(t, result.error.code, Error_Code.Output_Write_Error)
	testing.expect_value(t, result.error.io_error, io.Error.Unknown)
	testing.expect_value(t, result.statements, u64(0))
}

@(test)
test_error_messages_are_stable :: proc(t: ^testing.T) {
	messages := [Error_Code]string{
		.None                      = "no error",
		.Unsupported_Input_Format  = "unsupported input format",
		.Unsupported_Output_Format = "unsupported output format",
		.Invalid_Reader_Limits     = "reader limits must not be negative",
		.Invalid_Turtle_Prefixes   = "invalid Turtle prefix configuration",
		.Source_Parse_Error        = "source parse error",
		.Named_Graph_Not_Supported = "named graphs cannot be represented by the output format",
		.Serialization_Error       = "output serialization error",
		.Output_Write_Error        = "output write error",
	}
	for code in Error_Code do testing.expect_value(t, error_message(code), messages[code])
}
