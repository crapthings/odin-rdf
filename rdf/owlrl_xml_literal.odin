package rdf

import "core:strings"
import xml "core:encoding/xml"

// OWL_RL_XML_Literal_Status describes rdf:XMLLiteral lexical validation.
OWL_RL_XML_Literal_Status :: enum {
	Not_XML_Literal_Datatype,
	Not_In_Value_Space,
	Valid,
}

// owl_rl_xml_literal_status checks whether an rdf:XMLLiteral is a well-formed
// XML content fragment. The wrapper supplies the one document element needed
// by the XML parser; the fragment itself remains the literal value. Equality
// is intentionally not exposed here: RDF XMLLiteral equality requires shared
// canonical XML, never raw source-string comparison.
owl_rl_xml_literal_status :: proc(literal: Term) -> OWL_RL_XML_Literal_Status {
	if literal.kind != .Literal || literal.datatype != "http://www.w3.org/1999/02/22-rdf-syntax-ns#XMLLiteral" do return .Not_XML_Literal_Datatype
	if valid_xml_literal_fragment(literal.value) do return .Valid
	return .Not_In_Value_Space
}

@(private) valid_xml_literal_fragment :: proc(value: string) -> bool {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	strings.write_string(&builder, "<owlrl-xml-literal>")
	strings.write_string(&builder, value)
	strings.write_string(&builder, "</owlrl-xml-literal>")
	document, err := xml.parse(strings.to_string(builder), xml.Options{flags = {.Error_on_Unsupported, .Unbox_CDATA, .Decode_SGML_Entities, .Intern_Comments}}, "", nil)
	if document != nil do xml.destroy(document)
	return err == .None
}
