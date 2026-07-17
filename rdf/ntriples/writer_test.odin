package ntriples

import "core:strings"
import "core:testing"
import rdf ".."

@(private) Roundtrip_State :: struct { ok: bool }

@(private) check_roundtrip :: proc(triple: rdf.Triple, data: rawptr) -> bool {
	state := cast(^Roundtrip_State)data
	state.ok = triple.subject.value == "urn:subject" &&
		triple.predicate.value == "urn:predicate" &&
		triple.object.value == "quote\" slash\\ line\n tab\t ☃" &&
		triple.object.language == "en-US"
	return true
}

@(test)
test_writer_roundtrip_and_escaping :: proc(t: ^testing.T) {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	triple := rdf.Triple{
		rdf.iri("urn:subject"),
		rdf.iri("urn:predicate"),
		rdf.language_literal("quote\" slash\\ line\n tab\t ☃", "en-US"),
	}
	write_err := write_triple(&builder, triple)
	testing.expect_value(t, write_err, Write_Error.None)
	testing.expect_value(t, strings.to_string(builder), `<urn:subject> <urn:predicate> "quote\" slash\\ line\n tab\t ☃"@en-US .
`)
	state: Roundtrip_State
	parse_err := parse(strings.to_string(builder), check_roundtrip, &state)
	testing.expect_value(t, parse_err.code, Error_Code.None)
	testing.expect(t, state.ok)
}

@(test)
test_writer_escapes_forbidden_iri_characters :: proc(t: ^testing.T) {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	triple := rdf.Triple{rdf.iri("urn:s"), rdf.iri("urn:p"), rdf.iri("urn:has space")}
	err := write_triple(&builder, triple)
	testing.expect_value(t, err, Write_Error.None)
	testing.expect_value(t, strings.to_string(builder), "<urn:s> <urn:p> <urn:has\\u0020space> .\n")
}

@(private) Write_Case :: struct { triple: rdf.Triple, code: Write_Error }

@(test)
test_writer_rejects_invalid_terms :: proc(t: ^testing.T) {
	cases := []Write_Case{
		{rdf.Triple{rdf.literal("x"), rdf.iri("urn:p"), rdf.iri("urn:o")}, .Invalid_Subject},
		{rdf.Triple{rdf.iri("urn:s"), rdf.blank_node("p"), rdf.iri("urn:o")}, .Invalid_Predicate},
		{rdf.Triple{rdf.iri("relative"), rdf.iri("urn:p"), rdf.iri("urn:o")}, .Invalid_IRI},
		{rdf.Triple{rdf.iri("urn:s"), rdf.iri("urn:p"), rdf.blank_node("bad.")}, .Invalid_Blank_Node},
		{rdf.Triple{rdf.iri("urn:s"), rdf.iri("urn:p"), rdf.language_literal("x", "en-")}, .Invalid_Language_Tag},
		{rdf.Triple{rdf.iri("urn:s"), rdf.iri("urn:p"), rdf.Term{kind = .Literal, value = "x", language = "en", datatype = "urn:type"}}, .Invalid_Language_Datatype},
		{rdf.Triple{rdf.iri("urn:s"), rdf.iri("urn:p"), rdf.Term{kind = .Literal, value = "x"}}, .Missing_Literal_Datatype},
		{rdf.Triple{rdf.iri("urn:s"), rdf.iri("urn:p"), rdf.Term{kind = .IRI, value = "urn:o", language = "en"}}, .Unexpected_Language},
		{rdf.Triple{rdf.iri("urn:s"), rdf.iri("urn:p"), rdf.Term{kind = .Blank_Node, value = "o", datatype = "urn:type"}}, .Unexpected_Datatype},
		{rdf.Triple{rdf.iri("urn:s"), rdf.iri("urn:p"), rdf.Term{kind = cast(rdf.Term_Kind)99}}, .Invalid_Term_Kind},
	}
	for item in cases {
		builder := strings.builder_make()
		strings.write_string(&builder, "prefix")
		err := write_triple(&builder, item.triple)
		testing.expect_value(t, err, item.code)
		testing.expect_value(t, strings.to_string(builder), "prefix")
		strings.builder_destroy(&builder)
	}
}

@(test)
test_write_error_messages_are_stable :: proc(t: ^testing.T) {
	messages := [Write_Error]string{
		.None                      = "no error",
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
	}
	for code in Write_Error {
		testing.expect_value(t, write_error_message(code), messages[code])
	}
}
