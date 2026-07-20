// jsonld_flatten_runner flattens one JSON-LD document for the pinned W3C API
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
	if !strings.has_prefix(url, prefix) do return "", false
	path := strings.builder_make()
	defer strings.builder_destroy(&path)
	strings.write_string(&path, state.tests_root)
	strings.write_byte(&path, '/')
	strings.write_string(&path, url[len(prefix):])
	data, read_error := os.read_entire_file(strings.to_string(path), context.allocator)
	if read_error != nil do return "", false
	append(&state.loaded, data)
	return string(data), true
}

main :: proc() {
	if len(os.args) != 3 && len(os.args) != 4 {
		fmt.eprintln("usage: jsonld_flatten_runner <input.jsonld> <base-iri> [tests-root]")
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
	options := jsonld.Flatten_Options{context_options = {base_iri = os.args[2]}}
	if len(os.args) == 4 {
		state.tests_root = os.args[3]
		options.context_options.document_loader = load_document
		options.context_options.loader_data = &state
	}
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	if err := jsonld.flatten(&builder, string(input), options); err != .None {
		fmt.eprintf("%s: %s (%v)\n", os.args[1], jsonld.flatten_error_message(err), err)
		os.exit(1)
	}
	fmt.print(strings.to_string(builder))
}
