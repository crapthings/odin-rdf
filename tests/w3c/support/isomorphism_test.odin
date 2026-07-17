package support

import "core:testing"
import rdf "../../../rdf"

@(test)
test_graph_isomorphism_renames_blank_nodes_and_ignores_order :: proc(t: ^testing.T) {
	left_scope := rdf.new_blank_node_scope()
	right_scope := rdf.new_blank_node_scope()
	left := [2]rdf.Triple{
		{rdf.blank_node("a", left_scope), rdf.iri("urn:p"), rdf.blank_node("b", left_scope)},
		{rdf.blank_node("b", left_scope), rdf.iri("urn:q"), rdf.literal("value")},
	}
	right := [2]rdf.Triple{
		{rdf.blank_node("y", right_scope), rdf.iri("urn:q"), rdf.literal("value")},
		{rdf.blank_node("x", right_scope), rdf.iri("urn:p"), rdf.blank_node("y", right_scope)},
	}
	testing.expect(t, graph_isomorphic(left[:], right[:]))
}

@(test)
test_graph_isomorphism_rejects_non_isomorphic_graphs :: proc(t: ^testing.T) {
	left_scope := rdf.new_blank_node_scope()
	right_scope := rdf.new_blank_node_scope()
	left := [2]rdf.Triple{
		{rdf.blank_node("a", left_scope), rdf.iri("urn:p"), rdf.literal("one")},
		{rdf.blank_node("a", left_scope), rdf.iri("urn:p"), rdf.literal("two")},
	}
	different := [2]rdf.Triple{
		{rdf.blank_node("x", right_scope), rdf.iri("urn:p"), rdf.literal("one")},
		{rdf.blank_node("y", right_scope), rdf.iri("urn:p"), rdf.literal("two")},
	}
	testing.expect(t, !graph_isomorphic(left[:], different[:]))
}

@(test)
test_graph_isomorphism_handles_ground_graphs :: proc(t: ^testing.T) {
	left := [1]rdf.Triple{{rdf.iri("urn:s"), rdf.iri("urn:p"), rdf.literal("o")}}
	same := [1]rdf.Triple{{rdf.iri("urn:s"), rdf.iri("urn:p"), rdf.literal("o")}}
	different := [1]rdf.Triple{{rdf.iri("urn:s"), rdf.iri("urn:p"), rdf.literal("x")}}
	testing.expect(t, graph_isomorphic(left[:], same[:]))
	testing.expect(t, !graph_isomorphic(left[:], different[:]))
}

@(test)
test_graph_isomorphism_ignores_duplicate_statements :: proc(t: ^testing.T) {
	triple := rdf.Triple{rdf.iri("urn:s"), rdf.iri("urn:p"), rdf.literal("o")}
	left := [2]rdf.Triple{triple, triple}
	right := [1]rdf.Triple{triple}
	testing.expect(t, graph_isomorphic(left[:], right[:]))
}
