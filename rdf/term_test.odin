package rdf

import "core:testing"

@(test)
test_term_structure_validation :: proc(t: ^testing.T) {
	testing.expect_value(t, validate_term_structure(iri("urn:x")), Term_Structure_Error.None)
	testing.expect_value(t, validate_term_structure(blank_node("x")), Term_Structure_Error.None)
	testing.expect_value(t, validate_term_structure(literal("x")), Term_Structure_Error.None)
	testing.expect_value(t, validate_term_structure(language_literal("x", "en")), Term_Structure_Error.None)
	testing.expect_value(t, validate_term_structure(typed_literal("1", "urn:type")), Term_Structure_Error.None)

	testing.expect_value(t, validate_term_structure(Term{kind = .Literal, value = "x"}), Term_Structure_Error.Missing_Datatype)
	testing.expect_value(t, validate_term_structure(Term{kind = .Literal, value = "x", datatype = RDF_LANG_STRING}), Term_Structure_Error.Invalid_Language_Datatype)
	testing.expect_value(t, validate_term_structure(Term{kind = .IRI, value = "urn:x", language = "en"}), Term_Structure_Error.Unexpected_Language)
}

@(test)
test_triple_structure_validation :: proc(t: ^testing.T) {
	valid := Triple{blank_node("s"), iri("urn:p"), literal("o")}
	testing.expect_value(t, validate_triple_structure(valid), Triple_Structure_Error.None)
	testing.expect_value(t, validate_triple_structure(Triple{literal("s"), iri("urn:p"), literal("o")}), Triple_Structure_Error.Invalid_Subject)
	testing.expect_value(t, validate_triple_structure(Triple{iri("urn:s"), blank_node("p"), literal("o")}), Triple_Structure_Error.Invalid_Predicate)
	generalized := Triple{iri("urn:s"), blank_node("p"), literal("o")}
	testing.expect_value(t, validate_generalized_triple_structure(generalized), Triple_Structure_Error.None)
	testing.expect_value(t, validate_generalized_quad_structure(default_graph_quad(generalized)), Quad_Structure_Error.None)
}

@(test)
test_structure_error_messages_are_stable :: proc(t: ^testing.T) {
	term_messages := [Term_Structure_Error]string{
		.None                      = "no error",
		.Invalid_Term_Kind         = "invalid RDF term kind",
		.Unexpected_Language       = "language tag is only valid on a literal",
		.Unexpected_Datatype       = "datatype is only valid on a literal",
		.Missing_Datatype          = "literal datatype is required",
		.Invalid_Language_Datatype = "language-tagged literal must use rdf:langString",
	}
	for code in Term_Structure_Error {
		testing.expect_value(t, term_structure_error_message(code), term_messages[code])
	}

	triple_messages := [Triple_Structure_Error]string{
		.None                   = "no error",
		.Invalid_Subject        = "subject must be an IRI or blank node",
		.Invalid_Predicate      = "predicate must be an IRI",
		.Invalid_Subject_Term   = "subject has invalid term structure",
		.Invalid_Predicate_Term = "predicate has invalid term structure",
		.Invalid_Object_Term    = "object has invalid term structure",
	}
	for code in Triple_Structure_Error {
		testing.expect_value(t, triple_structure_error_message(code), triple_messages[code])
	}

	quad_messages := [Quad_Structure_Error]string{
		.None               = "no error",
		.Invalid_Triple     = "quad contains an invalid RDF triple",
		.Invalid_Graph      = "graph name must be an IRI or blank node",
		.Invalid_Graph_Term = "graph name has invalid term structure",
	}
	for code in Quad_Structure_Error {
		testing.expect_value(t, quad_structure_error_message(code), quad_messages[code])
	}
}

@(test)
test_quad_structure_and_default_graph :: proc(t: ^testing.T) {
	statement := Triple{blank_node("s"), iri("urn:p"), literal("o")}
	default_quad := default_graph_quad(statement)
	testing.expect(t, !default_quad.has_graph)
	testing.expect_value(t, validate_quad_structure(default_quad), Quad_Structure_Error.None)
	testing.expect_value(t, triple(default_quad), statement)
	default_quad.graph = literal("ignored")
	testing.expect_value(t, validate_quad_structure(default_quad), Quad_Structure_Error.None)

	named_quad := named_graph_quad(statement, iri("urn:g"))
	testing.expect(t, named_quad.has_graph)
	testing.expect_value(t, validate_quad_structure(named_quad), Quad_Structure_Error.None)

	bad_graph := named_graph_quad(statement, literal("graph"))
	testing.expect_value(t, validate_quad_structure(bad_graph), Quad_Structure_Error.Invalid_Graph)
}

@(test)
test_blank_node_scope_generator_is_nonzero_and_unique :: proc(t: ^testing.T) {
	first := new_blank_node_scope()
	second := new_blank_node_scope()
	testing.expect(t, first != Blank_Node_Scope(0))
	testing.expect(t, second != Blank_Node_Scope(0))
	testing.expect(t, first != second)
}
