// jsonld_compact_runner compacts one JSON-LD document using a context document.
package main

import "core:fmt"
import json "core:encoding/json"
import "core:os"
import "core:strings"
import dataset "../../../rdf/dataset"
import jsonld "../../../rdf/jsonld"

json_values_equal :: proc(left, right: json.Value) -> bool {
	#partial switch left_value in left {
	case json.Null:
		#partial switch _ in right { case json.Null: return true }
	case json.Boolean:
		#partial switch right_value in right { case json.Boolean: return left_value == right_value }
	case json.Integer:
		#partial switch right_value in right { case json.Integer: return left_value == right_value }
	case json.Float:
		#partial switch right_value in right { case json.Float: return left_value == right_value }
	case json.String:
		#partial switch right_value in right { case json.String: return left_value == right_value }
	case json.Array:
		#partial switch right_value in right {
		case json.Array:
			if len(left_value) != len(right_value) do return false
			for item, index in left_value do if !json_values_equal(item, right_value[index]) do return false
			return true
		}
	case json.Object:
		#partial switch right_value in right {
		case json.Object:
			if len(left_value) != len(right_value) do return false
			for key, item in left_value {
				other, found := right_value[key]
				if !found || !json_values_equal(item, other) do return false
			}
			return true
		}
	}
	return false
}

main :: proc() {
	if len(os.args) < 3 {
		fmt.eprintln("usage: jsonld_compact_runner <input.jsonld> <context.jsonld> [--expect output.jsonld] [--base IRI] [--preserve-arrays] [--rdf-direction-i18n|--rdf-direction-compound]")
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
	expected_path := ""
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
		case "--expect":
			if index + 1 >= len(os.args) {
				fmt.eprintln("--expect requires an output path")
				os.exit(2)
			}
			index += 1
			expected_path = os.args[index]
		case "--preserve-arrays":
			compact_options.array_policy = .Preserve
		case "--processing-mode-1.0":
			parse_options.processing_mode = .Json_LD_1_0
			compact_options.context_options.processing_mode = .Json_LD_1_0
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
	compact_options.source_document = string(input)
	if compact_error := jsonld.compact(&builder, collector.quads[:], string(context_document), compact_options); compact_error != .None {
		fmt.eprintln(jsonld.compact_error_message(compact_error))
		os.exit(1)
	}
	output := strings.to_string(builder)
	if len(expected_path) > 0 {
		expected, expected_error := os.read_entire_file(expected_path, context.allocator)
		if expected_error != nil {
			fmt.eprintf("cannot read %s: %v\n", expected_path, expected_error)
			os.exit(2)
		}
		defer delete(expected)
		actual_value, actual_json_error := json.parse_string(output, .JSON, true)
		if actual_json_error != .None {
			fmt.eprintln("compaction output is not valid JSON")
			os.exit(1)
		}
		defer json.destroy_value(actual_value)
		expected_value, expected_json_error := json.parse_string(string(expected), .JSON, true)
		if expected_json_error != .None {
			fmt.eprintln("expected output is not valid JSON")
			os.exit(2)
		}
		defer json.destroy_value(expected_value)
		if !json_values_equal(actual_value, expected_value) {
			fmt.eprintf("compacted output differs structurally from %s\n", expected_path)
			os.exit(1)
		}
	}
	fmt.print(output)
}
