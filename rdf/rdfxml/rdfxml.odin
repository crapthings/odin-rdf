// Package rdfxml transforms a bounded RDF/XML document into RDF dataset
// statements. It accepts RDF/XML input only; serialization is deliberately
// left to the N-Triples, N-Quads, and Turtle packages.
package rdfxml

import xml "core:encoding/xml"
import "core:strings"
import "core:unicode/utf8"
import rdf ".."
import turtle "../turtle"

RDF_NAMESPACE   :: "http://www.w3.org/1999/02/22-rdf-syntax-ns#"
XML_NAMESPACE   :: "http://www.w3.org/XML/1998/namespace"
RDF_TYPE        :: RDF_NAMESPACE + "type"
RDF_FIRST       :: RDF_NAMESPACE + "first"
RDF_REST        :: RDF_NAMESPACE + "rest"
RDF_NIL         :: RDF_NAMESPACE + "nil"
RDF_STATEMENT   :: RDF_NAMESPACE + "Statement"
RDF_SUBJECT     :: RDF_NAMESPACE + "subject"
RDF_PREDICATE   :: RDF_NAMESPACE + "predicate"
RDF_OBJECT      :: RDF_NAMESPACE + "object"
RDF_XML_LITERAL :: RDF_NAMESPACE + "XMLLiteral"

// Error_Code identifies XML, RDF/XML, resource-limit, and sink outcomes.
Error_Code :: enum {
	None,
	Missing_Sink,
	Invalid_UTF8,
	Invalid_XML,
	Invalid_Option,
	Invalid_Chunk_Size,
	Reader_Error,
	No_Progress,
	Document_Too_Large,
	Element_Limit,
	Attribute_Limit,
	Nesting_Limit,
	Quad_Limit,
	Invalid_Root,
	Invalid_Namespace,
	Invalid_QName,
	Invalid_IRI,
	Missing_Base,
	Invalid_Node_Element,
	Invalid_Property_Element,
	Invalid_Attribute,
	Duplicate_ID,
	Unsupported_Feature,
	Stopped,
	Out_Of_Memory,
}

// Parse_Error reports a processing outcome. XML parser positions are not
// exposed by core:encoding/xml, so semantic errors use a zero location.
Parse_Error :: struct {
	code:   Error_Code,
	line:   int,
	column: int,
}

// parse_error_message returns a stable, allocation-free description.
parse_error_message :: proc(code: Error_Code) -> string {
	switch code {
	case .None:                     return "no error"
	case .Missing_Sink:             return "sink is required"
	case .Invalid_UTF8:             return "invalid UTF-8"
	case .Invalid_XML:              return "invalid XML"
	case .Invalid_Option:           return "parser limits must not be negative"
	case .Invalid_Chunk_Size:       return "chunk size must not be negative"
	case .Reader_Error:             return "reader error"
	case .No_Progress:              return "reader made no progress"
	case .Document_Too_Large:       return "RDF/XML document exceeds configured byte limit"
	case .Element_Limit:            return "XML element limit reached"
	case .Attribute_Limit:          return "XML attribute limit reached"
	case .Nesting_Limit:            return "XML nesting depth limit reached"
	case .Quad_Limit:               return "quad limit reached"
	case .Invalid_Root:             return "RDF/XML document must contain a root element"
	case .Invalid_Namespace:        return "undefined XML namespace prefix"
	case .Invalid_QName:            return "invalid RDF/XML QName"
	case .Invalid_IRI:              return "invalid RDF/XML IRI"
	case .Missing_Base:             return "relative IRI requires a base IRI"
	case .Invalid_Node_Element:     return "invalid RDF/XML node element"
	case .Invalid_Property_Element: return "invalid RDF/XML property element"
	case .Invalid_Attribute:        return "invalid RDF/XML attribute"
	case .Duplicate_ID:             return "duplicate rdf:ID"
	case .Unsupported_Feature:      return "unsupported RDF/XML feature"
	case .Stopped:                  return "stopped by sink"
	case .Out_Of_Memory:            return "memory allocation failed"
	}
	return "unknown error"
}

// Options bounds the retained XML document and RDF/XML expansion. Zero selects
// documented defaults, except max_quads where zero disables the output cap.
Options :: struct {
	base_iri:           string,
	max_document_bytes: int,
	max_elements:       int,
	max_attributes:     int,
	max_nesting_depth:  int,
	max_quads:          int,
}

DEFAULT_MAX_DOCUMENT_BYTES :: 16 * 1024 * 1024
DEFAULT_MAX_ELEMENTS       :: 100_000
DEFAULT_MAX_ATTRIBUTES     :: 100_000
DEFAULT_MAX_NESTING_DEPTH  :: 256

// Sink receives default-graph RDF statements. Term strings remain valid only
// for the duration of the callback. Returning false stops parsing.
Sink :: proc(quad: rdf.Quad, user_data: rawptr) -> bool

@(private) Namespace_Map :: map[string]string

@(private) State :: struct {
	sink:           Sink,
	user_data:      rawptr,
	scope:          rdf.Blank_Node_Scope,
	named_bnodes:   map[string]rdf.Term,
	used_ids:       map[string]bool,
	owned:          [dynamic]string,
	generated:      u64,
	emitted:        int,
	attributes:     int,
	max_attributes: int,
	max_nesting:    int,
	max_quads:      int,
}

@(private) destroy_state :: proc(state: ^State) {
	for value in state.owned do delete(value)
	delete(state.owned)
	if state.named_bnodes != nil do delete(state.named_bnodes)
	if state.used_ids != nil do delete(state.used_ids)
}

@(private) own :: proc(state: ^State, value: string) -> (string, Parse_Error) {
	cloned, alloc_error := strings.clone(value)
	if alloc_error != nil do return "", Parse_Error{code = .Out_Of_Memory}
	append(&state.owned, cloned)
	return cloned, {}
}

@(private) own_concat2 :: proc(state: ^State, left, right: string) -> (string, Parse_Error) {
	parts := [2]string{left, right}
	joined, alloc_error := strings.concatenate(parts[:])
	if alloc_error != nil do return "", Parse_Error{code = .Out_Of_Memory}
	append(&state.owned, joined)
	return joined, {}
}

@(private) split_qname :: proc(name: string) -> (prefix, local: string, has_prefix, ok: bool) {
	if len(name) == 0 do return "", "", false, false
	colon := strings.index_byte(name, ':')
	if colon < 0 do return "", name, false, true
	if colon == 0 || colon + 1 >= len(name) do return "", "", false, false
	if strings.index_byte(name[colon + 1:], ':') >= 0 do return "", "", false, false
	return name[:colon], name[colon + 1:], true, true
}

@(private) clone_namespaces :: proc(parent: Namespace_Map) -> (Namespace_Map, Parse_Error) {
	result := make(Namespace_Map)
	for prefix, iri in parent do result[prefix] = iri
	return result, {}
}

@(private) extend_namespaces :: proc(parent: Namespace_Map, element: xml.Element) -> (Namespace_Map, Parse_Error) {
	result, err := clone_namespaces(parent)
	if err.code != .None do return nil, err
	for attribute in element.attribs {
		if attribute.key == "xmlns" {
			result[""] = attribute.val
			continue
		}
		if strings.has_prefix(attribute.key, "xmlns:") {
			prefix := attribute.key[len("xmlns:"):]
			if len(prefix) == 0 {
				delete(result)
				return nil, Parse_Error{code = .Invalid_Namespace}
			}
			result[prefix] = attribute.val
		}
	}
	return result, {}
}

@(private) expand_element_name :: proc(state: ^State, namespaces: Namespace_Map, name: string) -> (string, Parse_Error) {
	prefix, local, has_prefix, ok := split_qname(name)
	if !ok do return "", Parse_Error{code = .Invalid_QName}
	if has_prefix {
		namespace, found := namespaces[prefix]
		if !found do return "", Parse_Error{code = .Invalid_Namespace}
		return own_concat2(state, namespace, local)
	}
	namespace, found := namespaces[""]
	if !found do return "", Parse_Error{code = .Invalid_Namespace}
	return own_concat2(state, namespace, local)
}

@(private) expand_attribute_name :: proc(state: ^State, namespaces: Namespace_Map, name: string) -> (string, Parse_Error) {
	if name == "xmlns" || strings.has_prefix(name, "xmlns:") do return "", {}
	prefix, local, has_prefix, ok := split_qname(name)
	if !ok do return "", Parse_Error{code = .Invalid_QName}
	if !has_prefix do return "", {}
	if prefix == "xml" do return own_concat2(state, XML_NAMESPACE, local)
	namespace, found := namespaces[prefix]
	if !found do return "", Parse_Error{code = .Invalid_Namespace}
	return own_concat2(state, namespace, local)
}

@(private) is_absolute_iri :: proc(value: string) -> bool {
	if len(value) == 0 || !((value[0] >= 'A' && value[0] <= 'Z') || (value[0] >= 'a' && value[0] <= 'z')) do return false
	for index in 1..<len(value) {
		c := value[index]
		if c == ':' do return true
		if !((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '+' || c == '-' || c == '.') do return false
	}
	return false
}

@(private) is_rdf_syntax_name :: proc(iri: string) -> bool {
	switch iri {
	case RDF_NAMESPACE + "RDF", RDF_NAMESPACE + "ID", RDF_NAMESPACE + "about", RDF_NAMESPACE + "parseType", RDF_NAMESPACE + "resource", RDF_NAMESPACE + "nodeID", RDF_NAMESPACE + "datatype": return true
	}
	return false
}

@(private) is_reserved_rdf_name :: proc(iri: string) -> bool {
	switch iri {
	case RDF_NAMESPACE + "li", RDF_NAMESPACE + "bagID", RDF_NAMESPACE + "aboutEach", RDF_NAMESPACE + "aboutEachPrefix": return true
	}
	return false
}

@(private) valid_xml_name :: proc(value: string) -> bool {
	if len(value) == 0 do return false
	first := value[0]
	if !((first >= 'A' && first <= 'Z') || (first >= 'a' && first <= 'z') || first == '_') do return false
	for index in 1..<len(value) {
		c := value[index]
		if !((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_' || c == '-' || c == '.' || c >= 0x80) do return false
	}
	return true
}

@(private) resolve_iri :: proc(state: ^State, base, reference: string) -> (string, Parse_Error) {
	if len(reference) == 0 && len(base) == 0 do return "", Parse_Error{code = .Missing_Base}
	if len(reference) > 0 && is_absolute_iri(reference) do return reference, {}
	if len(base) == 0 do return "", Parse_Error{code = .Missing_Base}
	resolved, ok := turtle.resolve_iri_reference(base, reference)
	if !ok do return "", Parse_Error{code = .Invalid_IRI}
	append(&state.owned, resolved)
	return resolved, {}
}

@(private) rdf_attribute_value :: proc(state: ^State, element: xml.Element, namespaces: Namespace_Map, target: string) -> (string, bool, Parse_Error) {
	for attribute in element.attribs {
		name, err := expand_attribute_name(state, namespaces, attribute.key)
		if err.code != .None do return "", false, err
		if name == target do return attribute.val, true, {}
	}
	return "", false, {}
}

@(private) xml_attribute_value :: proc(state: ^State, element: xml.Element, namespaces: Namespace_Map, local: string) -> (string, bool, Parse_Error) {
	target, target_err := own_concat2(state, XML_NAMESPACE, local)
	if target_err.code != .None do return "", false, target_err
	return rdf_attribute_value(state, element, namespaces, target)
}

@(private) fresh_blank_node :: proc(state: ^State) -> (rdf.Term, Parse_Error) {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	strings.write_string(&builder, "rdfxml-genid-")
	strings.write_u64(&builder, state.generated)
	state.generated += 1
	owned_label, err := own(state, strings.to_string(builder))
	if err.code != .None do return {}, err
	return rdf.blank_node(owned_label, state.scope), {}
}

@(private) named_blank_node :: proc(state: ^State, label: string) -> (rdf.Term, Parse_Error) {
	if len(label) == 0 do return {}, Parse_Error{code = .Invalid_Attribute}
	if term, found := state.named_bnodes[label]; found do return term, {}
	owned_label, err := own(state, label)
	if err.code != .None do return {}, err
	term := rdf.blank_node(owned_label, state.scope)
	state.named_bnodes[owned_label] = term
	return term, {}
}

@(private) emit :: proc(state: ^State, subject, predicate, object: rdf.Term) -> Parse_Error {
	if state.max_quads > 0 && state.emitted >= state.max_quads do return Parse_Error{code = .Quad_Limit}
	quad := rdf.default_graph_quad(rdf.Triple{subject = subject, predicate = predicate, object = object})
	if !state.sink(quad, state.user_data) do return Parse_Error{code = .Stopped}
	state.emitted += 1
	return {}
}

@(private) element_children :: proc(doc: ^xml.Document, element: xml.Element) -> (children: [dynamic]xml.Element_ID, text: string, mixed: bool) {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	for value in element.value {
		#partial switch actual in value {
		case string:
			strings.write_string(&builder, actual)
		case xml.Element_ID:
			append(&children, actual)
		}
	}
	if len(children) > 0 && len(strings.to_string(builder)) > 0 do mixed = true
	return children, strings.clone(strings.to_string(builder)) or_else "", mixed
}

@(private) is_whitespace :: proc(value: string) -> bool {
	for c in value {
		if c != ' ' && c != '\t' && c != '\r' && c != '\n' do return false
	}
	return true
}

@(private) node_subject :: proc(state: ^State, element: xml.Element, namespaces: Namespace_Map, base: string) -> (rdf.Term, Parse_Error) {
	about, has_about, err := rdf_attribute_value(state, element, namespaces, RDF_NAMESPACE + "about")
	if err.code != .None do return {}, err
	id, has_id, id_err := rdf_attribute_value(state, element, namespaces, RDF_NAMESPACE + "ID")
	if id_err.code != .None do return {}, id_err
	node_id, has_node_id, node_id_err := rdf_attribute_value(state, element, namespaces, RDF_NAMESPACE + "nodeID")
	if node_id_err.code != .None do return {}, node_id_err
	count := (has_about ? 1 : 0) + (has_id ? 1 : 0) + (has_node_id ? 1 : 0)
	if count > 1 do return {}, Parse_Error{code = .Invalid_Node_Element}
	if has_id && !valid_xml_name(id) do return {}, Parse_Error{code = .Invalid_Attribute}
	if has_node_id && !valid_xml_name(node_id) do return {}, Parse_Error{code = .Invalid_Attribute}
	if has_about {
		iri, resolve_err := resolve_iri(state, base, about)
		if resolve_err.code != .None do return {}, resolve_err
		return rdf.iri(iri), {}
	}
	if has_id {
		reference, reference_err := own_concat2(state, "#", id)
		if reference_err.code != .None do return {}, reference_err
		iri, resolve_err := resolve_iri(state, base, reference)
		if resolve_err.code != .None do return {}, resolve_err
		if state.used_ids[iri] do return {}, Parse_Error{code = .Duplicate_ID}
		state.used_ids[iri] = true
		return rdf.iri(iri), {}
	}
	if has_node_id do return named_blank_node(state, node_id)
	return fresh_blank_node(state)
}

@(private) validate_node_attributes :: proc(state: ^State, element: xml.Element, namespaces: Namespace_Map) -> Parse_Error {
	for attribute in element.attribs {
		name, name_err := expand_attribute_name(state, namespaces, attribute.key)
		if name_err.code != .None do return name_err
		if is_reserved_rdf_name(name) do return Parse_Error{code = .Invalid_Attribute}
		if name == RDF_NAMESPACE + "resource" || name == RDF_NAMESPACE + "parseType" || name == RDF_NAMESPACE + "datatype" do return Parse_Error{code = .Invalid_Attribute}
	}
	return {}
}

@(private) reify :: proc(state: ^State, base, id: string, subject, predicate, object: rdf.Term) -> Parse_Error {
	reference, reference_err := own_concat2(state, "#", id)
	if reference_err.code != .None do return reference_err
	iri, resolve_err := resolve_iri(state, base, reference)
	if resolve_err.code != .None do return resolve_err
	if state.used_ids[iri] do return Parse_Error{code = .Duplicate_ID}
	state.used_ids[iri] = true
	reification := rdf.iri(iri)
	if err := emit(state, reification, rdf.iri(RDF_TYPE), rdf.iri(RDF_STATEMENT)); err.code != .None do return err
	if err := emit(state, reification, rdf.iri(RDF_SUBJECT), subject); err.code != .None do return err
	if err := emit(state, reification, rdf.iri(RDF_PREDICATE), predicate); err.code != .None do return err
	return emit(state, reification, rdf.iri(RDF_OBJECT), object)
}

@(private) process_properties :: proc(state: ^State, doc: ^xml.Document, element: xml.Element, namespaces: Namespace_Map, base, language: string, subject: rdf.Term, depth: int) -> Parse_Error {
	li_index := 1
	for value in element.value {
		#partial switch actual in value {
		case string:
			if !is_whitespace(actual) do return Parse_Error{code = .Invalid_Node_Element}
		case xml.Element_ID:
			child := doc.elements[actual]
			if child.kind != .Element do continue
			if err := process_property(state, doc, actual, namespaces, base, language, subject, depth + 1, &li_index); err.code != .None do return err
		}
	}
	return {}
}

@(private) process_property_attributes :: proc(state: ^State, element: xml.Element, namespaces: Namespace_Map, base, language: string, subject: rdf.Term) -> Parse_Error {
	for attribute in element.attribs {
		name, name_err := expand_attribute_name(state, namespaces, attribute.key)
		if name_err.code != .None do return name_err
		if is_reserved_rdf_name(name) do return Parse_Error{code = .Invalid_Attribute}
		if len(name) == 0 || strings.has_prefix(name, XML_NAMESPACE) || is_rdf_syntax_name(name) do continue
		if name == RDF_TYPE {
			iri, iri_err := resolve_iri(state, base, attribute.val)
			if iri_err.code != .None do return iri_err
			if err := emit(state, subject, rdf.iri(RDF_TYPE), rdf.iri(iri)); err.code != .None do return err
			continue
		}
		if err := emit(state, subject, rdf.iri(name), language != "" ? rdf.language_literal(attribute.val, language) : rdf.literal(attribute.val)); err.code != .None do return err
	}
	return {}
}

@(private) has_property_attributes :: proc(state: ^State, element: xml.Element, namespaces: Namespace_Map) -> (bool, Parse_Error) {
	for attribute in element.attribs {
		name, name_err := expand_attribute_name(state, namespaces, attribute.key)
		if name_err.code != .None do return false, name_err
		if is_reserved_rdf_name(name) do return false, Parse_Error{code = .Invalid_Attribute}
		if len(name) == 0 || strings.has_prefix(name, XML_NAMESPACE) || is_rdf_syntax_name(name) do continue
		return true, {}
	}
	return false, {}
}

@(private) process_property :: proc(state: ^State, doc: ^xml.Document, element_id: xml.Element_ID, parent_namespaces: Namespace_Map, parent_base, parent_language: string, subject: rdf.Term, depth: int, li_index: ^int) -> Parse_Error {
	if depth > state.max_nesting do return Parse_Error{code = .Nesting_Limit}
	element := doc.elements[element_id]
	namespaces, ns_err := extend_namespaces(parent_namespaces, element)
	if ns_err.code != .None do return ns_err
	defer delete(namespaces)
	state.attributes += len(element.attribs)
	if state.attributes > state.max_attributes do return Parse_Error{code = .Attribute_Limit}
	base := parent_base
	if xml_base, found, base_err := xml_attribute_value(state, element, namespaces, "base"); base_err.code != .None { return base_err } else if found {
		base, base_err = resolve_iri(state, parent_base, xml_base)
		if base_err.code != .None do return base_err
	}
	language := parent_language
	if xml_lang, found, lang_err := xml_attribute_value(state, element, namespaces, "lang"); lang_err.code != .None { return lang_err } else if found { language = xml_lang }
	predicate_iri, predicate_err := expand_element_name(state, namespaces, element.ident)
	if predicate_err.code != .None do return predicate_err
	is_li := predicate_iri == RDF_NAMESPACE + "li"
	if is_li {
		builder := strings.builder_make()
		strings.write_string(&builder, RDF_NAMESPACE + "_")
		strings.write_int(&builder, li_index^)
		predicate_iri, predicate_err = own(state, strings.to_string(builder))
		strings.builder_destroy(&builder)
		if predicate_err.code != .None do return predicate_err
		li_index^ += 1
	}
	if is_rdf_syntax_name(predicate_iri) || is_reserved_rdf_name(predicate_iri) || predicate_iri == RDF_NAMESPACE + "Description" do return Parse_Error{code = .Invalid_Property_Element}
	predicate := rdf.iri(predicate_iri)
	resource, has_resource, attr_err := rdf_attribute_value(state, element, namespaces, RDF_NAMESPACE + "resource")
	if attr_err.code != .None do return attr_err
	node_id, has_node_id, node_id_err := rdf_attribute_value(state, element, namespaces, RDF_NAMESPACE + "nodeID")
	if node_id_err.code != .None do return node_id_err
	datatype, has_datatype, datatype_err := rdf_attribute_value(state, element, namespaces, RDF_NAMESPACE + "datatype")
	if datatype_err.code != .None do return datatype_err
	parse_type, has_parse_type, parse_type_err := rdf_attribute_value(state, element, namespaces, RDF_NAMESPACE + "parseType")
	if parse_type_err.code != .None do return parse_type_err
	reification_id, has_reification, reification_err := rdf_attribute_value(state, element, namespaces, RDF_NAMESPACE + "ID")
	if reification_err.code != .None do return reification_err
	if has_reification && !valid_xml_name(reification_id) do return Parse_Error{code = .Invalid_Attribute}
	children, text, mixed := element_children(doc, element)
	defer delete(children)
	defer delete(text)
	has_property_attributes, property_attribute_err := has_property_attributes(state, element, namespaces)
	if property_attribute_err.code != .None do return property_attribute_err
	if mixed && !is_whitespace(text) do return Parse_Error{code = .Invalid_Property_Element}
	if (has_resource ? 1 : 0) + (has_node_id ? 1 : 0) + (has_datatype ? 1 : 0) + (has_parse_type ? 1 : 0) > 1 do return Parse_Error{code = .Invalid_Property_Element}
	if has_parse_type && has_property_attributes do return Parse_Error{code = .Invalid_Property_Element}
	if has_node_id && !valid_xml_name(node_id) do return Parse_Error{code = .Invalid_Attribute}
	object: rdf.Term
	if has_resource {
		if len(children) > 0 || !is_whitespace(text) do return Parse_Error{code = .Invalid_Property_Element}
		iri, resolve_err := resolve_iri(state, base, resource)
		if resolve_err.code != .None do return resolve_err
		object = rdf.iri(iri)
	} else if has_node_id {
		if len(children) > 0 || !is_whitespace(text) do return Parse_Error{code = .Invalid_Property_Element}
		term, node_err := named_blank_node(state, node_id)
		if node_err.code != .None do return node_err
		object = term
	} else if has_parse_type {
		switch parse_type {
		case "Resource":
			if !is_whitespace(text) do return Parse_Error{code = .Invalid_Property_Element}
			term, node_err := fresh_blank_node(state)
			if node_err.code != .None do return node_err
			object = term
			if err := emit(state, subject, predicate, object); err.code != .None do return err
			if has_reification {
				if err := reify(state, base, reification_id, subject, predicate, object); err.code != .None do return err
			}
			if has_property_attributes {
				if err := process_property_attributes(state, element, namespaces, base, language, object); err.code != .None do return err
			}
			return process_properties(state, doc, element, namespaces, base, language, object, depth)
		case "Collection":
			if !is_whitespace(text) do return Parse_Error{code = .Invalid_Property_Element}
			if len(children) == 0 { object = rdf.iri(RDF_NIL) } else {
				head, node_err := fresh_blank_node(state)
				if node_err.code != .None do return node_err
				object = head
				current := head
				for index in 0..<len(children) {
					item, item_err := process_node(state, doc, children[index], namespaces, base, language, depth + 1)
					if item_err.code != .None do return item_err
					if err := emit(state, current, rdf.iri(RDF_FIRST), item); err.code != .None do return err
					if index + 1 == len(children) { if err := emit(state, current, rdf.iri(RDF_REST), rdf.iri(RDF_NIL)); err.code != .None do return err
					} else {
						next, next_err := fresh_blank_node(state)
						if next_err.code != .None do return next_err
						if err := emit(state, current, rdf.iri(RDF_REST), next); err.code != .None do return err
						current = next
					}
				}
			}
		case "Literal":
			if len(children) > 0 do return Parse_Error{code = .Unsupported_Feature}
			object = rdf.typed_literal(text, RDF_XML_LITERAL)
		case: return Parse_Error{code = .Invalid_Property_Element}
		}
	} else if len(children) > 0 {
		if !is_whitespace(text) || len(children) != 1 do return Parse_Error{code = .Invalid_Property_Element}
		term, node_err := process_node(state, doc, children[0], namespaces, base, language, depth + 1)
		if node_err.code != .None do return node_err
		object = term
	} else if has_property_attributes {
		if !is_whitespace(text) do return Parse_Error{code = .Invalid_Property_Element}
		term, node_err := fresh_blank_node(state)
		if node_err.code != .None do return node_err
		object = term
	} else {
		if has_datatype {
			datatype_iri, resolve_err := resolve_iri(state, base, datatype)
			if resolve_err.code != .None do return resolve_err
			object = rdf.typed_literal(text, datatype_iri)
		} else if language != "" { object = rdf.language_literal(text, language) }
		else { object = rdf.literal(text) }
	}
	if err := emit(state, subject, predicate, object); err.code != .None do return err
	if has_reification {
		if err := reify(state, base, reification_id, subject, predicate, object); err.code != .None do return err
	}
	if has_property_attributes do return process_property_attributes(state, element, namespaces, base, language, object)
	return {}
}

@(private) process_node :: proc(state: ^State, doc: ^xml.Document, element_id: xml.Element_ID, parent_namespaces: Namespace_Map, parent_base, parent_language: string, depth: int) -> (rdf.Term, Parse_Error) {
	if depth > state.max_nesting do return {}, Parse_Error{code = .Nesting_Limit}
	element := doc.elements[element_id]
	namespaces, ns_err := extend_namespaces(parent_namespaces, element)
	if ns_err.code != .None do return {}, ns_err
	defer delete(namespaces)
	state.attributes += len(element.attribs)
	if state.attributes > state.max_attributes do return {}, Parse_Error{code = .Attribute_Limit}
	base := parent_base
	if xml_base, found, base_err := xml_attribute_value(state, element, namespaces, "base"); base_err.code != .None { return {}, base_err } else if found {
		base, base_err = resolve_iri(state, parent_base, xml_base)
		if base_err.code != .None do return {}, base_err
	}
	language := parent_language
	if xml_lang, found, lang_err := xml_attribute_value(state, element, namespaces, "lang"); lang_err.code != .None { return {}, lang_err } else if found { language = xml_lang }
	name, name_err := expand_element_name(state, namespaces, element.ident)
	if name_err.code != .None do return {}, name_err
	if is_rdf_syntax_name(name) || is_reserved_rdf_name(name) do return {}, Parse_Error{code = .Invalid_Node_Element}
	if attribute_err := validate_node_attributes(state, element, namespaces); attribute_err.code != .None do return {}, attribute_err
	subject, subject_err := node_subject(state, element, namespaces, base)
	if subject_err.code != .None do return {}, subject_err
	if name != RDF_NAMESPACE + "Description" {
		if err := emit(state, subject, rdf.iri(RDF_TYPE), rdf.iri(name)); err.code != .None do return {}, err
	}
	if attr_err := process_property_attributes(state, element, namespaces, base, language, subject); attr_err.code != .None do return {}, attr_err
	if properties_err := process_properties(state, doc, element, namespaces, base, language, subject, depth); properties_err.code != .None do return {}, properties_err
	return subject, {}
}

// parse transforms one complete RDF/XML document into default-graph RDF
// statements. It retains a bounded XML DOM only for the duration of parsing.
parse :: proc(input: string, sink: Sink, options: Options = {}, user_data: rawptr = nil) -> Parse_Error {
	if sink == nil do return Parse_Error{code = .Missing_Sink, line = 1, column = 1}
	if !utf8.valid_string(input) do return Parse_Error{code = .Invalid_UTF8, line = 1, column = 1}
	max_document_bytes := options.max_document_bytes
	if max_document_bytes == 0 do max_document_bytes = DEFAULT_MAX_DOCUMENT_BYTES
	max_elements := options.max_elements
	if max_elements == 0 do max_elements = DEFAULT_MAX_ELEMENTS
	max_attributes := options.max_attributes
	if max_attributes == 0 do max_attributes = DEFAULT_MAX_ATTRIBUTES
	max_nesting := options.max_nesting_depth
	if max_nesting == 0 do max_nesting = DEFAULT_MAX_NESTING_DEPTH
	if max_document_bytes < 0 || max_elements < 0 || max_attributes < 0 || max_nesting < 0 || options.max_quads < 0 do return Parse_Error{code = .Invalid_Option, line = 1, column = 1}
	if len(input) > max_document_bytes do return Parse_Error{code = .Document_Too_Large, line = 1, column = 1}
	document, xml_error := xml.parse(input, xml.Options{flags = {.Error_on_Unsupported, .Unbox_CDATA, .Decode_SGML_Entities}}, "", nil)
	if document == nil || xml_error != .None {
		if document != nil do xml.destroy(document)
		return Parse_Error{code = .Invalid_XML}
	}
	defer xml.destroy(document)
	if int(document.element_count) == 0 do return Parse_Error{code = .Invalid_Root}
	if int(document.element_count) > max_elements do return Parse_Error{code = .Element_Limit}
	state := State{
		sink = sink,
		user_data = user_data,
		scope = rdf.new_blank_node_scope(),
		named_bnodes = make(map[string]rdf.Term),
		used_ids = make(map[string]bool),
		max_attributes = max_attributes,
		max_nesting = max_nesting,
		max_quads = options.max_quads,
	}
	defer destroy_state(&state)
	root := document.elements[0]
	namespaces: Namespace_Map = make(Namespace_Map)
	defer delete(namespaces)
	root_namespaces, ns_err := extend_namespaces(namespaces, root)
	if ns_err.code != .None do return ns_err
	defer delete(root_namespaces)
	root_name, root_err := expand_element_name(&state, root_namespaces, root.ident)
	if root_err.code != .None do return root_err
	is_rdf_root := root_name == RDF_NAMESPACE + "RDF"
	base := options.base_iri
	if len(base) > 0 && !is_absolute_iri(base) do return Parse_Error{code = .Invalid_IRI}
	language := ""
	if is_rdf_root {
		if xml_base, found, base_err := xml_attribute_value(&state, root, root_namespaces, "base"); base_err.code != .None { return base_err } else if found {
			base, base_err = resolve_iri(&state, base, xml_base)
			if base_err.code != .None do return base_err
		}
		if xml_lang, found, lang_err := xml_attribute_value(&state, root, root_namespaces, "lang"); lang_err.code != .None { return lang_err } else if found { language = xml_lang }
		state.attributes += len(root.attribs)
		if state.attributes > state.max_attributes do return Parse_Error{code = .Attribute_Limit}
		for value in root.value {
			#partial switch actual in value {
			case string:
				if !is_whitespace(actual) do return Parse_Error{code = .Invalid_Root}
			case xml.Element_ID:
				child := document.elements[actual]
				if child.kind != .Element do continue
				if _, node_err := process_node(&state, document, actual, root_namespaces, base, language, 1); node_err.code != .None do return node_err
			}
		}
	} else {
		if _, node_err := process_node(&state, document, 0, namespaces, base, language, 1); node_err.code != .None do return node_err
	}
	return {}
}
