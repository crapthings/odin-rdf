package main

import "core:testing"
import "core:io"
import "core:os"
import "core:strings"
import canon "../../rdf/canon"
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
		"--max-records", "10", "--max-line-bytes=1024", "--max-statement-bytes", "2048", "--max-document-bytes", "4096",
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
	testing.expect_value(t, options.reader_limits.max_records, 10)
	testing.expect_value(t, options.reader_limits.max_line_bytes, 1024)
	testing.expect_value(t, options.reader_limits.max_statement_bytes, 2048)
	testing.expect_value(t, options.reader_limits.max_document_bytes, 4096)
}

@(test)
test_parses_context_directed_jsonld_conversion :: proc(t: ^testing.T) {
	options, err := parse_convert_args([]string{"convert", "input.nt", "--to", "jsonld", "--context", "context.jsonld", "--max-records", "10"})
	defer delete(options.prefixes)
	testing.expect_value(t, err.code, Command_Error_Code.None)
	testing.expect_value(t, options.context_path, "context.jsonld")
	testing.expect_value(t, options.output_format, convert.Format.JSON_LD)
	testing.expect_value(t, options.reader_limits.max_records, 10)

	wrong_options, wrong_err := parse_convert_args([]string{"convert", "input.nt", "--to", "nquads", "--context=context.jsonld"})
	defer delete(wrong_options.prefixes)
	testing.expect_value(t, wrong_err.code, Command_Error_Code.Context_Requires_JSONLD)

	conflict_options, conflict_err := parse_convert_args([]string{"convert", "input.nt", "--to", "jsonld", "--context", "context.jsonld", "--output", "context.jsonld", "--max-records", "10"})
	defer delete(conflict_options.prefixes)
	testing.expect_value(t, conflict_err.code, Command_Error_Code.Same_Input_Output)
}

@(test)
test_context_directed_jsonld_conversion_is_atomic :: proc(t: ^testing.T) {
	input_path :: "odin-rdf-cli-compact-input.nt"
	context_path :: "odin-rdf-cli-compact-context.jsonld"
	target_path :: "odin-rdf-cli-compact-output.jsonld"
	temporary_path :: "odin-rdf-cli-compact-output.jsonld.odin-rdf.tmp"
	defer os.remove(input_path)
	defer os.remove(context_path)
	defer os.remove(target_path)
	defer os.remove(temporary_path)
	testing.expect(t, write_test_file(input_path, `<https://example.test/alice> <https://example.test/name> "Alice" .
`) == nil)
	testing.expect(t, write_test_file(context_path, `{"@context":{"name":"https://example.test/name"}}`) == nil)
	options, parse_err := parse_convert_args([]string{"convert", input_path, "--to", "jsonld", "--context", context_path, "--output", target_path, "--max-records", "10"})
	defer delete(options.prefixes)
	testing.expect_value(t, parse_err.code, Command_Error_Code.None)
	testing.expect_value(t, run_convert(options), 0)
	buffer: [256]byte
	output, read_err := read_test_file(target_path, &buffer)
	testing.expect(t, read_err == nil)
	testing.expect(t, strings.contains(output, `"name": "Alice"`))
	testing.expect(t, !os.exists(temporary_path))

	testing.expect(t, write_test_file(target_path, "previous\n") == nil)
	testing.expect(t, write_test_file(context_path, `{`) == nil)
	testing.expect_value(t, run_convert(options), 1)
	output, read_err = read_test_file(target_path, &buffer)
	testing.expect(t, read_err == nil)
	testing.expect_value(t, output, "previous\n")
	testing.expect(t, !os.exists(temporary_path))
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
	testing.expect_value(t, options.input_format, convert.Format.Turtle)
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

	trig_options, trig_err := parse_format_command_args([]string{"format", "input.trig", "--max-quads", "20"})
	defer delete(trig_options.prefixes)
	testing.expect_value(t, trig_err.code, Command_Error_Code.None)
	testing.expect_value(t, trig_options.input_format, convert.Format.TriG)
	testing.expect_value(t, trig_options.max_quads, 20)

	stdin_options, stdin_err := parse_format_command_args([]string{"format", "-", "--from", "trig"})
	defer delete(stdin_options.prefixes)
	testing.expect_value(t, stdin_err.code, Command_Error_Code.None)
	testing.expect_value(t, stdin_options.input_format, convert.Format.TriG)

	invalid_quad_options, invalid_quad := parse_format_command_args([]string{"format", "input.trig", "--max-quads=0"})
	defer delete(invalid_quad_options.prefixes)
	testing.expect_value(t, invalid_quad.code, Command_Error_Code.Invalid_Max_Quads)

	wrong_limit_options, wrong_limit := parse_format_command_args([]string{"format", "input.trig", "--max-triples", "1"})
	defer delete(wrong_limit_options.prefixes)
	testing.expect_value(t, wrong_limit.code, Command_Error_Code.Incompatible_Format_Limit)
}

@(test)
test_infers_formats_from_canonical_file_extensions :: proc(t: ^testing.T) {
	options, err := parse_convert_args([]string{"convert", "input.ttl", "--output", "output.nq"})
	defer delete(options.prefixes)
	testing.expect_value(t, err.code, Command_Error_Code.None)
	testing.expect_value(t, options.input_format, convert.Format.Turtle)
	testing.expect_value(t, options.output_format, convert.Format.N_Quads)

	override_options, override_err := parse_convert_args([]string{"convert", "input.nt", "--from", "turtle", "--to", "nquads", "--output", "output.ttl"})
	defer delete(override_options.prefixes)
	testing.expect_value(t, override_err.code, Command_Error_Code.None)
	testing.expect_value(t, override_options.input_format, convert.Format.Turtle)
	testing.expect_value(t, override_options.output_format, convert.Format.N_Quads)

	jsonld_options, jsonld_err := parse_convert_args([]string{"convert", "input.jsonld", "--output", "output.nq"})
	defer delete(jsonld_options.prefixes)
	testing.expect_value(t, jsonld_err.code, Command_Error_Code.None)
	testing.expect_value(t, jsonld_options.input_format, convert.Format.JSON_LD)
	testing.expect_value(t, jsonld_options.output_format, convert.Format.N_Quads)

	jsonld_output_options, jsonld_output_err := parse_convert_args([]string{"convert", "input.trig", "--output", "output.jsonld", "--max-records", "20"})
	defer delete(jsonld_output_options.prefixes)
	testing.expect_value(t, jsonld_output_err.code, Command_Error_Code.None)
	testing.expect_value(t, jsonld_output_options.input_format, convert.Format.TriG)
	testing.expect_value(t, jsonld_output_options.output_format, convert.Format.JSON_LD)
	testing.expect_value(t, jsonld_output_options.reader_limits.max_records, 20)

	rdfxml_options, rdfxml_err := parse_convert_args([]string{"convert", "input.rdf", "--output", "output.nt"})
	defer delete(rdfxml_options.prefixes)
	testing.expect_value(t, rdfxml_err.code, Command_Error_Code.None)
	testing.expect_value(t, rdfxml_options.input_format, convert.Format.RDF_XML)
	testing.expect_value(t, rdfxml_options.output_format, convert.Format.N_Triples)

	trig_options, trig_err := parse_convert_args([]string{"convert", "input.trig", "--output", "output.nq"})
	defer delete(trig_options.prefixes)
	testing.expect_value(t, trig_err.code, Command_Error_Code.None)
	testing.expect_value(t, trig_options.input_format, convert.Format.TriG)
	testing.expect_value(t, trig_options.output_format, convert.Format.N_Quads)
}

@(test)
test_requires_an_explicit_format_when_it_cannot_be_inferred :: proc(t: ^testing.T) {
	options, missing_input := parse_convert_args([]string{"convert", "--from", "ntriples", "--to", "turtle"})
	defer delete(options.prefixes)
	testing.expect_value(t, missing_input.code, Command_Error_Code.Missing_Input)

	missing_from_options, missing_from := parse_convert_args([]string{"convert", "-", "--to", "turtle"})
	defer delete(missing_from_options.prefixes)
	testing.expect_value(t, missing_from.code, Command_Error_Code.Cannot_Infer_Input_Format)

	missing_to_options, missing_to := parse_convert_args([]string{"convert", "input.nt"})
	defer delete(missing_to_options.prefixes)
	testing.expect_value(t, missing_to.code, Command_Error_Code.Cannot_Infer_Output_Format)

	unknown_input_options, unknown_input := parse_convert_args([]string{"convert", "input.unknown", "--to", "ntriples"})
	defer delete(unknown_input_options.prefixes)
	testing.expect_value(t, unknown_input.code, Command_Error_Code.Cannot_Infer_Input_Format)

	unknown_output_options, unknown_output := parse_convert_args([]string{"convert", "input.nt", "--output", "output.unknown"})
	defer delete(unknown_output_options.prefixes)
	testing.expect_value(t, unknown_output.code, Command_Error_Code.Cannot_Infer_Output_Format)
}

@(test)
test_convert_command_infers_file_formats_end_to_end :: proc(t: ^testing.T) {
	input_path :: "odin-rdf-cli-inferred-input.ttl"
	target :: "odin-rdf-cli-inferred-output.nq"
	temporary :: "odin-rdf-cli-inferred-output.nq.odin-rdf.tmp"
	defer {
		_ = os.remove(input_path)
		_ = os.remove(target)
		_ = os.remove(temporary)
	}
	testing.expect(t, write_test_file(input_path, "<urn:s> <urn:p> <urn:o> .\n") == nil)
	options, err := parse_convert_args([]string{"convert", input_path, "--output", target})
	defer delete(options.prefixes)
	testing.expect_value(t, err.code, Command_Error_Code.None)
	testing.expect_value(t, run_convert(options), 0)
	buffer: [256]byte
	contents, read_err := read_test_file(target, &buffer)
	testing.expect(t, read_err == nil)
	testing.expect_value(t, contents, "<urn:s> <urn:p> <urn:o> .\n")
	testing.expect(t, !os.exists(temporary))
}

@(test)
test_convert_command_writes_bounded_rdfxml_atomically :: proc(t: ^testing.T) {
	input_path :: "odin-rdf-cli-rdfxml-input.nt"
	target :: "odin-rdf-cli-rdfxml-output.rdf"
	temporary :: "odin-rdf-cli-rdfxml-output.rdf.odin-rdf.tmp"
	defer {
		_ = os.remove(input_path)
		_ = os.remove(target)
		_ = os.remove(temporary)
	}
	testing.expect(t, write_test_file(input_path, "<https://example.test/s> <https://example.test/p> \"value\" .\n") == nil)
	testing.expect(t, write_test_file(target, "previous\n") == nil)
	options, err := parse_convert_args([]string{"convert", input_path, "--output", target, "--max-records", "1"})
	defer delete(options.prefixes)
	testing.expect_value(t, err.code, Command_Error_Code.None)
	testing.expect_value(t, options.output_format, convert.Format.RDF_XML)
	testing.expect_value(t, run_convert(options), 0)
	buffer: [256]byte
	contents, read_err := read_test_file(target, &buffer)
	testing.expect(t, read_err == nil)
	testing.expect(t, strings.contains(contents, `<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">`))
	testing.expect(t, strings.contains(contents, `<ns:p xmlns:ns="https://example.test/">value</ns:p>`))
	testing.expect(t, !os.exists(temporary))
}

@(test)
test_rejects_invalid_arguments_without_guessing :: proc(t: ^testing.T) {
	options, invalid_format := parse_convert_args([]string{"convert", "-", "--from", "rdfxmlx", "--to", "turtle"})
	defer delete(options.prefixes)
	testing.expect_value(t, invalid_format.code, Command_Error_Code.Invalid_Format)

	invalid_prefix_options, invalid_prefix := parse_convert_args([]string{"convert", "-", "--from", "ntriples", "--to", "turtle", "--prefix", "missing-separator"})
	defer delete(invalid_prefix_options.prefixes)
	testing.expect_value(t, invalid_prefix.code, Command_Error_Code.Invalid_Prefix)

	invalid_record_options, invalid_record := parse_convert_args([]string{"convert", "-", "--from", "ntriples", "--to", "nquads", "--max-records", "0"})
	defer delete(invalid_record_options.prefixes)
	testing.expect_value(t, invalid_record.code, Command_Error_Code.Invalid_Max_Records)

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
test_file_output_preserves_existing_target_after_conversion_record_limit :: proc(t: ^testing.T) {
	target :: "odin-rdf-cli-limit-test.nt"
	temporary :: "odin-rdf-cli-limit-test.nt.odin-rdf.tmp"
	defer {
		_ = os.remove(target)
		_ = os.remove(temporary)
	}
	testing.expect(t, write_test_file(target, "previous\n") == nil)
	input_state: strings.Reader
	input := strings.to_reader(&input_state, "<urn:a> <urn:p> <urn:o> .\n<urn:b> <urn:p> <urn:o> .\n")
	result := convert_to_file(input, target, convert.Options{
		input = .N_Triples,
		output = .N_Quads,
		reader_limits = {max_records = 1},
	})
	testing.expect_value(t, result.error.code, convert.Error_Code.Source_Parse_Error)
	testing.expect_value(t, result.error.detail, "triple limit reached")
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
		input_format = .Turtle,
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
		input_format = .Turtle,
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
		input_format = .Turtle,
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
test_format_trig_file_groups_named_graph_and_respects_quad_limit :: proc(t: ^testing.T) {
	input_path :: "odin-rdf-cli-format-input.trig"
	target :: "odin-rdf-cli-format-output.trig"
	temporary :: "odin-rdf-cli-format-output.trig.odin-rdf.tmp"
	defer {
		_ = os.remove(input_path)
		_ = os.remove(target)
		_ = os.remove(temporary)
	}
	input := `<urn:g> { <urn:s> <urn:p> <urn:o2>, <urn:o1> . }
`
	testing.expect(t, write_test_file(input_path, input) == nil)
	testing.expect(t, write_test_file(target, "previous\n") == nil)
	options, parse_err := parse_format_command_args([]string{"format", input_path, "--output", target, "--max-quads", "10"})
	defer delete(options.prefixes)
	testing.expect_value(t, parse_err.code, Command_Error_Code.None)
	testing.expect_value(t, run_format(options), 0)
	buffer: [256]byte
	contents, read_err := read_test_file(target, &buffer)
	testing.expect(t, read_err == nil)
	expected := `@prefix ns1: <urn:> .

ns1:g {
  ns1:s ns1:p ns1:o1 ,
          ns1:o2 .
}
`
	testing.expect_value(t, contents, expected)
	testing.expect(t, !os.exists(temporary))

	testing.expect(t, write_test_file(target, "previous\n") == nil)
	limited, limited_parse_err := parse_format_command_args([]string{"format", input_path, "--output", target, "--max-quads", "1"})
	defer delete(limited.prefixes)
	testing.expect_value(t, limited_parse_err.code, Command_Error_Code.None)
	testing.expect_value(t, run_format(limited), 1)
	contents, read_err = read_test_file(target, &buffer)
	testing.expect(t, read_err == nil)
	testing.expect_value(t, contents, "previous\n")
	testing.expect(t, !os.exists(temporary))
}

@(test)
test_parses_integrity_commands_with_bounded_reader_options :: proc(t: ^testing.T) {
	canon_options, canon_err := parse_integrity_command_args([]string{
		"canon", "input.trig", "--output", "canonical.nq", "--algorithm=sha384", "--max-quads", "20",
		"--max-records", "10", "--max-document-bytes", "4096",
	})
	testing.expect_value(t, canon_err.code, Command_Error_Code.None)
	testing.expect_value(t, canon_options.command, Integrity_Command.Canon)
	testing.expect_value(t, canon_options.input_format, convert.Format.TriG)
	testing.expect_value(t, canon_options.output_path, "canonical.nq")
	testing.expect_value(t, canon_options.hash_algorithm, canon.Hash_Algorithm.SHA_384)
	testing.expect_value(t, canon_options.max_quads, 20)
	testing.expect_value(t, canon_options.reader_limits.max_records, 10)
	testing.expect_value(t, canon_options.reader_limits.max_document_bytes, 4096)

	hash_options, hash_err := parse_integrity_command_args([]string{"hash", "input.nt"})
	testing.expect_value(t, hash_err.code, Command_Error_Code.None)
	testing.expect_value(t, hash_options.command, Integrity_Command.Hash)
	testing.expect_value(t, hash_options.max_quads, canon.DEFAULT_MAX_QUADS)

	compare_options, compare_err := parse_integrity_command_args([]string{"compare", "left.ttl", "right.trig"})
	testing.expect_value(t, compare_err.code, Command_Error_Code.None)
	testing.expect_value(t, compare_options.input_format, convert.Format.Turtle)
	testing.expect_value(t, compare_options.other_format, convert.Format.TriG)

	diff_options, diff_err := parse_integrity_command_args([]string{"diff", "before.ttl", "after.trig", "--output", "changes.nqdiff"})
	testing.expect_value(t, diff_err.code, Command_Error_Code.None)
	testing.expect_value(t, diff_options.command, Integrity_Command.Diff)
	testing.expect_value(t, diff_options.input_format, convert.Format.Turtle)
	testing.expect_value(t, diff_options.other_format, convert.Format.TriG)
	testing.expect_value(t, diff_options.output_path, "changes.nqdiff")

	missing_options, missing_err := parse_integrity_command_args([]string{"compare", "left.nq"})
	testing.expect_value(t, missing_err.code, Command_Error_Code.Missing_Compare_Input)
	testing.expect_value(t, missing_options.command, Integrity_Command.Compare)

	stdin_options, stdin_err := parse_integrity_command_args([]string{"compare", "-", "right.nq", "--from", "nquads"})
	testing.expect_value(t, stdin_err.code, Command_Error_Code.Compare_Standard_Input)
	testing.expect_value(t, stdin_options.command, Integrity_Command.Compare)

	missing_diff_options, missing_diff_err := parse_integrity_command_args([]string{"diff", "before.nq"})
	testing.expect_value(t, missing_diff_err.code, Command_Error_Code.Missing_Diff_Input)
	testing.expect_value(t, missing_diff_options.command, Integrity_Command.Diff)

	stdin_diff_options, stdin_diff_err := parse_integrity_command_args([]string{"diff", "-", "after.nq", "--from", "nquads"})
	testing.expect_value(t, stdin_diff_err.code, Command_Error_Code.Diff_Standard_Input)
	testing.expect_value(t, stdin_diff_options.command, Integrity_Command.Diff)

	same_output_options, same_output_err := parse_integrity_command_args([]string{"diff", "before.nq", "after.nq", "--output", "after.nq"})
	testing.expect_value(t, same_output_err.code, Command_Error_Code.Same_Input_Output)
	testing.expect_value(t, same_output_options.command, Integrity_Command.Diff)

	invalid_algorithm_options, invalid_algorithm_err := parse_integrity_command_args([]string{"hash", "input.nt", "--algorithm", "sha512"})
	testing.expect_value(t, invalid_algorithm_err.code, Command_Error_Code.Invalid_Hash_Algorithm)
	testing.expect_value(t, invalid_algorithm_options.command, Integrity_Command.Hash)
}

@(test)
test_integrity_commands_canonicalize_hash_and_compare_atomically :: proc(t: ^testing.T) {
	input_path :: "odin-rdf-cli-canon-input.nq"
	canonical_target :: "odin-rdf-cli-canon-output.nq"
	hash_target :: "odin-rdf-cli-hash-output.txt"
	left_path :: "odin-rdf-cli-compare-left.nq"
	right_path :: "odin-rdf-cli-compare-right.nq"
	different_path :: "odin-rdf-cli-compare-different.nq"
	diff_before_path :: "odin-rdf-cli-diff-before.nq"
	diff_after_path :: "odin-rdf-cli-diff-after.nq"
	diff_target :: "odin-rdf-cli-diff-output.nqdiff"
	defer {
		_ = os.remove(input_path)
		_ = os.remove(canonical_target)
		_ = os.remove(canonical_target + ".odin-rdf.tmp")
		_ = os.remove(hash_target)
		_ = os.remove(hash_target + ".odin-rdf.tmp")
		_ = os.remove(left_path)
		_ = os.remove(right_path)
		_ = os.remove(different_path)
		_ = os.remove(diff_before_path)
		_ = os.remove(diff_after_path)
		_ = os.remove(diff_target)
		_ = os.remove(diff_target + ".odin-rdf.tmp")
	}
	testing.expect(t, write_test_file(input_path, "<urn:z> <urn:p> <urn:o> .\n<urn:a> <urn:p> <urn:o> .\n<urn:z> <urn:p> <urn:o> .\n") == nil)
	canon_options, canon_err := parse_integrity_command_args([]string{"canon", input_path, "--output", canonical_target})
	testing.expect_value(t, canon_err.code, Command_Error_Code.None)
	testing.expect_value(t, run_integrity_command(canon_options), 0)
	buffer: [256]byte
	contents, read_err := read_test_file(canonical_target, &buffer)
	testing.expect(t, read_err == nil)
	testing.expect_value(t, contents, "<urn:a> <urn:p> <urn:o> .\n<urn:z> <urn:p> <urn:o> .\n")

	testing.expect(t, write_test_file(input_path, "<urn:s> <urn:p> \"value\" .\n") == nil)
	hash_options, hash_err := parse_integrity_command_args([]string{"hash", input_path, "--output", hash_target})
	testing.expect_value(t, hash_err.code, Command_Error_Code.None)
	testing.expect_value(t, run_integrity_command(hash_options), 0)
	contents, read_err = read_test_file(hash_target, &buffer)
	testing.expect(t, read_err == nil)
	testing.expect_value(t, contents, "469b8e68a9f9cc0f0a72e96fb6d3a55595f2fda5f518e79d218b20900b722d9b\n")

	testing.expect(t, write_test_file(left_path, "_:left <urn:p> <urn:o> .\n<urn:s> <urn:p> _:left .\n") == nil)
	testing.expect(t, write_test_file(right_path, "<urn:s> <urn:p> _:right .\n_:right <urn:p> <urn:o> .\n") == nil)
	compare_options, compare_err := parse_integrity_command_args([]string{"compare", left_path, right_path})
	testing.expect_value(t, compare_err.code, Command_Error_Code.None)
	testing.expect_value(t, run_integrity_command(compare_options), 0)
	limited_compare_options, limited_compare_err := parse_integrity_command_args([]string{"compare", left_path, right_path, "--max-quads", "1"})
	testing.expect_value(t, limited_compare_err.code, Command_Error_Code.None)
	testing.expect_value(t, run_integrity_command(limited_compare_options), 2)

	testing.expect(t, write_test_file(different_path, "<urn:s> <urn:p> <urn:different> .\n") == nil)
	different_options, different_err := parse_integrity_command_args([]string{"compare", left_path, different_path})
	testing.expect_value(t, different_err.code, Command_Error_Code.None)
	testing.expect_value(t, run_integrity_command(different_options), 1)

	testing.expect(t, write_test_file(diff_before_path, "<urn:a> <urn:p> <urn:o> .\n<urn:shared> <urn:p> <urn:o> .\n") == nil)
	testing.expect(t, write_test_file(diff_after_path, "<urn:b> <urn:p> <urn:o> .\n<urn:shared> <urn:p> <urn:o> .\n") == nil)
	diff_options, diff_err := parse_integrity_command_args([]string{"diff", diff_before_path, diff_after_path, "--output", diff_target})
	testing.expect_value(t, diff_err.code, Command_Error_Code.None)
	testing.expect_value(t, run_integrity_command(diff_options), 1)
	contents, read_err = read_test_file(diff_target, &buffer)
	testing.expect(t, read_err == nil)
	testing.expect_value(t, contents, "- <urn:a> <urn:p> <urn:o> .\n+ <urn:b> <urn:p> <urn:o> .\n")

	equal_diff_options, equal_diff_err := parse_integrity_command_args([]string{"diff", diff_before_path, diff_before_path, "--output", diff_target})
	testing.expect_value(t, equal_diff_err.code, Command_Error_Code.None)
	testing.expect_value(t, run_integrity_command(equal_diff_options), 0)
	contents, read_err = read_test_file(diff_target, &buffer)
	testing.expect(t, read_err == nil)
	testing.expect_value(t, contents, "")

	testing.expect(t, write_test_file(diff_target, "previous\n") == nil)
	limited_diff_options, limited_diff_err := parse_integrity_command_args([]string{"diff", left_path, right_path, "--output", diff_target, "--max-quads", "1"})
	testing.expect_value(t, limited_diff_err.code, Command_Error_Code.None)
	testing.expect_value(t, run_integrity_command(limited_diff_options), 2)
	contents, read_err = read_test_file(diff_target, &buffer)
	testing.expect(t, read_err == nil)
	testing.expect_value(t, contents, "previous\n")
	testing.expect(t, !os.exists(diff_target + ".odin-rdf.tmp"))
}

@(test)
test_canon_preserves_an_existing_target_when_collection_hits_its_limit :: proc(t: ^testing.T) {
	input_path :: "odin-rdf-cli-canon-limit-input.nq"
	target :: "odin-rdf-cli-canon-limit-output.nq"
	temporary :: "odin-rdf-cli-canon-limit-output.nq.odin-rdf.tmp"
	defer {
		_ = os.remove(input_path)
		_ = os.remove(target)
		_ = os.remove(temporary)
	}
	testing.expect(t, write_test_file(input_path, "<urn:a> <urn:p> <urn:o> .\n<urn:b> <urn:p> <urn:o> .\n") == nil)
	testing.expect(t, write_test_file(target, "previous\n") == nil)
	options, parse_err := parse_integrity_command_args([]string{"canon", input_path, "--output", target, "--max-quads", "1"})
	testing.expect_value(t, parse_err.code, Command_Error_Code.None)
	testing.expect_value(t, run_integrity_command(options), 1)
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
		.Invalid_Format       = "unsupported RDF syntax",
		.Invalid_Prefix       = "--prefix must use LABEL=NAMESPACE",
		.Invalid_Max_Records  = "--max-records must be a positive decimal integer",
		.Invalid_Max_Line_Bytes = "--max-line-bytes must be a positive decimal integer",
		.Invalid_Max_Statement_Bytes = "--max-statement-bytes must be a positive decimal integer",
		.Invalid_Max_Document_Bytes = "--max-document-bytes must be a positive decimal integer",
		.Invalid_Max_Triples  = "--max-triples must be a positive decimal integer",
		.Invalid_Max_Quads    = "--max-quads must be a positive decimal integer",
		.Incompatible_Format_Limit = "format limit is not valid for selected RDF syntax",
		.Cannot_Infer_Input_Format = "cannot infer input RDF syntax; use --from",
		.Cannot_Infer_Output_Format = "cannot infer output RDF syntax; use --to",
		.Same_Input_Output    = "input and output paths must differ",
		.Missing_Compare_Input = "compare requires two input paths",
		.Compare_Standard_Input = "compare does not accept standard input",
		.Missing_Diff_Input = "diff requires two input paths",
		.Diff_Standard_Input = "diff does not accept standard input",
		.Invalid_Hash_Algorithm = "--algorithm must be sha256 or sha384",
		.Context_Requires_JSONLD = "--context requires JSON-LD output",
	}
	for code in Command_Error_Code do testing.expect_value(t, command_error_message(code), messages[code])
}
