package turtle

import "core:strings"
import "core:testing"
import rdf ".."

@(private) Roundtrip_State :: struct {
	count: int,
	ok: bool,
}

@(private) check_roundtrip_triple :: proc(triple: rdf.Triple, data: rawptr) -> bool {
	state := cast(^Roundtrip_State)data
	state.count += 1
	if triple.subject.value != "https://example.com/alice" || triple.predicate.value != "https://example.com/knows" do return false
	if state.count == 1 {
		state.ok = triple.object.value == "https://example.com/bob"
	} else if state.count == 2 {
		state.ok = triple.object.value == "https://example.com/carol"
	} else {
		state.ok = false
	}
	return true
}

@(test)
test_formatter_groups_orders_and_deduplicates_triples :: proc(t: ^testing.T) {
	ex :: "https://example.com/"
	triples := []rdf.Triple{
		{rdf.iri(ex + "alice"), rdf.iri(ex + "name"), rdf.language_literal("Alice", "en")},
		{rdf.iri(ex + "alice"), rdf.iri(ex + "knows"), rdf.iri(ex + "carol")},
		{rdf.iri(ex + "bob"), rdf.iri(ex + "name"), rdf.literal("Bob")},
		{rdf.iri(ex + "alice"), rdf.iri(RDF_TYPE), rdf.iri(ex + "Person")},
		{rdf.iri(ex + "alice"), rdf.iri(ex + "knows"), rdf.iri(ex + "bob")},
		{rdf.iri(ex + "alice"), rdf.iri(ex + "knows"), rdf.iri(ex + "bob")},
	}
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	err := format_triples(&builder, triples, Format_Options{
		prefixes = []Prefix{{label = "ex", namespace = ex}},
		prefix_policy = .Explicit_Only,
	})
	testing.expect_value(t, err, Write_Error.None)
	expected := `@prefix ex: <https://example.com/> .

ex:alice a ex:Person ;
    ex:knows ex:bob ,
        ex:carol ;
    ex:name "Alice"@en .

ex:bob ex:name "Bob" .
`
	testing.expect_value(t, strings.to_string(builder), expected)
}

@(test)
test_formatter_infers_stable_prefixes :: proc(t: ^testing.T) {
	triples := []rdf.Triple{
		{rdf.iri("https://example.com/alice"), rdf.iri("https://example.com/age"), rdf.typed_literal("37", FORMATTER_XSD_NAMESPACE + "integer")},
	}
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	testing.expect_value(t, format_triples(&builder, triples), Write_Error.None)
	expected := `@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
@prefix ns1: <https://example.com/> .

ns1:alice ns1:age "37"^^xsd:integer .
`
	testing.expect_value(t, strings.to_string(builder), expected)
}

@(test)
test_formatter_is_atomic_for_invalid_graph_data :: proc(t: ^testing.T) {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	strings.write_string(&builder, "existing")
	triples := []rdf.Triple{{rdf.literal("invalid"), rdf.iri("urn:p"), rdf.iri("urn:o")}}
	testing.expect_value(t, format_triples(&builder, triples), Write_Error.Invalid_Subject)
	testing.expect_value(t, strings.to_string(builder), "existing")
}

@(test)
test_formatter_validates_rdf_type_before_using_a_shorthand :: proc(t: ^testing.T) {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	strings.write_string(&builder, "existing")
	invalid_type := rdf.Term{kind = .IRI, value = RDF_TYPE, language = "en"}
	triples := []rdf.Triple{{rdf.iri("urn:s"), invalid_type, rdf.iri("urn:o")}}
	testing.expect_value(t, format_triples(&builder, triples), Write_Error.Unexpected_Language)
	testing.expect_value(t, strings.to_string(builder), "existing")
}

@(test)
test_formatter_rejects_blank_node_label_collisions_between_scopes :: proc(t: ^testing.T) {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	strings.write_string(&builder, "existing")
	first_scope := rdf.Blank_Node_Scope(1)
	second_scope := rdf.Blank_Node_Scope(2)
	triples := []rdf.Triple{
		{rdf.blank_node("node", first_scope), rdf.iri("urn:p"), rdf.iri("urn:o1")},
		{rdf.blank_node("node", second_scope), rdf.iri("urn:p"), rdf.iri("urn:o2")},
	}
	testing.expect_value(t, format_triples(&builder, triples), Write_Error.Ambiguous_Blank_Node_Label)
	testing.expect_value(t, strings.to_string(builder), "existing")
}

@(test)
test_formatter_has_identical_output_for_input_permutations :: proc(t: ^testing.T) {
	first := []rdf.Triple{
		{rdf.iri("urn:alice"), rdf.iri("urn:name"), rdf.literal("Alice")},
		{rdf.iri("urn:bob"), rdf.iri("urn:name"), rdf.literal("Bob")},
	}
	second := []rdf.Triple{first[1], first[0]}
	first_builder := strings.builder_make()
	defer strings.builder_destroy(&first_builder)
	second_builder := strings.builder_make()
	defer strings.builder_destroy(&second_builder)
	options := Format_Options{prefix_policy = .Explicit_Only}
	testing.expect_value(t, format_triples(&first_builder, first, options), Write_Error.None)
	testing.expect_value(t, format_triples(&second_builder, second, options), Write_Error.None)
	testing.expect_value(t, strings.to_string(first_builder), strings.to_string(second_builder))
}

@(test)
test_formatter_output_parses_to_the_same_triples :: proc(t: ^testing.T) {
	triples := []rdf.Triple{
		{rdf.iri("https://example.com/alice"), rdf.iri("https://example.com/knows"), rdf.iri("https://example.com/carol")},
		{rdf.iri("https://example.com/alice"), rdf.iri("https://example.com/knows"), rdf.iri("https://example.com/bob")},
	}
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	testing.expect_value(t, format_triples(&builder, triples), Write_Error.None)
	state := Roundtrip_State{ok = true}
	err := parse(strings.to_string(builder), check_roundtrip_triple, {}, &state)
	testing.expect_value(t, err.code, Error_Code.None)
	testing.expect_value(t, state.count, 2)
	testing.expect(t, state.ok)
}
