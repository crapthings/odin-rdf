package main

import "core:fmt"
import rdf "../../rdf"
import turtle "../../rdf/turtle"

print_triple :: proc(triple: rdf.Triple, _: rawptr) -> bool {
	fmt.println(triple.subject.value, triple.predicate.value, triple.object.value)
	return true
}

main :: proc() {
	input := `@base <https://example.com/> .
@prefix ex: <vocab/> .

<#alice> a ex:Person ;
    ex:name "Alice"@en ;
    ex:knows [ ex:name "Bob" ] ;
    ex:favorites ("Odin" "RDF") .`

	if err := turtle.parse(input, print_triple); err.code != .None {
		fmt.eprintf("line %d, column %d: %s\n", err.line, err.column, turtle.parse_error_message(err.code))
	}
}
