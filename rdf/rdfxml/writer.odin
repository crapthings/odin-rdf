// Deterministic RDF/XML serialization for complete default-graph RDF data.
package rdfxml

import "core:encoding/xml"
import "core:strings"
import rdf ".."
import ntriples "../ntriples"

// Write_Error identifies why a graph cannot be represented as RDF/XML.
Write_Error :: enum {
	None,
	Invalid_Term_Kind,
	Invalid_Subject,
	Invalid_Predicate,
	Invalid_IRI,
	Invalid_Blank_Node,
	Invalid_Language_Tag,
	Invalid_UTF8,
	Unexpected_Language,
	Unexpected_Datatype,
	Missing_Literal_Datatype,
	Invalid_Language_Datatype,
	Invalid_Property_Name,
	Reserved_Predicate,
	Invalid_XML_Literal,
	Invalid_XML_Character,
}

// write_error_message returns a stable, allocation-free description.
write_error_message :: proc(code: Write_Error) -> string {
	switch code {
	case .None:                      return "no error"
	case .Invalid_Term_Kind:         return "invalid RDF term kind"
	case .Invalid_Subject:           return "subject must be an IRI or blank node"
	case .Invalid_Predicate:         return "predicate must be an IRI"
	case .Invalid_IRI:               return "invalid absolute IRI"
	case .Invalid_Blank_Node:        return "invalid blank-node label"
	case .Invalid_Language_Tag:      return "invalid language tag"
	case .Invalid_UTF8:              return "invalid UTF-8"
	case .Unexpected_Language:       return "language tag is only valid on a literal"
	case .Unexpected_Datatype:       return "datatype is only valid on a literal"
	case .Missing_Literal_Datatype:  return "literal datatype is required"
	case .Invalid_Language_Datatype: return "language-tagged literal must use rdf:langString"
	case .Invalid_Property_Name:     return "predicate IRI cannot be represented as an RDF/XML QName"
	case .Reserved_Predicate:        return "predicate is reserved by RDF/XML syntax"
	case .Invalid_XML_Literal:       return "rdf:XMLLiteral value is not a valid XML fragment"
	case .Invalid_XML_Character:     return "RDF term contains a character not representable in XML 1.0"
	}
	return "unknown error"
}

@(private) Writer_Blank_Node :: struct {
	value: string,
	scope: rdf.Blank_Node_Scope,
}

@(private) Writer_State :: struct {
	blank_nodes: [dynamic]Writer_Blank_Node,
}

@(private) destroy_writer_state :: proc(state: ^Writer_State) {
	delete(state.blank_nodes)
}

@(private) map_ntriples_error :: proc(code: ntriples.Write_Error) -> Write_Error {
	switch code {
	case .None:                      return .None
	case .Invalid_Term_Kind:         return .Invalid_Term_Kind
	case .Invalid_Subject:           return .Invalid_Subject
	case .Invalid_Predicate:         return .Invalid_Predicate
	case .Invalid_IRI:               return .Invalid_IRI
	case .Invalid_Blank_Node:        return .Invalid_Blank_Node
	case .Invalid_Language_Tag:      return .Invalid_Language_Tag
	case .Invalid_UTF8:              return .Invalid_UTF8
	case .Unexpected_Language:       return .Unexpected_Language
	case .Unexpected_Datatype:       return .Unexpected_Datatype
	case .Missing_Literal_Datatype:  return .Missing_Literal_Datatype
	case .Invalid_Language_Datatype: return .Invalid_Language_Datatype
	}
	return .Invalid_Term_Kind
}

@(private) validate_triple :: proc(triple: rdf.Triple) -> Write_Error {
	validation := strings.builder_make()
	defer strings.builder_destroy(&validation)
	return map_ntriples_error(ntriples.write_triple(&validation, triple))
}

@(private) valid_xml_characters :: proc(value: string) -> bool {
	for r in value {
		code := u32(r)
		if code == '\t' || code == '\n' || code == '\r' do continue
		if (code >= 0x20 && code <= 0xd7ff) || (code >= 0xe000 && code <= 0xfffd) || (code >= 0x10000 && code <= 0x10ffff) do continue
		return false
	}
	return true
}

@(private) valid_term_xml_characters :: proc(term: rdf.Term) -> bool {
	if term.kind == .Blank_Node do return true
	return valid_xml_characters(term.value) && valid_xml_characters(term.language) && valid_xml_characters(term.datatype)
}

@(private) blank_node_index :: proc(state: ^Writer_State, term: rdf.Term) -> int {
	for entry, index in state.blank_nodes {
		if entry.value == term.value && entry.scope == term.scope do return index
	}
	append(&state.blank_nodes, Writer_Blank_Node{value = term.value, scope = term.scope})
	return len(state.blank_nodes) - 1
}

@(private) collect_blank_nodes :: proc(state: ^Writer_State, triples: []rdf.Triple) {
	for triple in triples {
		if triple.subject.kind == .Blank_Node do _ = blank_node_index(state, triple.subject)
		if triple.object.kind == .Blank_Node do _ = blank_node_index(state, triple.object)
	}
}

@(private) write_xml_text :: proc(builder: ^strings.Builder, value: string) {
	for index in 0..<len(value) {
		byte := value[index]
		switch byte {
		case '&': strings.write_string(builder, "&amp;")
		case '<': strings.write_string(builder, "&lt;")
		case '>': strings.write_string(builder, "&gt;")
		case:    strings.write_byte(builder, byte)
		}
	}
}

@(private) write_xml_attribute :: proc(builder: ^strings.Builder, value: string) {
	for index in 0..<len(value) {
		byte := value[index]
		switch byte {
		case '&':  strings.write_string(builder, "&amp;")
		case '<':  strings.write_string(builder, "&lt;")
		case '"':  strings.write_string(builder, "&quot;")
		case '\t': strings.write_string(builder, "&#x9;")
		case '\n': strings.write_string(builder, "&#xA;")
		case '\r': strings.write_string(builder, "&#xD;")
		case:      strings.write_byte(builder, byte)
		}
	}
}

@(private) write_blank_node_id :: proc(builder: ^strings.Builder, state: ^Writer_State, term: rdf.Term) {
	strings.write_string(builder, "b")
	strings.write_i64(builder, i64(blank_node_index(state, term)))
}

@(private) split_predicate :: proc(value: string) -> (namespace, local: string, ok: bool) {
	for index := len(value) - 1; index >= 0; index -= 1 {
		if value[index] != '#' && value[index] != '/' && value[index] != ':' do continue
		if index + 1 >= len(value) do continue
		candidate_namespace, candidate_local := value[:index + 1], value[index + 1:]
		if valid_xml_name(candidate_local) do return candidate_namespace, candidate_local, true
	}
	return "", "", false
}

@(private) valid_xml_literal :: proc(value: string) -> bool {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	strings.write_string(&builder, "<rdfxml-writer-fragment>")
	strings.write_string(&builder, value)
	strings.write_string(&builder, "</rdfxml-writer-fragment>")
	document, err := xml.parse(strings.to_string(builder), xml.Options{flags = {.Error_on_Unsupported, .Unbox_CDATA, .Decode_SGML_Entities, .Intern_Comments}}, "", nil)
	if document != nil do xml.destroy(document)
	return err == .None
}

@(private) write_subject :: proc(builder: ^strings.Builder, state: ^Writer_State, subject: rdf.Term) {
	strings.write_string(builder, "  <rdf:Description")
	if subject.kind == .IRI {
		strings.write_string(builder, " rdf:about=\"")
		write_xml_attribute(builder, subject.value)
	} else {
		strings.write_string(builder, " rdf:nodeID=\"")
		write_blank_node_id(builder, state, subject)
	}
	strings.write_string(builder, "\">\n")
}

@(private) write_property_open :: proc(builder: ^strings.Builder, predicate: rdf.Term) -> (local: string, err: Write_Error) {
	namespace, predicate_local, ok := split_predicate(predicate.value)
	if !ok do return "", .Invalid_Property_Name
	if is_rdf_syntax_name(predicate.value) || is_reserved_rdf_name(predicate.value) || predicate.value == RDF_NAMESPACE + "Description" do return "", .Reserved_Predicate
	if namespace == RDF_NAMESPACE {
		strings.write_string(builder, "    <rdf:")
		strings.write_string(builder, predicate_local)
		return predicate_local, .None
	}
	strings.write_string(builder, "    <ns:")
	strings.write_string(builder, predicate_local)
	strings.write_string(builder, " xmlns:ns=\"")
	write_xml_attribute(builder, namespace)
	strings.write_byte(builder, '"')
	return predicate_local, .None
}

@(private) write_property_close :: proc(builder: ^strings.Builder, predicate: rdf.Term, local: string) {
	namespace, _, _ := split_predicate(predicate.value)
	strings.write_string(builder, "</")
	if namespace == RDF_NAMESPACE {
		strings.write_string(builder, "rdf:")
	} else {
		strings.write_string(builder, "ns:")
	}
	strings.write_string(builder, local)
	strings.write_string(builder, ">\n")
}

@(private) write_triple_unchecked :: proc(builder: ^strings.Builder, state: ^Writer_State, triple: rdf.Triple) -> Write_Error {
	write_subject(builder, state, triple.subject)
	local, open_err := write_property_open(builder, triple.predicate)
	if open_err != .None do return open_err

	if triple.object.kind == .IRI {
		strings.write_string(builder, " rdf:resource=\"")
		write_xml_attribute(builder, triple.object.value)
		strings.write_string(builder, "\"/>\n")
	} else if triple.object.kind == .Blank_Node {
		strings.write_string(builder, " rdf:nodeID=\"")
		write_blank_node_id(builder, state, triple.object)
		strings.write_string(builder, "\"/>\n")
	} else if triple.object.datatype == RDF_XML_LITERAL {
		strings.write_string(builder, " rdf:parseType=\"Literal\">")
		strings.write_string(builder, triple.object.value)
		write_property_close(builder, triple.predicate, local)
	} else {
		if len(triple.object.language) > 0 {
			strings.write_string(builder, " xml:lang=\"")
			write_xml_attribute(builder, triple.object.language)
			strings.write_byte(builder, '"')
		} else if triple.object.datatype != rdf.XSD_STRING {
			strings.write_string(builder, " rdf:datatype=\"")
			write_xml_attribute(builder, triple.object.datatype)
			strings.write_byte(builder, '"')
		}
		strings.write_byte(builder, '>')
		write_xml_text(builder, triple.object.value)
		write_property_close(builder, triple.predicate, local)
	}
	strings.write_string(builder, "  </rdf:Description>\n")
	return .None
}

// write_triples atomically appends a deterministic RDF/XML document for a
// complete default graph. It retains source triple order and represents every
// blank node with a generated XML-safe nodeID, so distinct source scopes never
// collide. Named graphs require a dataset syntax such as TriG or N-Quads.
write_triples :: proc(builder: ^strings.Builder, triples: []rdf.Triple) -> Write_Error {
	for triple in triples {
		if err := validate_triple(triple); err != .None do return err
		if !valid_term_xml_characters(triple.subject) || !valid_term_xml_characters(triple.predicate) || !valid_term_xml_characters(triple.object) do return .Invalid_XML_Character
		if _, _, ok := split_predicate(triple.predicate.value); !ok do return .Invalid_Property_Name
		if is_rdf_syntax_name(triple.predicate.value) || is_reserved_rdf_name(triple.predicate.value) || triple.predicate.value == RDF_NAMESPACE + "Description" do return .Reserved_Predicate
		if triple.object.kind == .Literal && triple.object.datatype == RDF_XML_LITERAL && !valid_xml_literal(triple.object.value) do return .Invalid_XML_Literal
	}
	state := Writer_State{}
	defer destroy_writer_state(&state)
	collect_blank_nodes(&state, triples)
	temporary := strings.builder_make()
	defer strings.builder_destroy(&temporary)
	strings.write_string(&temporary, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
	strings.write_string(&temporary, "<rdf:RDF xmlns:rdf=\"")
	strings.write_string(&temporary, RDF_NAMESPACE)
	strings.write_string(&temporary, "\">\n")
	for triple in triples {
		if err := write_triple_unchecked(&temporary, &state, triple); err != .None do return err
	}
	strings.write_string(&temporary, "</rdf:RDF>\n")
	strings.write_string(builder, strings.to_string(temporary))
	return .None
}
