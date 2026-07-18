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
}

write_quad :: proc(quad: rdf.Quad, user_data: rawptr) -> bool {
	state := cast(^State)user_data
	state.write_error = nquads.write_quad(&state.builder, quad)
	return state.write_error == .None
}

destroy_state :: proc(state: ^State) {
	for data in state.loaded do delete(data)
	delete(state.loaded)
}

load_document :: proc(url: string, user_data: rawptr) -> (string, bool) {
	state := cast(^State)user_data
	prefix :: "https://w3c.github.io/json-ld-api/tests/"
	if !strings.has_prefix(url, prefix) do return "", false
	path_builder := strings.builder_make()
	defer strings.builder_destroy(&path_builder)
	strings.write_string(&path_builder, state.tests_root)
	strings.write_byte(&path_builder, '/')
	strings.write_string(&path_builder, url[len(prefix):])
	data, read_error := os.read_entire_file(strings.to_string(path_builder), context.allocator)
	if read_error != nil do return "", false
	append(&state.loaded, data)
	return string(data), true
}

main :: proc() {
	if len(os.args) != 3 && len(os.args) != 4 {
		fmt.eprintln("usage: jsonld_runner <input.jsonld> <base-iri> [tests-root]")
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
	if len(os.args) == 4 {
		state.tests_root = os.args[3]
		options.document_loader = load_document
		options.loader_data = &state
	}
	err := jsonld.parse(string(data), write_quad, options, &state)
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
