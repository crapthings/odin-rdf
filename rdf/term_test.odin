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
}
