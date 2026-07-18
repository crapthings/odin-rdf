package canon

import "core:strings"
import "core:testing"
import rdf ".."

@(test)
test_canonicalize_assigns_stable_labels_and_sorts :: proc(t: ^testing.T) {
	quads := []rdf.Quad{
		rdf.default_graph_quad(rdf.Triple{rdf.iri("urn:test"), rdf.iri("urn:B"), rdf.blank_node("right", rdf.Blank_Node_Scope(9))}),
		rdf.default_graph_quad(rdf.Triple{rdf.iri("urn:test"), rdf.iri("urn:A"), rdf.blank_node("left", rdf.Blank_Node_Scope(9))}),
	}
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	testing.expect_value(t, canonicalize(&builder, quads), Error_Code.None)
	testing.expect_value(t, strings.to_string(builder), "<urn:test> <urn:A> _:c14n1 .\n<urn:test> <urn:B> _:c14n0 .\n")
}

@(test)
test_canonicalize_treats_input_as_a_dataset_and_is_atomic :: proc(t: ^testing.T) {
	quad := rdf.default_graph_quad(rdf.Triple{rdf.iri("urn:s"), rdf.iri("urn:p"), rdf.blank_node("a", rdf.Blank_Node_Scope(1))})
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	strings.write_string(&builder, "prefix")
	testing.expect_value(t, canonicalize(&builder, []rdf.Quad{quad, quad}), Error_Code.None)
	testing.expect_value(t, strings.to_string(builder), "prefix<urn:s> <urn:p> _:c14n0 .\n")

	invalid := rdf.default_graph_quad(rdf.Triple{rdf.literal("not a subject"), rdf.iri("urn:p"), rdf.iri("urn:o")})
	testing.expect_value(t, canonicalize(&builder, []rdf.Quad{invalid}), Error_Code.Invalid_Quad)
	testing.expect_value(t, strings.to_string(builder), "prefix<urn:s> <urn:p> _:c14n0 .\n")
}

@(test)
test_canonicalize_uses_rdfc_control_escaping_and_limits :: proc(t: ^testing.T) {
	quad := rdf.default_graph_quad(rdf.Triple{rdf.iri("urn:s"), rdf.iri("urn:p"), rdf.literal("\x08\x0b\x7f\t\n\"\\")})
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	testing.expect_value(t, canonicalize(&builder, []rdf.Quad{quad}), Error_Code.None)
	testing.expect_value(t, strings.to_string(builder), "<urn:s> <urn:p> \"\\b\\u000B\\u007F\\t\\n\\\"\\\\\" .\n")

	testing.expect_value(t, canonicalize(&builder, []rdf.Quad{quad}, Options{max_quads = 0 - 1}), Error_Code.Invalid_Option)
	testing.expect_value(t, canonicalize(&builder, []rdf.Quad{quad}, Options{max_quads = 0}), Error_Code.None)
}

@(test)
test_canonical_error_messages_are_stable :: proc(t: ^testing.T) {
	for code in Error_Code {
		expected: string
		switch code {
		case .None:              expected = "no error"
		case .Invalid_Option:    expected = "canonicalization limits must not be negative"
		case .Invalid_Quad:      expected = "invalid RDF quad"
		case .Quad_Limit:        expected = "canonicalization quad limit reached"
		case .Blank_Node_Limit:  expected = "canonicalization blank-node limit reached"
		case .Work_Limit:        expected = "canonicalization work limit reached"
		case .Permutation_Limit: expected = "canonicalization permutation limit reached"
		case .Recursion_Limit:   expected = "canonicalization recursion limit reached"
		case .Out_Of_Memory:     expected = "canonicalization memory allocation failed"
		}
		testing.expect_value(t, error_message(code), expected)
	}
}

@(test)
test_canonical_hash_uses_the_selected_canonicalization_algorithm :: proc(t: ^testing.T) {
	quad := rdf.default_graph_quad(rdf.Triple{rdf.iri("urn:s"), rdf.iri("urn:p"), rdf.literal("value")})
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	strings.write_string(&builder, "prefix")
	testing.expect_value(t, canonical_hash(&builder, []rdf.Quad{quad}), Error_Code.None)
	testing.expect_value(t, strings.to_string(builder), "prefix469b8e68a9f9cc0f0a72e96fb6d3a55595f2fda5f518e79d218b20900b722d9b")

	strings.builder_reset(&builder)
	testing.expect_value(t, canonical_hash(&builder, []rdf.Quad{quad}, Options{hash_algorithm = .SHA_384}), Error_Code.None)
	testing.expect_value(t, strings.to_string(builder), "bd9b9a920a59456f3f84d674a98d6c23caac2706bdf09537e05ca52dbb88fbab7342d7e3b9b31a281c0185c05ceacaec")

	strings.builder_reset(&builder)
	strings.write_string(&builder, "unchanged")
	invalid := rdf.default_graph_quad(rdf.Triple{rdf.literal("not a subject"), rdf.iri("urn:p"), rdf.iri("urn:o")})
	testing.expect_value(t, canonical_hash(&builder, []rdf.Quad{invalid}), Error_Code.Invalid_Quad)
	testing.expect_value(t, strings.to_string(builder), "unchanged")
}

@(test)
test_isomorphic_compares_canonical_forms_not_source_blank_node_labels :: proc(t: ^testing.T) {
	left := []rdf.Quad{
		rdf.default_graph_quad(rdf.Triple{rdf.blank_node("source-left", rdf.Blank_Node_Scope(1)), rdf.iri("urn:p"), rdf.iri("urn:o")}),
		rdf.default_graph_quad(rdf.Triple{rdf.iri("urn:s"), rdf.iri("urn:p"), rdf.blank_node("source-left", rdf.Blank_Node_Scope(1))}),
	}
	right := []rdf.Quad{
		rdf.default_graph_quad(rdf.Triple{rdf.iri("urn:s"), rdf.iri("urn:p"), rdf.blank_node("other-label", rdf.Blank_Node_Scope(99))}),
		rdf.default_graph_quad(rdf.Triple{rdf.blank_node("other-label", rdf.Blank_Node_Scope(99)), rdf.iri("urn:p"), rdf.iri("urn:o")}),
	}
	equal, err := isomorphic(left, right)
	testing.expect_value(t, err, Error_Code.None)
	testing.expect(t, equal)

	different := []rdf.Quad{rdf.default_graph_quad(rdf.Triple{rdf.iri("urn:s"), rdf.iri("urn:p"), rdf.iri("urn:different")})}
	equal, err = isomorphic(left, different)
	testing.expect_value(t, err, Error_Code.None)
	testing.expect(t, !equal)

	invalid := []rdf.Quad{rdf.default_graph_quad(rdf.Triple{rdf.literal("not a subject"), rdf.iri("urn:p"), rdf.iri("urn:o")})}
	equal, err = isomorphic(invalid, right)
	testing.expect(t, !equal)
	testing.expect_value(t, err, Error_Code.Invalid_Quad)
}
