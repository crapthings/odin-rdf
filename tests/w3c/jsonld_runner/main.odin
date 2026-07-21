// jsonld_runner transforms one JSON-LD document into N-Quads for the pinned
// W3C JSON-LD to-RDF harness. Dataset comparison and manifest selection stay
// in the shell script so this runner remains a small package-level adapter.
package main

import "core:fmt"
import "core:os"
import "core:strings"
import rdf "../../../rdf"
import jsonld "../../../rdf/jsonld"
import nquads "../../../rdf/nquads"

State :: struct {
	builder: strings.Builder,
	write_error: nquads.Write_Error,
	tests_root: string,
	loaded:     [dynamic][]byte,
	allow_generalized_rdf: bool,
}

write_quad :: proc(quad: rdf.Quad, user_data: rawptr) -> bool {
	state := cast(^State)user_data
	state.write_error = nquads.write_quad_with_options(&state.builder, quad, {allow_generalized_rdf = state.allow_generalized_rdf})
	return state.write_error == .None
}

destroy_state :: proc(state: ^State) {
	for data in state.loaded do delete(data)
	delete(state.loaded)
}

load_document :: proc(url: string, user_data: rawptr) -> (string, bool) {
	state := cast(^State)user_data
	prefix :: "https://w3c.github.io/json-ld-api/tests/"
	relative := ""
	if strings.has_prefix(url, prefix) {
		relative = url[len(prefix):]
	} else if url == "http://example.org/a/c031/c031-context.jsonld" {
		relative = "toRdf/c031/c031-context.jsonld"
	} else if url == "http://example.org/c031-context.jsonld" {
		relative = "toRdf/c031-context.jsonld"
	} else {
		return "", false
	}
	path_builder := strings.builder_make()
	defer strings.builder_destroy(&path_builder)
	strings.write_string(&path_builder, state.tests_root)
	strings.write_byte(&path_builder, '/')
	strings.write_string(&path_builder, relative)
	data, read_error := os.read_entire_file(strings.to_string(path_builder), context.allocator)
	if read_error != nil do return "", false
	append(&state.loaded, data)
	return string(data), true
}

// wrap_expand_context applies the W3C expandContext fixture to a top-level
// object without changing the library's public parse options. The fixture is a
// JSON document containing one @context member; its value becomes the input
// document's leading local context.
wrap_expand_context :: proc(builder: ^strings.Builder, input, context_document: string) -> bool {
	context_colon := -1
	for index in 0..<len(context_document) {
		if context_document[index] == ':' {
			context_colon = index
			break
		}
	}
	context_end := len(context_document) - 1
	for context_end >= 0 && (context_document[context_end] == ' ' || context_document[context_end] == '\t' || context_document[context_end] == '\n' || context_document[context_end] == '\r') do context_end -= 1
	input_start := 0
	for input_start < len(input) && (input[input_start] == ' ' || input[input_start] == '\t' || input[input_start] == '\n' || input[input_start] == '\r') do input_start += 1
	if context_colon < 0 || context_end <= context_colon || context_document[context_end] != '}' || input_start >= len(input) || input[input_start] != '{' do return false
	strings.write_string(builder, "{\"@context\":")
	strings.write_string(builder, context_document[context_colon + 1:context_end])
	strings.write_byte(builder, ',')
	strings.write_string(builder, input[input_start + 1:])
	return true
}

main :: proc() {
	if len(os.args) < 3 || len(os.args) > 5 {
		fmt.eprintln("usage: jsonld_runner <input.jsonld> <base-iri> [tests-root] [i18n-datatype|compound-literal|generalized-rdf|json-ld-1.0|expand-context-e077]")
		os.exit(2)
	}
	data, read_error := os.read_entire_file(os.args[1], context.allocator)
	if read_error != nil {
		fmt.eprintf("cannot read %s: %v\n", os.args[1], read_error)
		os.exit(2)
	}
	defer delete(data)
	state := State{builder = strings.builder_make()}
	defer strings.builder_destroy(&state.builder)
	defer destroy_state(&state)
	options := jsonld.Options{base_iri = os.args[2]}
	expand_context_e077 := false
	for argument in os.args[3:] {
		switch argument {
		case "i18n-datatype":
			options.rdf_direction = .I18n_Datatype
		case "compound-literal":
			options.rdf_direction = .Compound_Literal
		case "generalized-rdf":
			options.produce_generalized_rdf = true
			state.allow_generalized_rdf = true
		case "json-ld-1.0":
			options.processing_mode = .Json_LD_1_0
		case "expand-context-e077":
			expand_context_e077 = true
		case:
			if len(state.tests_root) > 0 {
				fmt.eprintf("unknown jsonld runner option: %s\n", argument)
				os.exit(2)
			}
			state.tests_root = argument
		}
	}
	if len(state.tests_root) > 0 {
		options.document_loader = load_document
		options.loader_data = &state
	}
	document := string(data)
	wrapped_document := strings.builder_make()
	defer strings.builder_destroy(&wrapped_document)
	if expand_context_e077 {
		context_document, loaded := load_document("https://w3c.github.io/json-ld-api/tests/toRdf/e077-context.jsonld", &state)
		if !loaded || !wrap_expand_context(&wrapped_document, document, context_document) {
			fmt.eprintf("cannot apply expandContext for %s\n", os.args[1])
			os.exit(2)
		}
		document = strings.to_string(wrapped_document)
	}
	err := jsonld.parse(document, write_quad, options, &state)
	if err.code != .None {
		fmt.eprintf("%s: %s (%v)\n", os.args[1], jsonld.parse_error_message(err.code), err.code)
		os.exit(1)
	}
	if state.write_error != .None {
		fmt.eprintf("%s: N-Quads writer rejected output: %s\n", os.args[1], nquads.write_error_message(state.write_error))
		os.exit(1)
	}
	fmt.print(strings.to_string(state.builder))
}
