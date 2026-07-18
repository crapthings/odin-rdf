package trig

import "core:strings"
import "core:testing"
import rdf ".."
import turtle "../turtle"

@(private) Writer_Collect_State :: struct {
	quads: [dynamic]rdf.Quad,
}

@(private) collect_writer_quad :: proc(quad: rdf.Quad, data: rawptr) -> bool {
	state := cast(^Writer_Collect_State)data
	append(&state.quads, quad)
	return true
}

@(test)
test_writer_serializes_default_and_named_graphs_and_roundtrips :: proc(t: ^testing.T) {
	default_quad := rdf.default_graph_quad(rdf.Triple{rdf.iri("https://example.test/default"), rdf.iri("https://example.test/p"), rdf.literal("default")})
	named_quad := rdf.named_graph_quad(rdf.Triple{rdf.iri("https://example.test/s"), rdf.iri("https://example.test/p"), rdf.typed_literal("Ada", "https://example.test/Name")}, rdf.blank_node("graph"))
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	testing.expect_value(t, write_quad(&builder, default_quad), Write_Error.None)
	testing.expect_value(t, write_quad(&builder, named_quad), Write_Error.None)
	expected := "<https://example.test/default> <https://example.test/p> \"default\" .\n_:graph { <https://example.test/s> <https://example.test/p> \"Ada\"^^<https://example.test/Name> . }\n"
	testing.expect_value(t, strings.to_string(builder), expected)

	state: Writer_Collect_State
	defer delete(state.quads)
	parse_err := parse(strings.to_string(builder), collect_writer_quad, {}, &state)
	testing.expect_value(t, parse_err.code, Error_Code.None)
	testing.expect_value(t, len(state.quads), 2)
	if len(state.quads) == 2 {
		testing.expect(t, !state.quads[0].has_graph)
		testing.expect_value(t, state.quads[0].object.value, "default")
		testing.expect(t, state.quads[1].has_graph)
		testing.expect_value(t, state.quads[1].graph.kind, rdf.Term_Kind.Blank_Node)
		testing.expect_value(t, state.quads[1].graph.value, "graph")
		testing.expect_value(t, state.quads[1].object.datatype, "https://example.test/Name")
	}
}

@(test)
test_writer_prefixes_are_shared_with_turtle :: proc(t: ^testing.T) {
	prefixes := []turtle.Prefix{{label = "ex", namespace = "https://example.test/"}}
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	testing.expect_value(t, write_prefixes(&builder, prefixes), Write_Error.None)
	quad := rdf.named_graph_quad(rdf.Triple{rdf.iri("https://example.test/s"), rdf.iri("https://example.test/p"), rdf.iri("https://example.test/o")}, rdf.iri("https://example.test/g"))
	testing.expect_value(t, write_quad(&builder, quad, Writer_Options{prefixes = prefixes}), Write_Error.None)
	testing.expect_value(t, strings.to_string(builder), "@prefix ex: <https://example.test/> .\nex:g { ex:s ex:p ex:o . }\n")
	state: Writer_Collect_State
	defer delete(state.quads)
	parse_err := parse(strings.to_string(builder), collect_writer_quad, {}, &state)
	testing.expect_value(t, parse_err.code, Error_Code.None)
	testing.expect_value(t, len(state.quads), 1)
}

@(test)
test_writer_is_atomic_for_invalid_options_and_quad :: proc(t: ^testing.T) {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	strings.write_string(&builder, "prefix")
	invalid_options := Writer_Options{prefixes = []turtle.Prefix{{label = "bad.", namespace = "urn:example:"}}}
	quad := rdf.default_graph_quad(rdf.Triple{rdf.iri("urn:s"), rdf.iri("urn:p"), rdf.iri("urn:o")})
	testing.expect_value(t, write_quad(&builder, quad, invalid_options), Write_Error.Invalid_Prefix_Label)
	testing.expect_value(t, strings.to_string(builder), "prefix")
	testing.expect_value(t, write_quad(&builder, rdf.named_graph_quad(rdf.triple(quad), rdf.literal("bad"))), Write_Error.Invalid_Graph)
	testing.expect_value(t, strings.to_string(builder), "prefix")
}

@(test)
test_write_error_messages_are_stable :: proc(t: ^testing.T) {
	messages := [Write_Error]string{
		.None                      = "no error",
		.Invalid_Prefix_Label      = "invalid TriG prefix label",
		.Invalid_Prefix_Namespace  = "prefix namespace must be an absolute IRI",
		.Duplicate_Prefix          = "duplicate TriG prefix label",
		.Invalid_Triple            = "quad contains an invalid RDF triple",
		.Invalid_Graph             = "graph name must be an IRI or blank node",
		.Invalid_Term_Kind         = "invalid RDF term kind",
		.Invalid_Subject           = "subject must be an IRI or blank node",
		.Invalid_Predicate         = "predicate must be an IRI",
		.Invalid_IRI               = "invalid absolute IRI",
		.Invalid_Blank_Node        = "invalid blank-node label",
		.Invalid_Language_Tag      = "invalid language tag",
		.Invalid_UTF8              = "invalid UTF-8",
		.Unexpected_Language       = "language tag is only valid on a literal",
		.Unexpected_Datatype       = "datatype is only valid on a literal",
		.Missing_Literal_Datatype  = "literal datatype is required",
		.Invalid_Language_Datatype = "language-tagged literal must use rdf:langString",
		.Ambiguous_Blank_Node_Label = "blank-node label refers to multiple source scopes",
	}
	for code in Write_Error do testing.expect_value(t, write_error_message(code), messages[code])
}
