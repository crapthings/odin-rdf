// jsonld_frame_runner frames one JSON-LD document for the pinned W3C harness.
// The shell runner performs structural JSON comparison.
package main

import "core:fmt"
import "core:os"
import "core:strings"
import jsonld "../../../rdf/jsonld"

main :: proc() {
	if len(os.args) < 4 {
		fmt.eprintln("usage: jsonld_frame_runner <input.jsonld> <frame.jsonld> <base-iri> [omit-graph|keep-graph|json-ld-1.0 ...]")
		os.exit(2)
	}
	input, input_error := os.read_entire_file(os.args[1], context.allocator)
	if input_error != nil {
		fmt.eprintf("cannot read %s: %v\n", os.args[1], input_error)
		os.exit(2)
	}
	defer delete(input)
	frame_document, frame_error := os.read_entire_file(os.args[2], context.allocator)
	if frame_error != nil {
		fmt.eprintf("cannot read %s: %v\n", os.args[2], frame_error)
		os.exit(2)
	}
	defer delete(frame_document)
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	options := jsonld.Frame_Options{context_options = {base_iri = os.args[3]}}
	for argument in os.args[4:] {
		switch argument {
		case "omit-graph":
			options.omit_graph = true
			options.omit_graph_set = true
		case "keep-graph":
			options.omit_graph = false
			options.omit_graph_set = true
		case "json-ld-1.0":
			options.processing_mode = .Json_LD_1_0
		case:
			fmt.eprintf("unknown frame option: %s\n", argument)
			os.exit(2)
		}
	}
	if err := jsonld.frame(&builder, string(input), string(frame_document), options); err != .None {
		fmt.eprintf("%s: %s (%v)\n", os.args[1], jsonld.frame_error_message(err), err)
		os.exit(1)
	}
	fmt.print(strings.to_string(builder))
}
