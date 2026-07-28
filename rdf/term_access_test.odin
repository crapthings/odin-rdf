package rdf

import "core:testing"

@(test)
test_term_accessors_preserve_rdf_identity_fields :: proc(t: ^testing.T) {
	iri_term := iri("urn:concept")
	label := language_literal("数据最小化", "zh")
	typed := typed_literal("42", "http://www.w3.org/2001/XMLSchema#integer")
	testing.expect(t, term_kind(iri_term) == .IRI)
	testing.expect_value(t, term_value(iri_term), "urn:concept")
	testing.expect_value(t, term_language(iri_term), "")
	testing.expect_value(t, term_datatype(iri_term), "")
	testing.expect(t, term_kind(label) == .Literal)
	testing.expect_value(t, term_value(label), "数据最小化")
	testing.expect_value(t, term_language(label), "zh")
	testing.expect_value(t, term_datatype(label), RDF_LANG_STRING)
	testing.expect_value(t, term_datatype(typed), "http://www.w3.org/2001/XMLSchema#integer")
}
