package turtle

import "core:strings"
import "core:testing"
import rdf ".."

@(private) Writer_Roundtrip_State :: struct {
	count: int,
	ok:    bool,
}

@(private) check_writer_roundtrip :: proc(triple: rdf.Triple, data: rawptr) -> bool {
	state := cast(^Writer_Roundtrip_State)data
	state.count += 1
	state.ok = triple.subject.value == "https://example.com/alice" &&
		triple.predicate.value == "https://example.com/vocab/name" &&
		triple.object.value == "Ada\nLovelace" &&
		triple.object.datatype == "https://example.com/vocab/PersonName"
	return true
}

@(test)
test_writer_prefixes_choose_longest_namespace_and_roundtrip :: proc(t: ^testing.T) {
	prefixes := []Prefix{
		{label = "ex", namespace = "https://example.com/"},
		{label = "v", namespace = "https://example.com/vocab/"},
	}
	options := Writer_Options{prefixes = prefixes}
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	testing.expect_value(t, write_prefixes(&builder, prefixes), Write_Error.None)
	triple := rdf.Triple{
		rdf.iri("https://example.com/alice"),
		rdf.iri("https://example.com/vocab/name"),
		rdf.typed_literal("Ada\nLovelace", "https://example.com/vocab/PersonName"),
	}
	testing.expect_value(t, write_triple(&builder, triple, options), Write_Error.None)
	expected := `@prefix ex: <https://example.com/> .
@prefix v: <https://example.com/vocab/> .
ex:alice v:name "Ada\nLovelace"^^v:PersonName .
`
	testing.expect_value(t, strings.to_string(builder), expected)
	state: Writer_Roundtrip_State
	parse_err := parse(strings.to_string(builder), check_writer_roundtrip, {}, &state)
	testing.expect_value(t, parse_err.code, Error_Code.None)
	testing.expect_value(t, state.count, 1)
	testing.expect(t, state.ok)
}

@(test)
test_writer_uses_default_prefix_and_falls_back_for_unsafe_local :: proc(t: ^testing.T) {
	prefixes := []Prefix{{namespace = "urn:example:"}}
	options := Writer_Options{prefixes = prefixes}
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	testing.expect_value(t, write_term(&builder, rdf.iri("urn:example:thing"), options), Write_Error.None)
	testing.expect_value(t, strings.to_string(builder), ":thing")
	strings.builder_reset(&builder)
	testing.expect_value(t, write_term(&builder, rdf.iri("urn:example:has/slash"), options), Write_Error.None)
	testing.expect_value(t, strings.to_string(builder), "<urn:example:has/slash>")
	strings.builder_reset(&builder)
	testing.expect_value(t, write_term(&builder, rdf.iri("urn:example:a:b"), options), Write_Error.None)
	testing.expect_value(t, strings.to_string(builder), ":a:b")
}

@(test)
test_writer_is_atomic_for_invalid_options_and_terms :: proc(t: ^testing.T) {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	strings.write_string(&builder, "prefix")
	invalid_label := Writer_Options{prefixes = []Prefix{{label = "bad.", namespace = "urn:example:"}}}
	testing.expect_value(t, write_term(&builder, rdf.iri("urn:example:x"), invalid_label), Write_Error.Invalid_Prefix_Label)
	testing.expect_value(t, strings.to_string(builder), "prefix")
	duplicate := []Prefix{{label = "ex", namespace = "urn:one:"}, {label = "ex", namespace = "urn:two:"}}
	testing.expect_value(t, write_prefixes(&builder, duplicate), Write_Error.Duplicate_Prefix)
	testing.expect_value(t, strings.to_string(builder), "prefix")
	invalid := rdf.Triple{rdf.literal("x"), rdf.iri("urn:p"), rdf.iri("urn:o")}
	testing.expect_value(t, write_triple(&builder, invalid), Write_Error.Invalid_Subject)
	testing.expect_value(t, strings.to_string(builder), "prefix")
	testing.expect_value(t, write_term(&builder, rdf.iri("urn:has space")), Write_Error.Invalid_IRI)
	testing.expect_value(t, strings.to_string(builder), "prefix")
}

@(test)
test_write_error_messages_are_stable :: proc(t: ^testing.T) {
	messages := [Write_Error]string{
		.None                      = "no error",
		.Invalid_Prefix_Label      = "invalid Turtle prefix label",
		.Invalid_Prefix_Namespace  = "prefix namespace must be an absolute IRI",
		.Duplicate_Prefix          = "duplicate Turtle prefix label",
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
