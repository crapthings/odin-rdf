// jsonld_compact_runner compacts one JSON-LD document using a context document.
package main

import "core:fmt"
import "core:os"
import "core:strings"
import dataset "../../../rdf/dataset"
import jsonld "../../../rdf/jsonld"

main :: proc() {
	if len(os.args) < 3 {
		fmt.eprintln("usage: jsonld_compact_runner <input.jsonld> <context.jsonld> [--base IRI] [--rdf-direction-i18n|--rdf-direction-compound]")
		os.exit(2)
	}
	input, input_error := os.read_entire_file(os.args[1], context.allocator)
	if input_error != nil {
		fmt.eprintf("cannot read %s: %v\n", os.args[1], input_error)
		os.exit(2)
	}
	defer delete(input)
	context_document, context_error := os.read_entire_file(os.args[2], context.allocator)
	if context_error != nil {
		fmt.eprintf("cannot read %s: %v\n", os.args[2], context_error)
		os.exit(2)
	}
	defer delete(context_document)
	collector: dataset.Collector
	if init_error := dataset.init(&collector, dataset.Options{max_quads = jsonld.DEFAULT_MAX_SERIALIZE_QUADS}); init_error != .None {
		fmt.eprintln(dataset.error_message(init_error))
		os.exit(2)
	}
	defer dataset.destroy(&collector)
	parse_options: jsonld.Options
	compact_options: jsonld.Compact_Options
	for index := 3; index < len(os.args); index += 1 {
		switch os.args[index] {
		case "--base":
			if index + 1 >= len(os.args) {
				fmt.eprintln("--base requires an absolute IRI")
				os.exit(2)
			}
			index += 1
			parse_options.base_iri = os.args[index]
			compact_options.context_options.base_iri = os.args[index]
		case "--rdf-direction-i18n", "--rdf-direction-compound":
			direction := os.args[index] == "--rdf-direction-i18n" ? jsonld.RDF_Direction_Mode.I18n_Datatype : jsonld.RDF_Direction_Mode.Compound_Literal
			parse_options.rdf_direction = direction
			compact_options.serializer_options.rdf_direction = direction
		case:
			fmt.eprintf("unknown compact runner option: %s\n", os.args[index])
			os.exit(2)
		}
	}
	if parse_error := jsonld.parse(string(input), dataset.sink, parse_options, &collector); parse_error.code != .None {
		fmt.eprintf("%s: %s\n", os.args[1], jsonld.parse_error_message(parse_error.code))
		os.exit(1)
	}
	if collector.last_error != .None {
		fmt.eprintln(dataset.error_message(collector.last_error))
		os.exit(1)
	}
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	if compact_error := jsonld.compact(&builder, collector.quads[:], string(context_document), compact_options); compact_error != .None {
		fmt.eprintln(jsonld.compact_error_message(compact_error))
		os.exit(1)
	}
	fmt.print(strings.to_string(builder))
}
