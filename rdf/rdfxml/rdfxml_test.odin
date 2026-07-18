package rdfxml

import "core:strings"
import "core:testing"
import "core:io"
import rdf ".."
import nquads "../nquads"
import ntriples "../ntriples"

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

@(private) Document_Write_State :: struct {
	writer: ^Document_Writer,
	error:  Write_Error,
}

@(private) write_document_sink :: proc(triple: rdf.Triple, user_data: rawptr) -> bool {
	state := cast(^Document_Write_State)user_data
	state.error = write_document_triple(state.writer, triple)
	return state.error == .None
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
test_document_writer_streams_explicit_namespaces_and_blank_nodes :: proc(t: ^testing.T) {
	namespaces := []Namespace{{prefix = "ex", iri = "https://example.test/"}}
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	writer: Document_Writer
	testing.expect_value(t, init_document_writer(&writer, &builder, Document_Writer_Options{namespaces = namespaces, max_blank_nodes = 2}), Write_Error.None)
	defer destroy_document_writer(&writer)
	shared := rdf.blank_node("callback-label", rdf.Blank_Node_Scope(9))
	testing.expect_value(t, write_document_triple(&writer, rdf.Triple{
		subject = rdf.iri("https://example.test/s"),
		predicate = rdf.iri("https://example.test/knows"),
		object = shared,
	}), Write_Error.None)
	testing.expect_value(t, write_document_triple(&writer, rdf.Triple{
		subject = shared,
		predicate = rdf.iri("https://example.test/label"),
		object = rdf.language_literal("B & C", "en"),
	}), Write_Error.None)
	testing.expect_value(t, write_document_triple(&writer, rdf.Triple{
		subject = rdf.iri("https://example.test/s"),
		predicate = rdf.iri(RDF_TYPE),
		object = rdf.iri("https://example.test/Person"),
	}), Write_Error.None)
	testing.expect_value(t, finish_document_writer(&writer), Write_Error.None)
	written := strings.to_string(builder)
	testing.expect(t, strings.contains(written, `<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns:ex="https://example.test/">`))
	testing.expect(t, strings.contains(written, `<ex:knows rdf:nodeID="b0"/>`))
	testing.expect(t, strings.contains(written, `<ex:label xml:lang="en">B &amp; C</ex:label>`))
	testing.expect(t, strings.contains(written, `<rdf:type rdf:resource="https://example.test/Person"/>`))
	actual, parse_err := parse_to_nquads(written)
	defer delete(actual)
	testing.expect_value(t, parse_err.code, Error_Code.None)
	testing.expect(t, strings.contains(actual, `<https://example.test/s> <https://example.test/knows> _:b0 .`))
	testing.expect(t, strings.contains(actual, `_:b0 <https://example.test/label> "B & C"@en .`))
}

@(test)
test_document_writer_owns_blank_nodes_from_reused_reader_callbacks :: proc(t: ^testing.T) {
	namespaces := []Namespace{{prefix = "ex", iri = "https://example.test/"}}
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	writer: Document_Writer
	testing.expect_value(t, init_document_writer(&writer, &builder, Document_Writer_Options{namespaces = namespaces, max_blank_nodes = 1}), Write_Error.None)
	defer destroy_document_writer(&writer)
	input := "<https://example.test/s> <https://example.test/knows> _:shared .\n_:shared <https://example.test/label> \"value\" .\n"
	reader_state: strings.Reader
	state := Document_Write_State{writer = &writer}
	parsed := ntriples.parse_reader(strings.to_reader(&reader_state, input), write_document_sink, ntriples.Reader_Options{chunk_size = 1}, &state)
	testing.expect_value(t, parsed.error.code, ntriples.Error_Code.None)
	testing.expect_value(t, state.error, Write_Error.None)
	testing.expect_value(t, finish_document_writer(&writer), Write_Error.None)
	written := strings.to_string(builder)
	testing.expect(t, strings.contains(written, `<ex:knows rdf:nodeID="b0"/>`))
	testing.expect(t, strings.contains(written, `<rdf:Description rdf:nodeID="b0">`))
}

@(test)
test_document_writer_rejects_bad_records_without_partial_output :: proc(t: ^testing.T) {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	strings.write_string(&builder, "prefix")
	invalid_namespaces := []Namespace{{prefix = "1bad", iri = "https://example.test/"}}
	writer: Document_Writer
	testing.expect_value(t, init_document_writer(&writer, &builder, Document_Writer_Options{namespaces = invalid_namespaces}), Write_Error.Invalid_Namespace_Prefix)
	testing.expect_value(t, strings.to_string(builder), "prefix")
	namespaces := []Namespace{{prefix = "ex", iri = "https://example.test/"}}
	testing.expect_value(t, init_document_writer(&writer, &builder, Document_Writer_Options{namespaces = namespaces, max_blank_nodes = 1}), Write_Error.None)
	defer destroy_document_writer(&writer)
	first := rdf.Triple{
		subject = rdf.blank_node("one", rdf.Blank_Node_Scope(1)),
		predicate = rdf.iri("https://example.test/value"),
		object = rdf.literal("first"),
	}
	testing.expect_value(t, write_document_triple(&writer, first), Write_Error.None)
	before := strings.clone(strings.to_string(builder)) or_else ""
	defer delete(before)
	missing_namespace := rdf.Triple{
		subject = rdf.iri("https://example.test/s"),
		predicate = rdf.iri("https://other.test/value"),
		object = rdf.literal("value"),
	}
	testing.expect_value(t, write_document_triple(&writer, missing_namespace), Write_Error.Missing_Predicate_Namespace)
	testing.expect_value(t, strings.to_string(builder), before)
	limited := rdf.Triple{
		subject = rdf.blank_node("two", rdf.Blank_Node_Scope(1)),
		predicate = rdf.iri("https://example.test/value"),
		object = rdf.literal("second"),
	}
	testing.expect_value(t, write_document_triple(&writer, limited), Write_Error.Blank_Node_Limit)
	testing.expect_value(t, strings.to_string(builder), before)
	testing.expect_value(t, write_document_triple(&writer, first), Write_Error.None)
	testing.expect_value(t, finish_document_writer(&writer), Write_Error.None)
	testing.expect_value(t, finish_document_writer(&writer), Write_Error.Writer_Closed)
	testing.expect_value(t, write_document_triple(&writer, first), Write_Error.Writer_Closed)
}

@(test)
test_document_writer_validates_namespace_and_capacity_options_before_output :: proc(t: ^testing.T) {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	strings.write_string(&builder, "prefix")
	writer: Document_Writer
	testing.expect_value(t, init_document_writer(&writer, nil), Write_Error.Missing_Output)
	testing.expect_value(t, init_document_writer(&writer, &builder, Document_Writer_Options{max_blank_nodes = -1}), Write_Error.Invalid_Writer_Options)
	reserved := []Namespace{{prefix = "rdf", iri = "https://example.test/"}}
	testing.expect_value(t, init_document_writer(&writer, &builder, Document_Writer_Options{namespaces = reserved}), Write_Error.Reserved_Namespace_Prefix)
	duplicate := []Namespace{
		{prefix = "ex", iri = "https://one.test/"},
		{prefix = "ex", iri = "https://two.test/"},
	}
	testing.expect_value(t, init_document_writer(&writer, &builder, Document_Writer_Options{namespaces = duplicate}), Write_Error.Duplicate_Namespace_Prefix)
	invalid_iri := []Namespace{{prefix = "ex", iri = "relative"}}
	testing.expect_value(t, init_document_writer(&writer, &builder, Document_Writer_Options{namespaces = invalid_iri}), Write_Error.Invalid_Namespace_IRI)
	testing.expect_value(t, strings.to_string(builder), "prefix")
}

@(test)
test_xml_ncname_validation_accepts_combining_marks_only_after_start :: proc(t: ^testing.T) {
	testing.expect(t, valid_xml_name("é\u0301"))
	testing.expect(t, valid_xml_name("A\u203Fname"))
	testing.expect(t, !valid_xml_name("\u0301bad"))
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	valid := [1]rdf.Triple{{
		subject = rdf.iri("https://example.test/s"),
		predicate = rdf.iri("https://example.test/é\u0301"),
		object = rdf.literal("value"),
	}}
	testing.expect_value(t, write_triples(&builder, valid[:]), Write_Error.None)
	invalid := [1]rdf.Triple{{
		subject = rdf.iri("https://example.test/s"),
		predicate = rdf.iri("https://example.test/\u0301bad"),
		object = rdf.literal("value"),
	}}
	before := strings.clone(strings.to_string(builder)) or_else ""
	defer delete(before)
	testing.expect_value(t, write_triples(&builder, invalid[:]), Write_Error.Invalid_Property_Name)
	testing.expect_value(t, strings.to_string(builder), before)
}

@(test)
test_write_error_messages_are_stable :: proc(t: ^testing.T) {
	messages := [Write_Error]string{
		.None                        = "no error",
		.Invalid_Term_Kind           = "invalid RDF term kind",
		.Invalid_Subject             = "subject must be an IRI or blank node",
		.Invalid_Predicate           = "predicate must be an IRI",
		.Invalid_IRI                 = "invalid absolute IRI",
		.Invalid_Blank_Node          = "invalid blank-node label",
		.Invalid_Language_Tag        = "invalid language tag",
		.Invalid_UTF8                = "invalid UTF-8",
		.Unexpected_Language         = "language tag is only valid on a literal",
		.Unexpected_Datatype         = "datatype is only valid on a literal",
		.Missing_Literal_Datatype    = "literal datatype is required",
		.Invalid_Language_Datatype   = "language-tagged literal must use rdf:langString",
		.Invalid_Property_Name       = "predicate IRI cannot be represented as an RDF/XML QName",
		.Reserved_Predicate          = "predicate is reserved by RDF/XML syntax",
		.Invalid_XML_Literal         = "rdf:XMLLiteral value is not a valid XML fragment",
		.Invalid_XML_Character       = "RDF term contains a character not representable in XML 1.0",
		.Missing_Output              = "output builder is required",
		.Invalid_Writer_Options      = "writer options must not be negative",
		.Invalid_Namespace_Prefix    = "namespace prefix must be an XML NCName",
		.Invalid_Namespace_IRI       = "namespace IRI must be an absolute XML-safe IRI",
		.Duplicate_Namespace_Prefix  = "duplicate namespace prefix",
		.Reserved_Namespace_Prefix   = "namespace prefix is reserved by XML or RDF/XML",
		.Missing_Predicate_Namespace = "predicate namespace has no declared prefix",
		.Blank_Node_Limit            = "blank-node limit reached",
		.Writer_Not_Active           = "RDF/XML document writer is not active",
		.Writer_Already_Active       = "RDF/XML document writer is already active",
		.Writer_Closed               = "RDF/XML document writer is already closed",
		.Out_Of_Memory               = "memory allocation failed",
	}
	for code in Write_Error do testing.expect_value(t, write_error_message(code), messages[code])
}
