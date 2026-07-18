// jsonld_fromrdf_runner serializes N-Quads through the JSON-LD RDF-to-JSON-LD
// API for the pinned W3C fromRdf conformance harness.
package main

import "core:fmt"
import "core:os"
import "core:strings"
import dataset "../../../rdf/dataset"
import jsonld "../../../rdf/jsonld"
import nquads "../../../rdf/nquads"

main :: proc() {
	if len(os.args) < 2 || len(os.args) > 4 {
		fmt.eprintln("usage: jsonld_fromrdf_runner <input.nq> [--use-native-types] [--use-rdf-type]")
		os.exit(2)
	}
	options: jsonld.Serialize_Options
	for argument in os.args[2:] {
		switch argument {
		case "--use-native-types": options.use_native_types = true
		case "--use-rdf-type":     options.use_rdf_type = true
		case:
			fmt.eprintf("unknown option: %s\n", argument)
			os.exit(2)
		}
	}
	data, read_error := os.read_entire_file(os.args[1], context.allocator)
	if read_error != nil {
		fmt.eprintf("cannot read %s: %v\n", os.args[1], read_error)
		os.exit(2)
	}
	defer delete(data)
	collector: dataset.Collector
	if init_error := dataset.init(&collector, dataset.Options{max_quads = jsonld.DEFAULT_MAX_SERIALIZE_QUADS}); init_error != .None {
		fmt.eprintln(dataset.error_message(init_error))
		os.exit(2)
	}
	defer dataset.destroy(&collector)
	parse_error := nquads.parse(string(data), dataset.sink, &collector)
	if parse_error.code != .None {
		fmt.eprintf("%s: %s\n", os.args[1], nquads.parse_error_message(parse_error.code))
		os.exit(1)
	}
	if collector.last_error != .None {
		fmt.eprintln(dataset.error_message(collector.last_error))
		os.exit(1)
	}
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	if serialize_error := jsonld.serialize(&builder, collector.quads[:], options); serialize_error != .None {
		fmt.eprintln(jsonld.serialize_error_message(serialize_error))
		os.exit(1)
	}
	fmt.print(strings.to_string(builder))
}
