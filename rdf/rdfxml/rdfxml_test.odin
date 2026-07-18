package rdfxml

import "core:strings"
import "core:testing"
import "core:io"
import rdf ".."
import nquads "../nquads"

@(private) Collect_State :: struct {
	builder: strings.Builder,
	quads:   int,
}

@(private) collect_quad :: proc(quad: rdf.Quad, user_data: rawptr) -> bool {
	state := cast(^Collect_State)user_data
	if nquads.write_quad(&state.builder, quad) != .None do return false
	state.quads += 1
	return true
}

@(private) parse_to_nquads :: proc(input: string, options: Options = {}) -> (string, Parse_Error) {
	state := Collect_State{builder = strings.builder_make()}
	defer strings.builder_destroy(&state.builder)
	err := parse(input, collect_quad, options, &state)
	return strings.clone(strings.to_string(state.builder)) or_else "", err
}

@(test)
test_node_property_and_typed_node :: proc(t: ^testing.T) {
	actual, err := parse_to_nquads(`
<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns:ex="https://example.test/">
  <ex:Person rdf:about="alice" ex:label="Alice">
    <ex:knows rdf:resource="bob"/>
    <ex:age rdf:datatype="https://www.w3.org/2001/XMLSchema#integer">42</ex:age>
  </ex:Person>
</rdf:RDF>`, Options{base_iri = "https://example.test/"})
	defer delete(actual)
	testing.expect_value(t, err.code, Error_Code.None)
	testing.expect(t, strings.contains(actual, `<https://example.test/alice> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <https://example.test/Person> .`))
	testing.expect(t, strings.contains(actual, `<https://example.test/alice> <https://example.test/label> "Alice" .`))
	testing.expect(t, strings.contains(actual, `<https://example.test/alice> <https://example.test/knows> <https://example.test/bob> .`))
	testing.expect(t, strings.contains(actual, `<https://example.test/alice> <https://example.test/age> "42"^^<https://www.w3.org/2001/XMLSchema#integer> .`))
}

@(test)
test_nested_nodes_collections_and_limits :: proc(t: ^testing.T) {
	actual, err := parse_to_nquads(`
<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns:ex="https://example.test/">
  <rdf:Description rdf:about="https://example.test/alice">
    <ex:friend><rdf:Description rdf:nodeID="bob"><ex:name xml:lang="en">Bob</ex:name></rdf:Description></ex:friend>
    <ex:items rdf:parseType="Collection"><rdf:Description rdf:about="one"/><rdf:Description rdf:about="two"/></ex:items>
  </rdf:Description>
</rdf:RDF>`, Options{base_iri = "https://example.test/"})
	defer delete(actual)
	testing.expect_value(t, err.code, Error_Code.None)
	testing.expect(t, strings.contains(actual, `<https://example.test/alice> <https://example.test/friend> _:bob .`))
	testing.expect(t, strings.contains(actual, `_:bob <https://example.test/name> "Bob"@en .`))
	testing.expect(t, strings.contains(actual, `<http://www.w3.org/1999/02/22-rdf-syntax-ns#first> <https://example.test/one> .`))
	limited, limit_err := parse_to_nquads(`<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description/></rdf:RDF>`, Options{max_elements = 1})
	defer delete(limited)
	testing.expect_value(t, limit_err.code, Error_Code.Element_Limit)
}

@(test)
test_invalid_node_and_xml_literal :: proc(t: ^testing.T) {
	root_output, root_err := parse_to_nquads(`<rdf:about xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"/>`)
	defer delete(root_output)
	testing.expect_value(t, root_err.code, Error_Code.Invalid_Node_Element)
	literal_output, literal_err := parse_to_nquads(`<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns:ex="https://example.test/"><rdf:Description><ex:value rdf:parseType="Literal"><em>x</em></ex:value></rdf:Description></rdf:RDF>`)
	defer delete(literal_output)
	testing.expect_value(t, literal_err.code, Error_Code.None)
	testing.expect(t, strings.contains(literal_output, `<em xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\" xmlns:ex=\"https://example.test/\">x</em>`))
	root_text_output, root_text_err := parse_to_nquads(`<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">not allowed</rdf:RDF>`)
	defer delete(root_text_output)
	testing.expect_value(t, root_text_err.code, Error_Code.Invalid_Root)
	node_text_output, node_text_err := parse_to_nquads(`<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description>not allowed</rdf:Description></rdf:RDF>`)
	defer delete(node_text_output)
	testing.expect_value(t, node_text_err.code, Error_Code.Invalid_Node_Element)
}

@(test)
test_xml_literal_preserves_mixed_content_comments_and_attribute_order :: proc(t: ^testing.T) {
	input := `<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns:ex="https://example.test/" xmlns:x="https://markup.test/"><rdf:Description rdf:about="https://example.test/s"><ex:value rdf:parseType="Other">before <!--note--><?keep value?><x:em z="2" a="1"/> after</ex:value></rdf:Description></rdf:RDF>`
	actual, err := parse_to_nquads(input)
	defer delete(actual)
	testing.expect_value(t, err.code, Error_Code.None)
	testing.expect(t, strings.contains(actual, `before <!--note--><?keep value?><x:em xmlns:x=\"https://markup.test/\" a=\"1\" z=\"2\"></x:em> after`))
}

@(test)
test_xml_literal_reader_preserves_content_across_chunks :: proc(t: ^testing.T) {
	input := `<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns:ex="https://example.test/" xmlns:x="https://markup.test/"><rdf:Description rdf:about="https://example.test/s"><ex:value rdf:parseType="Literal">left <x:mark>middle</x:mark> right</ex:value></rdf:Description></rdf:RDF>`
	expected, expected_err := parse_to_nquads(input)
	defer delete(expected)
	testing.expect_value(t, expected_err.code, Error_Code.None)
	reader_state: strings.Reader
	actual_state := Collect_State{builder = strings.builder_make()}
	defer strings.builder_destroy(&actual_state.builder)
	result := parse_reader(strings.to_reader(&reader_state, input), collect_quad, Reader_Options{chunk_size = 1}, &actual_state)
	testing.expect_value(t, result.error.code, Error_Code.None)
	testing.expect_value(t, strings.to_string(actual_state.builder), expected)
}

@(test)
test_reader_retains_one_bounded_document :: proc(t: ^testing.T) {
	input := `<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns:ex="https://example.test/"><rdf:Description rdf:about="https://example.test/alice"><ex:name>Alice</ex:name></rdf:Description></rdf:RDF>`
	reader_state: strings.Reader
	state := Collect_State{builder = strings.builder_make()}
	defer strings.builder_destroy(&state.builder)
	result := parse_reader(strings.to_reader(&reader_state, input), collect_quad, Reader_Options{chunk_size = 3, max_document_bytes = 1024}, &state)
	testing.expect_value(t, result.error.code, Error_Code.None)
	testing.expect_value(t, result.quads, u64(1))
	testing.expect_value(t, result.bytes_read, u64(len(input)))
	invalid_chunk := parse_reader(strings.to_reader(&reader_state, input), collect_quad, Reader_Options{chunk_size = -1}, &state)
	testing.expect_value(t, invalid_chunk.error.code, Error_Code.Invalid_Chunk_Size)
}

@(private) broken_reader_proc :: proc(_: rawptr, mode: io.Stream_Mode, _: []byte, _: i64, _: io.Seek_From) -> (i64, io.Error) {
	if mode == .Read do return 0, .Unknown
	if mode == .Query do return io.query_utility({.Read})
	return 0, .Unsupported
}

@(private) stalled_reader_proc :: proc(_: rawptr, mode: io.Stream_Mode, _: []byte, _: i64, _: io.Seek_From) -> (i64, io.Error) {
	if mode == .Read do return 0, .None
	if mode == .Query do return io.query_utility({.Read})
	return 0, .Unsupported
}

@(test)
test_reader_preserves_io_failures_and_no_progress :: proc(t: ^testing.T) {
	failed := parse_reader(io.Reader{procedure = broken_reader_proc}, collect_quad)
	testing.expect_value(t, failed.error.code, Error_Code.Reader_Error)
	testing.expect_value(t, failed.reader_error, io.Error.Unknown)

	stalled := parse_reader(io.Reader{procedure = stalled_reader_proc}, collect_quad, Reader_Options{chunk_size = 1})
	testing.expect_value(t, stalled.error.code, Error_Code.No_Progress)
	testing.expect_value(t, stalled.reader_error, io.Error.No_Progress)
}

@(test)
test_write_triples_round_trips_terms_and_blank_node_scopes :: proc(t: ^testing.T) {
	shared := rdf.blank_node("source-label", rdf.Blank_Node_Scope(7))
	other := rdf.blank_node("source-label", rdf.Blank_Node_Scope(8))
	triples := [4]rdf.Triple{
		{subject = rdf.iri("https://example.test/s"), predicate = rdf.iri("https://example.test/knows"), object = shared},
		{subject = shared, predicate = rdf.iri("https://example.test/label"), object = rdf.language_literal("B & C", "en")},
		{subject = other, predicate = rdf.iri("https://example.test/count"), object = rdf.typed_literal("42", "https://www.w3.org/2001/XMLSchema#integer")},
		{subject = rdf.iri("https://example.test/s"), predicate = rdf.iri(RDF_TYPE), object = rdf.iri("https://example.test/Person")},
	}
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	testing.expect_value(t, write_triples(&builder, triples[:]), Write_Error.None)
	written := strings.to_string(builder)
	testing.expect(t, strings.contains(written, `<rdf:Description rdf:about="https://example.test/s">`))
	testing.expect(t, strings.contains(written, `<ns:knows xmlns:ns="https://example.test/" rdf:nodeID="b0"/>`))
	testing.expect(t, strings.contains(written, `<rdf:Description rdf:nodeID="b1">`))
	testing.expect(t, strings.contains(written, `B &amp; C`))
	actual, parse_err := parse_to_nquads(written)
	defer delete(actual)
	testing.expect_value(t, parse_err.code, Error_Code.None)
	testing.expect(t, strings.contains(actual, `<https://example.test/s> <https://example.test/knows> _:b0 .`))
	testing.expect(t, strings.contains(actual, `_:b0 <https://example.test/label> "B & C"@en .`))
	testing.expect(t, strings.contains(actual, `_:b1 <https://example.test/count> "42"^^<https://www.w3.org/2001/XMLSchema#integer> .`))
	testing.expect(t, strings.contains(actual, `<https://example.test/s> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <https://example.test/Person> .`))
}

@(test)
test_write_triples_preserves_xml_literal :: proc(t: ^testing.T) {
	triples := [1]rdf.Triple{{
		subject = rdf.iri("https://example.test/s"),
		predicate = rdf.iri("https://example.test/value"),
		object = rdf.typed_literal(`<x:em xmlns:x="https://markup.test/">x</x:em>`, RDF_XML_LITERAL),
	}}
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	testing.expect_value(t, write_triples(&builder, triples[:]), Write_Error.None)
	written := strings.to_string(builder)
	testing.expect(t, strings.contains(written, `rdf:parseType="Literal"><x:em xmlns:x="https://markup.test/">x</x:em>`))
	actual, parse_err := parse_to_nquads(written)
	defer delete(actual)
	testing.expect_value(t, parse_err.code, Error_Code.None)
	testing.expect(t, strings.contains(actual, `<x:em xmlns:x=\"https://markup.test/\">x</x:em>`))
}

@(test)
test_write_triples_fails_atomically_for_unrepresentable_data :: proc(t: ^testing.T) {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	strings.write_string(&builder, "prefix")
	invalid_predicate := [1]rdf.Triple{{
		subject = rdf.iri("https://example.test/s"),
		predicate = rdf.iri("https://example.test/123"),
		object = rdf.literal("value"),
	}}
	testing.expect_value(t, write_triples(&builder, invalid_predicate[:]), Write_Error.Invalid_Property_Name)
	testing.expect_value(t, strings.to_string(builder), "prefix")
	invalid_xml := [1]rdf.Triple{{
		subject = rdf.iri("https://example.test/s"),
		predicate = rdf.iri("https://example.test/value"),
		object = rdf.typed_literal("<unclosed>", RDF_XML_LITERAL),
	}}
	testing.expect_value(t, write_triples(&builder, invalid_xml[:]), Write_Error.Invalid_XML_Literal)
	testing.expect_value(t, strings.to_string(builder), "prefix")
	invalid_character := [1]rdf.Triple{{
		subject = rdf.iri("https://example.test/s"),
		predicate = rdf.iri("https://example.test/value"),
		object = rdf.literal("\x01"),
	}}
	testing.expect_value(t, write_triples(&builder, invalid_character[:]), Write_Error.Invalid_XML_Character)
	testing.expect_value(t, strings.to_string(builder), "prefix")
}

@(test)
test_write_error_messages_are_stable :: proc(t: ^testing.T) {
	codes := [15]Write_Error{
		.None, .Invalid_Term_Kind, .Invalid_Subject, .Invalid_Predicate, .Invalid_IRI,
		.Invalid_Blank_Node, .Invalid_Language_Tag, .Invalid_UTF8, .Unexpected_Language,
		.Unexpected_Datatype, .Missing_Literal_Datatype, .Invalid_Language_Datatype,
		.Invalid_Property_Name, .Reserved_Predicate, .Invalid_XML_Literal,
	}
	messages := [15]string{
		"no error", "invalid RDF term kind", "subject must be an IRI or blank node", "predicate must be an IRI", "invalid absolute IRI",
		"invalid blank-node label", "invalid language tag", "invalid UTF-8", "language tag is only valid on a literal",
		"datatype is only valid on a literal", "literal datatype is required", "language-tagged literal must use rdf:langString",
		"predicate IRI cannot be represented as an RDF/XML QName", "predicate is reserved by RDF/XML syntax", "rdf:XMLLiteral value is not a valid XML fragment",
	}
	for code, index in codes do testing.expect_value(t, write_error_message(code), messages[index])
	testing.expect_value(t, write_error_message(.Invalid_XML_Character), "RDF term contains a character not representable in XML 1.0")
}
