package main

import "core:testing"
import "core:io"
import "core:os"
import "core:strings"
import convert "../../rdf/convert"
import turtle "../../rdf/turtle"

@(private) write_test_file :: proc(path, text: string) -> os.Error {
	file, create_err := os.create(path)
	if create_err != nil do return create_err
	defer os.close(file)
	count, write_err := os.write(file, transmute([]byte)text)
	if write_err != nil do return write_err
	if count != len(text) do return io.Error.Short_Write
	return nil
}

@(private) read_test_file :: proc(path: string, buffer: ^[256]byte) -> (string, os.Error) {
	file, open_err := os.open(path)
	if open_err != nil do return "", open_err
	defer os.close(file)
	count, read_err := os.read(file, buffer^[:])
	if read_err != nil && read_err != .EOF do return "", read_err
	return string(buffer^[:count]), nil
}

@(test)
test_parses_convert_command_with_repeated_prefixes :: proc(t: ^testing.T) {
	args := []string{
		"convert", "input.ttl", "--from", "ttl", "--to=ntriples", "--output", "output.nt",
		"--prefix", "ex=https://example.com/", "--prefix", "=urn:example:",
	}
	options, err := parse_convert_args(args)
	defer delete(options.prefixes)
	testing.expect_value(t, err.code, Command_Error_Code.None)
	testing.expect_value(t, options.input_path, "input.ttl")
	testing.expect_value(t, options.output_path, "output.nt")
	testing.expect_value(t, options.input_format, convert.Format.Turtle)
	testing.expect_value(t, options.output_format, convert.Format.N_Triples)
	testing.expect_value(t, len(options.prefixes), 2)
	testing.expect_value(t, options.prefixes[0].label, "ex")
	testing.expect_value(t, options.prefixes[1].label, "")
}

@(test)
test_parses_format_command_with_prefix_policy :: proc(t: ^testing.T) {
	args := []string{
		"format", "input.ttl", "--output=output.ttl", "--prefix", "ex=https://example.com/", "--max-triples", "20", "--no-infer-prefixes",
	}
	options, err := parse_format_command_args(args)
	defer delete(options.prefixes)
	testing.expect_value(t, err.code, Command_Error_Code.None)
	testing.expect_value(t, options.input_path, "input.ttl")
	testing.expect_value(t, options.output_path, "output.ttl")
	testing.expect(t, !options.infer_prefixes)
	testing.expect_value(t, options.max_triples, 20)
	testing.expect_value(t, len(options.prefixes), 1)
	testing.expect_value(t, options.prefixes[0].label, "ex")

	missing_input_options, missing_input := parse_format_command_args([]string{"format"})
	defer delete(missing_input_options.prefixes)
	testing.expect_value(t, missing_input.code, Command_Error_Code.Missing_Input)

	invalid_limit_options, invalid_limit := parse_format_command_args([]string{"format", "input.ttl", "--max-triples=0"})
	defer delete(invalid_limit_options.prefixes)
	testing.expect_value(t, invalid_limit.code, Command_Error_Code.Invalid_Max_Triples)

	signed_limit_options, signed_limit := parse_format_command_args([]string{"format", "input.ttl", "--max-triples=+1"})
	defer delete(signed_limit_options.prefixes)
	testing.expect_value(t, signed_limit.code, Command_Error_Code.Invalid_Max_Triples)
}

@(test)
test_requires_an_explicit_input_and_formats :: proc(t: ^testing.T) {
	options, missing_input := parse_convert_args([]string{"convert", "--from", "ntriples", "--to", "turtle"})
	defer delete(options.prefixes)
	testing.expect_value(t, missing_input.code, Command_Error_Code.Missing_Input)

	missing_from_options, missing_from := parse_convert_args([]string{"convert", "-", "--to", "turtle"})
	defer delete(missing_from_options.prefixes)
	testing.expect_value(t, missing_from.code, Command_Error_Code.Missing_From)

	missing_to_options, missing_to := parse_convert_args([]string{"convert", "-", "--from", "ntriples"})
	defer delete(missing_to_options.prefixes)
	testing.expect_value(t, missing_to.code, Command_Error_Code.Missing_To)
}

@(test)
test_rejects_invalid_arguments_without_guessing :: proc(t: ^testing.T) {
	options, invalid_format := parse_convert_args([]string{"convert", "-", "--from", "jsonld", "--to", "turtle"})
	defer delete(options.prefixes)
	testing.expect_value(t, invalid_format.code, Command_Error_Code.Invalid_Format)

	invalid_prefix_options, invalid_prefix := parse_convert_args([]string{"convert", "-", "--from", "ntriples", "--to", "turtle", "--prefix", "missing-separator"})
	defer delete(invalid_prefix_options.prefixes)
	testing.expect_value(t, invalid_prefix.code, Command_Error_Code.Invalid_Prefix)

	same_path_options, same_path := parse_convert_args([]string{"convert", "graph.nt", "--from", "ntriples", "--to", "turtle", "--output", "graph.nt"})
	defer delete(same_path_options.prefixes)
	testing.expect_value(t, same_path.code, Command_Error_Code.Same_Input_Output)
}

@(test)
test_file_output_replaces_only_after_successful_conversion :: proc(t: ^testing.T) {
	target :: "odin-rdf-cli-success-test.nt"
	temporary :: "odin-rdf-cli-success-test.nt.odin-rdf.tmp"
	defer {
		_ = os.remove(target)
		_ = os.remove(temporary)
	}
	testing.expect(t, write_test_file(target, "previous\n") == nil)
	input_state: strings.Reader
	input := strings.to_reader(&input_state, "<urn:s> <urn:p> <urn:o> .\n")
	result := convert_to_file(input, target, convert.Options{input = .N_Triples, output = .N_Quads})
	testing.expect_value(t, result.error.code, convert.Error_Code.None)
	buffer: [256]byte
	contents, read_err := read_test_file(target, &buffer)
	testing.expect(t, read_err == nil)
	testing.expect_value(t, contents, "<urn:s> <urn:p> <urn:o> .\n")
	testing.expect(t, !os.exists(temporary))
}

@(test)
test_file_output_preserves_existing_target_after_conversion_failure :: proc(t: ^testing.T) {
	target :: "odin-rdf-cli-failure-test.nt"
	temporary :: "odin-rdf-cli-failure-test.nt.odin-rdf.tmp"
	defer {
		_ = os.remove(target)
		_ = os.remove(temporary)
	}
	testing.expect(t, write_test_file(target, "previous\n") == nil)
	input_state: strings.Reader
	input := strings.to_reader(&input_state, "<urn:s> <urn:p> <urn:o> <urn:g> .\n")
	result := convert_to_file(input, target, convert.Options{input = .N_Quads, output = .N_Triples})
	testing.expect_value(t, result.error.code, convert.Error_Code.Named_Graph_Not_Supported)
	buffer: [256]byte
	contents, read_err := read_test_file(target, &buffer)
	testing.expect(t, read_err == nil)
	testing.expect_value(t, contents, "previous\n")
	testing.expect(t, !os.exists(temporary))
}

@(test)
test_format_file_output_is_grouped_and_replaces_after_success :: proc(t: ^testing.T) {
	input_path :: "odin-rdf-cli-format-input.ttl"
	target :: "odin-rdf-cli-format-output.ttl"
	temporary :: "odin-rdf-cli-format-output.ttl.odin-rdf.tmp"
	defer {
		_ = os.remove(input_path)
		_ = os.remove(target)
		_ = os.remove(temporary)
	}
	input := `<https://example.com/alice> <https://example.com/name> "Alice" .
<https://example.com/alice> <https://example.com/knows> <https://example.com/bob> .
`
	testing.expect(t, write_test_file(input_path, input) == nil)
	testing.expect(t, write_test_file(target, "previous\n") == nil)
	options := Format_Command_Options{
		input_path = input_path,
		output_path = target,
		prefixes = make([dynamic]turtle.Prefix),
		infer_prefixes = true,
	}
	defer delete(options.prefixes)
	testing.expect_value(t, run_format(options), 0)
	buffer: [256]byte
	contents, read_err := read_test_file(target, &buffer)
	testing.expect(t, read_err == nil)
	expected := `@prefix ns1: <https://example.com/> .

ns1:alice ns1:knows ns1:bob ;
    ns1:name "Alice" .
`
	testing.expect_value(t, contents, expected)
	testing.expect(t, !os.exists(temporary))
}

@(test)
test_format_file_output_preserves_existing_target_after_parse_failure :: proc(t: ^testing.T) {
	input_path :: "odin-rdf-cli-format-invalid-input.ttl"
	target :: "odin-rdf-cli-format-invalid-output.ttl"
	temporary :: "odin-rdf-cli-format-invalid-output.ttl.odin-rdf.tmp"
	defer {
		_ = os.remove(input_path)
		_ = os.remove(target)
		_ = os.remove(temporary)
	}
	testing.expect(t, write_test_file(input_path, `<https://example.com/s> <https://example.com/p> .\n`) == nil)
	testing.expect(t, write_test_file(target, "previous\n") == nil)
	options := Format_Command_Options{
		input_path = input_path,
		output_path = target,
		prefixes = make([dynamic]turtle.Prefix),
		infer_prefixes = true,
	}
	defer delete(options.prefixes)
	testing.expect_value(t, run_format(options), 1)
	buffer: [256]byte
	contents, read_err := read_test_file(target, &buffer)
	testing.expect(t, read_err == nil)
	testing.expect_value(t, contents, "previous\n")
	testing.expect(t, !os.exists(temporary))
}

@(test)
test_format_file_output_preserves_existing_target_after_triple_limit :: proc(t: ^testing.T) {
	input_path :: "odin-rdf-cli-format-limit-input.ttl"
	target :: "odin-rdf-cli-format-limit-output.ttl"
	temporary :: "odin-rdf-cli-format-limit-output.ttl.odin-rdf.tmp"
	defer {
		_ = os.remove(input_path)
		_ = os.remove(target)
		_ = os.remove(temporary)
	}
	input := `<https://example.com/a> <https://example.com/p> <https://example.com/o> .
<https://example.com/b> <https://example.com/p> <https://example.com/o> .
`
	testing.expect(t, write_test_file(input_path, input) == nil)
	testing.expect(t, write_test_file(target, "previous\n") == nil)
	options := Format_Command_Options{
		input_path = input_path,
		output_path = target,
		prefixes = make([dynamic]turtle.Prefix),
		infer_prefixes = true,
		max_triples = 1,
	}
	defer delete(options.prefixes)
	testing.expect_value(t, run_format(options), 1)
	buffer: [256]byte
	contents, read_err := read_test_file(target, &buffer)
	testing.expect(t, read_err == nil)
	testing.expect_value(t, contents, "previous\n")
	testing.expect(t, !os.exists(temporary))
}

@(test)
test_command_error_messages_are_stable :: proc(t: ^testing.T) {
	messages := [Command_Error_Code]string{
		.None                 = "no error",
		.Missing_Command      = "expected a command",
		.Unknown_Command      = "unknown command",
		.Missing_Option_Value = "option requires a value",
		.Unknown_Option       = "unknown option",
		.Missing_Input        = "expected an input path or - for standard input",
		.Extra_Input          = "only one input path is supported",
		.Missing_From         = "--from is required",
		.Missing_To           = "--to is required",
		.Invalid_Format       = "unsupported RDF syntax",
		.Invalid_Prefix       = "--prefix must use LABEL=NAMESPACE",
		.Invalid_Max_Triples  = "--max-triples must be a positive decimal integer",
		.Same_Input_Output    = "input and output paths must differ",
	}
	for code in Command_Error_Code do testing.expect_value(t, command_error_message(code), messages[code])
}
