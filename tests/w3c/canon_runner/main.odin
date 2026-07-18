package main

import "core:fmt"
import "core:os"
import "core:strings"
import rdf "../../../rdf"
import canon "../../../rdf/canon"
import nquads "../../../rdf/nquads"

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

read_dataset :: proc(path: string, dataset: ^Dataset) -> bool {
	data, read_error := os.read_entire_file(path, context.allocator)
	if read_error != nil {
		fmt.eprintf("cannot read %s: %v\n", path, read_error)
		return false
	}
	defer delete(data)
	if parse_error := nquads.parse(string(data), collect, dataset); parse_error.code != .None {
		fmt.eprintf("%s: input is invalid N-Quads: %s\n", path, nquads.parse_error_message(parse_error.code))
		return false
	}
	return true
}

main :: proc() {
	if len(os.args) < 3 || len(os.args) > 5 {
		fmt.eprintln("usage: canon_runner <evaluation|negative> <input.nq> [expected.nq] [sha256|sha384]")
		os.exit(2)
	}
	kind, input_path := os.args[1], os.args[2]
	dataset := Dataset{quads = make([dynamic]rdf.Quad), owned = make([dynamic]string)}
	defer destroy_dataset(&dataset)
	if !read_dataset(input_path, &dataset) do os.exit(2)
	options: canon.Options
	if kind == "evaluation" && len(os.args) == 5 {
		switch os.args[4] {
		case "sha256": options.hash_algorithm = .SHA_256
		case "sha384": options.hash_algorithm = .SHA_384
		case:
			fmt.eprintf("unknown hash algorithm: %s\n", os.args[4])
			os.exit(2)
		}
	}
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	err := canon.canonicalize(&builder, dataset.quads[:], options)
	if kind == "negative" {
		if err == .None {
			fmt.eprintf("%s: expected canonicalization to hit a resource limit\n", input_path)
			os.exit(1)
		}
		return
	}
	if kind != "evaluation" || len(os.args) < 4 {
		fmt.eprintln("evaluation requires expected N-Quads")
		os.exit(2)
	}
	if err != .None {
		fmt.eprintf("%s: canonicalization failed: %s\n", input_path, canon.error_message(err))
		os.exit(1)
	}
	expected, expected_error := os.read_entire_file(os.args[3], context.allocator)
	if expected_error != nil {
		fmt.eprintf("cannot read %s: %v\n", os.args[3], expected_error)
		os.exit(2)
	}
	defer delete(expected)
	if strings.to_string(builder) != string(expected) {
		fmt.eprintf("%s: canonical N-Quads differ\n", input_path)
		os.exit(1)
	}
}
