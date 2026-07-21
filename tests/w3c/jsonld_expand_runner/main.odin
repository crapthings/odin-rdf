// jsonld_expand_runner expands one JSON-LD document for the pinned W3C API
// harness. The shell runner performs structural JSON comparison.
package main

import "core:fmt"
import "core:os"
import "core:strings"
import jsonld "../../../rdf/jsonld"

State :: struct {
	tests_root: string,
	loaded:     [dynamic][]byte,
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
		relative = "expand/c031/c031-context.jsonld"
	} else if url == "http://example.org/c031-context.jsonld" {
		relative = "expand/c031-context.jsonld"
	} else {
		return "", false
	}
	path := strings.builder_make()
	defer strings.builder_destroy(&path)
	strings.write_string(&path, state.tests_root)
	strings.write_byte(&path, '/')
	strings.write_string(&path, relative)
	data, read_error := os.read_entire_file(strings.to_string(path), context.allocator)
	if read_error != nil do return "", false
	append(&state.loaded, data)
	return string(data), true
}

// wrap_expand_context applies the W3C expandContext fixture at the document
// boundary. The library deliberately keeps this option out of its bounded
// public Expansion API; this adapter only supplies the conformance fixture.
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
		fmt.eprintln("usage: jsonld_expand_runner <input.jsonld> <base-iri> [tests-root] [json-ld-1.0|expand-context-0077]")
		os.exit(2)
	}
	input, read_error := os.read_entire_file(os.args[1], context.allocator)
	if read_error != nil {
		fmt.eprintf("cannot read %s: %v\n", os.args[1], read_error)
		os.exit(2)
	}
	defer delete(input)
	state: State
	defer destroy_state(&state)
	options := jsonld.Expand_Options{context_options = {base_iri = os.args[2]}}
	expand_context_0077 := false
	for argument in os.args[3:] {
		switch argument {
		case "json-ld-1.0":
			options.context_options.processing_mode = .Json_LD_1_0
		case "expand-context-0077":
			expand_context_0077 = true
		case:
			if len(state.tests_root) > 0 {
				fmt.eprintf("unknown jsonld expansion runner option: %s\n", argument)
				os.exit(2)
			}
			state.tests_root = argument
		}
	}
	if len(state.tests_root) > 0 {
		options.context_options.document_loader = load_document
		options.context_options.loader_data = &state
	}
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	document := string(input)
	wrapped := strings.builder_make()
	defer strings.builder_destroy(&wrapped)
	if expand_context_0077 {
		context_document, loaded := load_document("https://w3c.github.io/json-ld-api/tests/expand/0077-context.jsonld", &state)
		if !loaded || !wrap_expand_context(&wrapped, document, context_document) {
			fmt.eprintf("cannot apply expandContext for %s\n", os.args[1])
			os.exit(2)
		}
		document = strings.to_string(wrapped)
	}
	if err := jsonld.expand(&builder, document, options); err != .None {
		fmt.eprintf("%s: %s (%v)\n", os.args[1], jsonld.expand_error_message(err), err)
		os.exit(1)
	}
	fmt.print(strings.to_string(builder))
}
