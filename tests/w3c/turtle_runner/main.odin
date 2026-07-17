package main

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import rdf "../../../rdf"
import ntriples "../../../rdf/ntriples"
import turtle "../../../rdf/turtle"
import support "../support"

Graph :: struct {
	triples: [dynamic]rdf.Triple,
	owned:   [dynamic]string,
}

destroy_graph :: proc(graph: ^Graph) {
	for value in graph.owned do delete(value)
	delete(graph.owned)
	delete(graph.triples)
}

clone_string :: proc(graph: ^Graph, value: string) -> string {
	if len(value) == 0 do return ""
	cloned := strings.clone(value) or_else ""
	append(&graph.owned, cloned)
	return cloned
}

clone_term :: proc(graph: ^Graph, term: rdf.Term) -> rdf.Term {
	return rdf.Term{
		kind = term.kind,
		value = clone_string(graph, term.value),
		language = clone_string(graph, term.language),
		datatype = clone_string(graph, term.datatype),
		scope = term.scope,
	}
}

collect :: proc(triple: rdf.Triple, data: rawptr) -> bool {
	graph := cast(^Graph)data
	append(&graph.triples, rdf.Triple{
		clone_term(graph, triple.subject),
		clone_term(graph, triple.predicate),
		clone_term(graph, triple.object),
	})
	return true
}

verify_readers :: proc(input, base, path: string, want_valid: bool, memory: ^Graph, memory_error: turtle.Parse_Error = {}) -> bool {
	chunk_sizes := [3]int{1, 7, 0}
	for chunk_size in chunk_sizes {
		actual := Graph{triples = make([dynamic]rdf.Triple), owned = make([dynamic]string)}
		reader_state: strings.Reader
		reader := strings.to_reader(&reader_state, input)
		result := turtle.parse_reader(reader, collect, turtle.Reader_Options{
			parse = turtle.Parse_Options{base_iri = base},
			chunk_size = chunk_size,
		}, &actual)
		is_valid := result.error.code == .None
		if is_valid != want_valid {
			fmt.eprintf("%s: reader chunk=%d expected valid=%v, got %s (%v) at %d:%d\n", path, chunk_size, want_valid, turtle.parse_error_message(result.error.code), result.error.code, result.error.line, result.error.column)
			destroy_graph(&actual)
			return false
		}
		if !want_valid && (result.error.code != memory_error.code || result.error.line != memory_error.line || result.error.column != memory_error.column) {
			fmt.eprintf("%s: reader chunk=%d error differs from memory: memory=(%v %d:%d), reader=(%v %d:%d)\n", path, chunk_size, memory_error.code, memory_error.line, memory_error.column, result.error.code, result.error.line, result.error.column)
			destroy_graph(&actual)
			return false
		}
		if want_valid && !support.graph_isomorphic(memory.triples[:], actual.triples[:]) {
			fmt.eprintf("%s: reader chunk=%d graph differs from memory parser\n", path, chunk_size)
			destroy_graph(&actual)
			return false
		}
		destroy_graph(&actual)
	}
	return true
}

main :: proc() {
	if len(os.args) < 3 || len(os.args) > 4 {
		fmt.eprintln("usage: turtle_runner <evaluation|positive|negative> <action.ttl> [result.nt]")
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
	strings.write_string(&base_builder, "https://w3c.github.io/rdf-tests/rdf/rdf11/rdf-turtle/")
	strings.write_string(&base_builder, filepath.base(action_path))

	actual := Graph{triples = make([dynamic]rdf.Triple), owned = make([dynamic]string)}
	defer destroy_graph(&actual)
	err := turtle.parse(string(action), collect, turtle.Parse_Options{base_iri = strings.to_string(base_builder)}, &actual)
	if kind == "negative" {
		if err.code == .None {
			fmt.eprintf("%s: expected invalid Turtle, parser accepted it\n", action_path)
			os.exit(1)
		}
		if !verify_readers(string(action), strings.to_string(base_builder), action_path, false, &actual, err) do os.exit(1)
		return
	}
	if err.code != .None {
		fmt.eprintf("%s: %s (%v) at %d:%d\n", action_path, turtle.parse_error_message(err.code), err.code, err.line, err.column)
		os.exit(1)
	}
	if !verify_readers(string(action), strings.to_string(base_builder), action_path, true, &actual) do os.exit(1)
	if kind == "positive" do return
	if len(os.args) != 4 {
		fmt.eprintln("evaluation case requires expected N-Triples")
		os.exit(2)
	}
	expected_data, expected_read_error := os.read_entire_file(os.args[3], context.allocator)
	if expected_read_error != nil {
		fmt.eprintf("cannot read %s: %v\n", os.args[3], expected_read_error)
		os.exit(2)
	}
	defer delete(expected_data)
	expected := Graph{triples = make([dynamic]rdf.Triple), owned = make([dynamic]string)}
	defer destroy_graph(&expected)
	expected_error := ntriples.parse(string(expected_data), collect, &expected)
	if expected_error.code != .None {
		fmt.eprintf("%s: expected graph is invalid N-Triples\n", os.args[3])
		os.exit(2)
	}
	if !support.graph_isomorphic(actual.triples[:], expected.triples[:]) {
		fmt.eprintf("%s: graph mismatch, got %d triples, expected %d\n", action_path, len(actual.triples), len(expected.triples))
		os.exit(1)
	}
}
