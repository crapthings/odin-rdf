package main

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import rdf "../../../rdf"
import nquads "../../../rdf/nquads"
import trig "../../../rdf/trig"
import support "../support"

Dataset :: struct {
	quads: [dynamic]rdf.Quad,
	owned: [dynamic]string,
}

destroy_dataset :: proc(dataset: ^Dataset) {
	for value in dataset.owned do delete(value)
	delete(dataset.owned)
	delete(dataset.quads)
}

clone_string :: proc(dataset: ^Dataset, value: string) -> string {
	if len(value) == 0 do return ""
	cloned := strings.clone(value) or_else ""
	append(&dataset.owned, cloned)
	return cloned
}

clone_term :: proc(dataset: ^Dataset, term: rdf.Term) -> rdf.Term {
	return rdf.Term{
		kind = term.kind,
		value = clone_string(dataset, term.value),
		language = clone_string(dataset, term.language),
		datatype = clone_string(dataset, term.datatype),
		scope = term.scope,
	}
}

collect :: proc(quad: rdf.Quad, data: rawptr) -> bool {
	dataset := cast(^Dataset)data
	append(&dataset.quads, rdf.Quad{
		subject = clone_term(dataset, quad.subject),
		predicate = clone_term(dataset, quad.predicate),
		object = clone_term(dataset, quad.object),
		graph = clone_term(dataset, quad.graph),
		has_graph = quad.has_graph,
	})
	return true
}

verify_readers :: proc(input, base, path: string, want_valid: bool, memory: ^Dataset, memory_error: trig.Parse_Error = {}) -> bool {
	chunk_sizes := [3]int{1, 7, 0}
	for chunk_size in chunk_sizes {
		actual := Dataset{quads = make([dynamic]rdf.Quad), owned = make([dynamic]string)}
		reader_state: strings.Reader
		reader := strings.to_reader(&reader_state, input)
		result := trig.parse_reader(reader, collect, trig.Reader_Options{
			parse = trig.Parse_Options{base_iri = base},
			chunk_size = chunk_size,
		}, &actual)
		is_valid := result.error.code == .None
		if is_valid != want_valid {
			fmt.eprintf("%s: reader chunk=%d expected valid=%v, got %s (%v) at %d:%d\n", path, chunk_size, want_valid, trig.parse_error_message(result.error.code), result.error.code, result.error.line, result.error.column)
			destroy_dataset(&actual)
			return false
		}
		if !want_valid && (result.error.code != memory_error.code || result.error.line != memory_error.line || result.error.column != memory_error.column) {
			fmt.eprintf("%s: reader chunk=%d error differs from memory: memory=(%v %d:%d), reader=(%v %d:%d)\n", path, chunk_size, memory_error.code, memory_error.line, memory_error.column, result.error.code, result.error.line, result.error.column)
			destroy_dataset(&actual)
			return false
		}
		if want_valid && !support.dataset_isomorphic(memory.quads[:], actual.quads[:]) {
			fmt.eprintf("%s: reader chunk=%d dataset differs from memory parser\n", path, chunk_size)
			destroy_dataset(&actual)
			return false
		}
		destroy_dataset(&actual)
	}
	return true
}

main :: proc() {
	if len(os.args) < 3 || len(os.args) > 4 {
		fmt.eprintln("usage: trig_runner <evaluation|positive|negative> <action.trig> [result.nq]")
		os.exit(2)
	}
	kind, action_path := os.args[1], os.args[2]
	action, read_error := os.read_entire_file(action_path, context.allocator)
	if read_error != nil {
		fmt.eprintf("cannot read %s: %v\n", action_path, read_error)
		os.exit(2)
	}
	defer delete(action)
	base_builder := strings.builder_make()
	defer strings.builder_destroy(&base_builder)
	strings.write_string(&base_builder, "https://w3c.github.io/rdf-tests/rdf/rdf11/rdf-trig/")
	strings.write_string(&base_builder, filepath.base(action_path))

	actual := Dataset{quads = make([dynamic]rdf.Quad), owned = make([dynamic]string)}
	defer destroy_dataset(&actual)
	err := trig.parse(string(action), collect, trig.Parse_Options{base_iri = strings.to_string(base_builder)}, &actual)
	if kind == "negative" {
		if err.code == .None {
			fmt.eprintf("%s: expected invalid TriG, parser accepted it\n", action_path)
			os.exit(1)
		}
		if !verify_readers(string(action), strings.to_string(base_builder), action_path, false, &actual, err) do os.exit(1)
		return
	}
	if err.code != .None {
		fmt.eprintf("%s: %s (%v) at %d:%d\n", action_path, trig.parse_error_message(err.code), err.code, err.line, err.column)
		os.exit(1)
	}
	if !verify_readers(string(action), strings.to_string(base_builder), action_path, true, &actual) do os.exit(1)
	if kind == "positive" do return
	if len(os.args) != 4 {
		fmt.eprintln("evaluation case requires expected N-Quads")
		os.exit(2)
	}
	expected_data, expected_read_error := os.read_entire_file(os.args[3], context.allocator)
	if expected_read_error != nil {
		fmt.eprintf("cannot read %s: %v\n", os.args[3], expected_read_error)
		os.exit(2)
	}
	defer delete(expected_data)
	expected := Dataset{quads = make([dynamic]rdf.Quad), owned = make([dynamic]string)}
	defer destroy_dataset(&expected)
	expected_error := nquads.parse(string(expected_data), collect, &expected)
	if expected_error.code != .None {
		fmt.eprintf("%s: expected dataset is invalid N-Quads\n", os.args[3])
		os.exit(2)
	}
	if !support.dataset_isomorphic(actual.quads[:], expected.quads[:]) {
		fmt.eprintf("%s: dataset mismatch, got %d quads, expected %d\n", action_path, len(actual.quads), len(expected.quads))
		os.exit(1)
	}
}
