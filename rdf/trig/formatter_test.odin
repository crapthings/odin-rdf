package trig

import "core:strings"
import "core:testing"
import rdf ".."
import turtle "../turtle"

@(private) Formatter_Collect_State :: struct {
	quads: [dynamic]rdf.Quad,
}

@(private) collect_formatted_quad :: proc(quad: rdf.Quad, data: rawptr) -> bool {
	state := cast(^Formatter_Collect_State)data
	append(&state.quads, quad)
	return true
}

@(test)
test_formatter_groups_graphs_triples_and_duplicates :: proc(t: ^testing.T) {
	ex :: "https://example.test/"
	quads := []rdf.Quad{
		rdf.named_graph_quad(rdf.Triple{rdf.iri(ex + "alice"), rdf.iri(ex + "knows"), rdf.iri(ex + "carol")}, rdf.iri(ex + "people")),
		rdf.default_graph_quad(rdf.Triple{rdf.iri(ex + "about"), rdf.iri(ex + "name"), rdf.literal("Dataset")}),
		rdf.named_graph_quad(rdf.Triple{rdf.iri(ex + "alice"), rdf.iri(FORMAT_RDF_TYPE), rdf.iri(ex + "Person")}, rdf.iri(ex + "people")),
		rdf.named_graph_quad(rdf.Triple{rdf.iri(ex + "alice"), rdf.iri(ex + "knows"), rdf.iri(ex + "bob")}, rdf.iri(ex + "people")),
		rdf.named_graph_quad(rdf.Triple{rdf.iri(ex + "alice"), rdf.iri(ex + "knows"), rdf.iri(ex + "bob")}, rdf.iri(ex + "people")),
	}
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	err := format_quads(&builder, quads, Format_Options{
		prefixes = []turtle.Prefix{{label = "ex", namespace = ex}},
		prefix_policy = .Explicit_Only,
	})
	testing.expect_value(t, err, Write_Error.None)
	expected := `@prefix ex: <https://example.test/> .

ex:about ex:name "Dataset" .

ex:people {
  ex:alice a ex:Person ;
      ex:knows ex:bob ,
          ex:carol .
}
`
	testing.expect_value(t, strings.to_string(builder), expected)
}

@(test)
test_formatter_infers_prefixes_including_graph_names_and_roundtrips :: proc(t: ^testing.T) {
	quads := []rdf.Quad{
		rdf.default_graph_quad(rdf.Triple{rdf.iri("https://example.test/default"), rdf.iri("https://example.test/name"), rdf.typed_literal("7", FORMAT_XSD_NAMESPACE + "integer")}),
		rdf.named_graph_quad(rdf.Triple{rdf.iri("https://example.test/alice"), rdf.iri("https://example.test/knows"), rdf.iri("https://example.test/bob")}, rdf.iri("https://graphs.test/people")),
	}
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	testing.expect_value(t, format_quads(&builder, quads), Write_Error.None)
	expected := `@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
@prefix ns1: <https://example.test/> .
@prefix ns2: <https://graphs.test/> .

ns1:default ns1:name "7"^^xsd:integer .

ns2:people {
  ns1:alice ns1:knows ns1:bob .
}
`
	testing.expect_value(t, strings.to_string(builder), expected)
	state: Formatter_Collect_State
	defer delete(state.quads)
	parse_err := parse(strings.to_string(builder), collect_formatted_quad, {}, &state)
	testing.expect_value(t, parse_err.code, Error_Code.None)
	testing.expect_value(t, len(state.quads), 2)
	if len(state.quads) == 2 {
		testing.expect(t, !state.quads[0].has_graph)
		testing.expect(t, state.quads[1].has_graph)
		testing.expect_value(t, state.quads[1].graph.value, "https://graphs.test/people")
	}
}

@(test)
test_formatter_is_atomic_for_invalid_data_and_scope_collisions :: proc(t: ^testing.T) {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	strings.write_string(&builder, "existing")
	invalid := []rdf.Quad{rdf.default_graph_quad(rdf.Triple{rdf.literal("bad"), rdf.iri("urn:p"), rdf.iri("urn:o")})}
	testing.expect_value(t, format_quads(&builder, invalid), Write_Error.Invalid_Triple)
	testing.expect_value(t, strings.to_string(builder), "existing")
	first_scope := rdf.Blank_Node_Scope(1)
	second_scope := rdf.Blank_Node_Scope(2)
	collision := []rdf.Quad{
		rdf.named_graph_quad(rdf.Triple{rdf.iri("urn:s"), rdf.iri("urn:p"), rdf.iri("urn:o")}, rdf.blank_node("graph", first_scope)),
		rdf.named_graph_quad(rdf.Triple{rdf.iri("urn:s"), rdf.iri("urn:p"), rdf.iri("urn:o2")}, rdf.blank_node("graph", second_scope)),
	}
	testing.expect_value(t, format_quads(&builder, collision), Write_Error.Ambiguous_Blank_Node_Label)
	testing.expect_value(t, strings.to_string(builder), "existing")
}

@(test)
test_formatter_has_identical_output_for_input_permutations :: proc(t: ^testing.T) {
	first := []rdf.Quad{
		rdf.named_graph_quad(rdf.Triple{rdf.iri("urn:a"), rdf.iri("urn:p"), rdf.iri("urn:o")}, rdf.iri("urn:g")),
		rdf.default_graph_quad(rdf.Triple{rdf.iri("urn:b"), rdf.iri("urn:p"), rdf.iri("urn:o")}),
	}
	second := []rdf.Quad{first[1], first[0]}
	first_builder := strings.builder_make()
	defer strings.builder_destroy(&first_builder)
	second_builder := strings.builder_make()
	defer strings.builder_destroy(&second_builder)
	options := Format_Options{prefix_policy = .Explicit_Only}
	testing.expect_value(t, format_quads(&first_builder, first, options), Write_Error.None)
	testing.expect_value(t, format_quads(&second_builder, second, options), Write_Error.None)
	testing.expect_value(t, strings.to_string(first_builder), strings.to_string(second_builder))
}
