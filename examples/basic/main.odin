package main

import "core:fmt"
import rdf "../../rdf"
import ntriples "../../rdf/ntriples"

print_triple :: proc(triple: rdf.Triple, _: rawptr) -> bool {
	fmt.println(triple.subject.value, triple.predicate.value, triple.object.value)
	return true
}

main :: proc() {
	input := `<http://example/alice> <http://example/name> "Alice"@en .`
	if err := ntriples.parse(input, print_triple); err.code != .None {
		fmt.eprintf("line %d, column %d: %s\n", err.line, err.column, ntriples.parse_error_message(err.code))
	}
}
