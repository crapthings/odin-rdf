package main

import "core:fmt"
import "core:strings"
import rdf "../../rdf"
import ntriples "../../rdf/ntriples"
import rdfxml "../../rdf/rdfxml"

Serialize_State :: struct {
	writer: ^rdfxml.Document_Writer,
	error:  rdfxml.Write_Error,
}

serialize :: proc(triple: rdf.Triple, data: rawptr) -> bool {
	state := cast(^Serialize_State)data
	state.error = rdfxml.write_document_triple(state.writer, triple)
	return state.error == .None
}

main :: proc() {
	namespaces := []rdfxml.Namespace{
		{prefix = "ex", iri = "https://example.com/"},
		{prefix = "v", iri = "https://example.com/vocab/"},
	}
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	writer: rdfxml.Document_Writer
	if err := rdfxml.init_document_writer(&writer, &builder, rdfxml.Document_Writer_Options{namespaces = namespaces, max_blank_nodes = 1_000}); err != .None {
		fmt.eprintln(rdfxml.write_error_message(err))
		return
	}
	defer rdfxml.destroy_document_writer(&writer)

	input := `<https://example.com/alice> <https://example.com/vocab/name> "Alice"@en .
<https://example.com/alice> <https://example.com/vocab/knows> _:bob .
_:bob <https://example.com/vocab/name> "Bob" .`
	state := Serialize_State{writer = &writer}
	if err := ntriples.parse(input, serialize, &state); err.code != .None {
		fmt.eprintf("line %d, column %d: %s\n", err.line, err.column, ntriples.parse_error_message(err.code))
		return
	}
	if state.error != .None {
		fmt.eprintln(rdfxml.write_error_message(state.error))
		return
	}
	if err := rdfxml.finish_document_writer(&writer); err != .None {
		fmt.eprintln(rdfxml.write_error_message(err))
		return
	}
	fmt.print(strings.to_string(builder))
}
