package main

import "core:fmt"
import "core:strings"
import rdf "../../rdf"
import turtle "../../rdf/turtle"

main :: proc() {
	triples := []rdf.Triple{
		{rdf.iri("https://example.com/alice"), rdf.iri("https://example.com/knows"), rdf.iri("https://example.com/carol")},
		{rdf.iri("https://example.com/alice"), rdf.iri("https://example.com/name"), rdf.literal("Alice")},
		{rdf.iri("https://example.com/alice"), rdf.iri("https://example.com/knows"), rdf.iri("https://example.com/bob")},
	}
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	if err := turtle.format_triples(&builder, triples); err != .None {
		fmt.eprintln(turtle.write_error_message(err))
		return
	}
	fmt.print(strings.to_string(builder))
}
