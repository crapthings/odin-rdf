package nquads

import "core:strings"
import "core:testing"
import rdf ".."

@(test)
test_write_quad_default_named_and_roundtrip :: proc(t: ^testing.T) {
	statement := rdf.Triple{rdf.iri("urn:s"), rdf.iri("urn:p"), rdf.language_literal("hello", "en")}
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	testing.expect_value(t, write_quad(&builder, rdf.default_graph_quad(statement)), Write_Error.None)
	testing.expect_value(t, write_quad(&builder, rdf.named_graph_quad(statement, rdf.blank_node("g"))), Write_Error.None)
	testing.expect_value(t, strings.to_string(builder), "<urn:s> <urn:p> \"hello\"@en .\n<urn:s> <urn:p> \"hello\"@en _:g .\n")
	count := 0
	counting := proc(_: rdf.Quad, data: rawptr) -> bool { (cast(^int)data)^ += 1; return true }
	err := parse(strings.to_string(builder), counting, &count)
	testing.expect_value(t, err.code, Error_Code.None)
	testing.expect_value(t, count, 2)
}

@(test)
test_write_quad_is_atomic_on_failure :: proc(t: ^testing.T) {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	strings.write_string(&builder, "prefix")
	statement := rdf.Triple{rdf.iri("urn:s"), rdf.iri("urn:p"), rdf.iri("urn:o")}
	err := write_quad(&builder, rdf.named_graph_quad(statement, rdf.literal("bad")))
	testing.expect_value(t, err, Write_Error.Invalid_Graph)
	testing.expect_value(t, strings.to_string(builder), "prefix")
}

@(test)
test_write_error_messages_are_stable :: proc(t: ^testing.T) {
	messages := [Write_Error]string{
		.None                      = "no error",
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
	}
	for code in Write_Error do testing.expect_value(t, write_error_message(code), messages[code])
}
