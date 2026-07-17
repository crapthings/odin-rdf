package main

import "core:fmt"
import rdf "../../rdf"
import nquads "../../rdf/nquads"

print_quad :: proc(quad: rdf.Quad, _: rawptr) -> bool {
	if quad.has_graph {
		fmt.println(quad.subject.value, quad.predicate.value, quad.object.value, quad.graph.value)
	} else {
		fmt.println(quad.subject.value, quad.predicate.value, quad.object.value, "(default graph)")
	}
	return true
}

main :: proc() {
	input := `<https://example/alice> <https://example/name> "Alice" <https://example/people> .`
	if err := nquads.parse(input, print_quad); err.code != .None {
		fmt.eprintf("line %d, column %d: %s\n", err.line, err.column, nquads.parse_error_message(err.code))
	}
}
