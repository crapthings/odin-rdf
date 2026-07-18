// Raw XML Literal capture and serialization. The general-purpose XML DOM used
// by the RDF/XML parser intentionally discards inter-element whitespace; this
// file retains it for rdf:parseType="Literal", where it is RDF data.
package rdfxml

import "core:sort"
import "core:strings"
import entity "core:encoding/entity"
import xml "core:encoding/xml"

@(private) Raw_Attribute :: struct {
	name:  string,
	value: string,
}

@(private) Raw_Start_Tag :: struct {
	name:         string,
	attributes:   [dynamic]Raw_Attribute,
	self_closing: bool,
}

@(private) Raw_Scan_Element :: struct {
	namespaces:    Namespace_Map,
	literal:       bool,
	content_start: int,
}

@(private) raw_is_space :: proc(byte: u8) -> bool {
	return byte == ' ' || byte == '\t' || byte == '\r' || byte == '\n'
}

@(private) raw_skip_space :: proc(source: string, position: ^int) {
	for position^ < len(source) && raw_is_space(source[position^]) do position^ += 1
}

@(private) raw_read_name :: proc(source: string, position: ^int) -> (string, bool) {
	start := position^
	for position^ < len(source) {
		byte := source[position^]
		if raw_is_space(byte) || byte == '=' || byte == '/' || byte == '>' do break
		position^ += 1
	}
	return source[start:position^], position^ > start
}

@(private) raw_parse_start_tag :: proc(source: string, position: int) -> (Raw_Start_Tag, int, bool) {
	cursor := position
	if cursor >= len(source) || source[cursor] != '<' do return {}, cursor, false
	cursor += 1
	name, name_ok := raw_read_name(source, &cursor)
	if !name_ok do return {}, cursor, false
	tag := Raw_Start_Tag{name = name, attributes = make([dynamic]Raw_Attribute)}
	for cursor < len(source) {
		raw_skip_space(source, &cursor)
		if cursor >= len(source) do break
		if source[cursor] == '>' {
			return tag, cursor + 1, true
		}
		if source[cursor] == '/' && cursor + 1 < len(source) && source[cursor + 1] == '>' {
			tag.self_closing = true
			return tag, cursor + 2, true
		}
		attribute_name, attribute_ok := raw_read_name(source, &cursor)
		if !attribute_ok {
			delete(tag.attributes)
			return {}, cursor, false
		}
		raw_skip_space(source, &cursor)
		if cursor >= len(source) || source[cursor] != '=' {
			delete(tag.attributes)
			return {}, cursor, false
		}
		cursor += 1
		raw_skip_space(source, &cursor)
		if cursor >= len(source) || (source[cursor] != '"' && source[cursor] != '\'') {
			delete(tag.attributes)
			return {}, cursor, false
		}
		quote := source[cursor]
		cursor += 1
		value_start := cursor
		for cursor < len(source) && source[cursor] != quote do cursor += 1
		if cursor >= len(source) {
			delete(tag.attributes)
			return {}, cursor, false
		}
		append(&tag.attributes, Raw_Attribute{name = attribute_name, value = source[value_start:cursor]})
		cursor += 1
	}
	delete(tag.attributes)
	return {}, cursor, false
}

@(private) raw_skip_comment :: proc(source: string, position: int) -> (int, bool) {
	if !strings.has_prefix(source[position:], "<!--") do return position, false
	end := strings.index(source[position + 4:], "-->")
	if end < 0 do return position, false
	return position + 4 + end + 3, true
}

@(private) raw_skip_cdata :: proc(source: string, position: int) -> (int, bool) {
	if !strings.has_prefix(source[position:], "<![CDATA[") do return position, false
	end := strings.index(source[position + 9:], "]]>")
	if end < 0 do return position, false
	return position + 9 + end + 3, true
}

@(private) raw_skip_instruction :: proc(source: string, position: int) -> (int, bool) {
	if !strings.has_prefix(source[position:], "<?") do return position, false
	end := strings.index(source[position + 2:], "?>")
	if end < 0 do return position, false
	return position + 2 + end + 2, true
}

@(private) raw_skip_declaration :: proc(source: string, position: int) -> (int, bool) {
	if !strings.has_prefix(source[position:], "<!") do return position, false
	cursor := position + 2
	bracket_depth := 0
	quote: u8
	for cursor < len(source) {
		byte := source[cursor]
		if quote != 0 {
			if byte == quote do quote = 0
			cursor += 1
			continue
		}
		switch byte {
		case '\'', '"': quote = byte
		case '[':       bracket_depth += 1
		case ']':       if bracket_depth > 0 do bracket_depth -= 1
		case '>':       if bracket_depth == 0 do return cursor + 1, true
		}
		cursor += 1
	}
	return position, false
}

@(private) raw_parse_end_tag :: proc(source: string, position: int) -> (name: string, next: int, ok: bool) {
	cursor := position
	if cursor + 2 > len(source) || !strings.has_prefix(source[cursor:], "</") do return "", cursor, false
	cursor += 2
	parsed_name, name_ok := raw_read_name(source, &cursor)
	if !name_ok do return "", cursor, false
	raw_skip_space(source, &cursor)
	if cursor >= len(source) || source[cursor] != '>' do return "", cursor, false
	return parsed_name, cursor + 1, true
}

@(private) raw_extend_namespaces :: proc(parent: Namespace_Map, attributes: []Raw_Attribute) -> Namespace_Map {
	result := clone_literal_namespaces(parent)
	for attribute in attributes {
		if attribute.name == "xmlns" {
			result[""] = attribute.value
		} else if strings.has_prefix(attribute.name, "xmlns:") {
			result[attribute.name[len("xmlns:"):]] = attribute.value
		}
	}
	return result
}

@(private) raw_parse_type :: proc(tag: Raw_Start_Tag, namespaces: Namespace_Map) -> (value: string, found: bool) {
	for attribute in tag.attributes {
		prefix, local, has_prefix, ok := split_qname(attribute.name)
		if !ok || !has_prefix || local != "parseType" do continue
		if namespace, exists := namespaces[prefix]; exists && namespace == RDF_NAMESPACE do return attribute.value, true
	}
	return "", false
}

// collect_literal_sources records each RDF/XML parseType Literal source span in
// document order. The DOM traversal visits the same property elements in order,
// allowing the canonicalizer to retain whitespace the DOM deliberately omits.
@(private) collect_literal_sources :: proc(source: string) -> ([dynamic]string, Parse_Error) {
	result := make([dynamic]string)
	stack := make([dynamic]Raw_Scan_Element)
	defer {
		for element in stack do delete(element.namespaces)
		delete(stack)
	}
	namespaces := make(Namespace_Map)
	defer delete(namespaces)
	position := 0
	literal_depth := 0
	for position < len(source) {
		next_tag := strings.index_byte(source[position:], '<')
		if next_tag < 0 do break
		position += next_tag
		if next, ok := raw_skip_comment(source, position); ok {
			position = next
			continue
		}
		if next, ok := raw_skip_cdata(source, position); ok {
			position = next
			continue
		}
		if next, ok := raw_skip_instruction(source, position); ok {
			position = next
			continue
		}
		if strings.has_prefix(source[position:], "<!") {
			next, ok := raw_skip_declaration(source, position)
			if !ok {
				delete(result)
				return nil, Parse_Error{code = .Invalid_XML}
			}
			position = next
			continue
		}
		if strings.has_prefix(source[position:], "</") {
			_, next, ok := raw_parse_end_tag(source, position)
			if !ok || len(stack) == 0 {
				delete(result)
				return nil, Parse_Error{code = .Invalid_XML}
			}
			element := stack[len(stack) - 1]
			if element.literal {
				append(&result, source[element.content_start:position])
				literal_depth -= 1
			}
			delete(element.namespaces)
			pop(&stack)
			position = next
			continue
		}
		tag, next, ok := raw_parse_start_tag(source, position)
		if !ok {
			delete(result)
			return nil, Parse_Error{code = .Invalid_XML}
		}
		parent_namespaces := namespaces
		if len(stack) > 0 do parent_namespaces = stack[len(stack) - 1].namespaces
		element_namespaces := raw_extend_namespaces(parent_namespaces, tag.attributes[:])
		parse_type, has_parse_type := raw_parse_type(tag, element_namespaces)
		literal := literal_depth == 0 && has_parse_type && parse_type != "Resource" && parse_type != "Collection"
		if tag.self_closing {
			if literal do append(&result, "")
			delete(element_namespaces)
			delete(tag.attributes)
			position = next
			continue
		}
		append(&stack, Raw_Scan_Element{namespaces = element_namespaces, literal = literal, content_start = next})
		if literal do literal_depth += 1
		delete(tag.attributes)
		position = next
	}
	if len(stack) != 0 {
		delete(result)
		return nil, Parse_Error{code = .Invalid_XML}
	}
	return result, {}
}

@(private) decode_literal_xml :: proc(value: string) -> (string, Parse_Error) {
	decoded, err := entity.decode_xml(value)
	if err != .None do return "", Parse_Error{code = .Invalid_XML}
	return decoded, {}
}

@(private) canonical_xml_literal :: proc(state: ^State, doc: ^xml.Document, property_id: xml.Element_ID, property_namespaces: Namespace_Map) -> (string, Parse_Error) {
	if state.literal_index >= len(state.literal_sources) do return "", Parse_Error{code = .Invalid_XML}
	source := state.literal_sources[state.literal_index]
	state.literal_index += 1
	initial_namespaces := literal_in_scope_namespaces(doc, property_id)
	defer delete(initial_namespaces)
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	position := 0
	if err := canonicalize_raw_content(&builder, source, &position, "", property_namespaces, nil, initial_namespaces[:], true); err.code != .None do return "", err
	if position != len(source) do return "", Parse_Error{code = .Invalid_XML}
	return own(state, strings.to_string(builder))
}

@(private) canonicalize_raw_content :: proc(builder: ^strings.Builder, source: string, position: ^int, closing_name: string, inherited: Namespace_Map, rendered: map[string]string, initial_namespaces: []Canonical_Namespace, root: bool) -> Parse_Error {
	first_element := true
	for position^ < len(source) {
		if source[position^] != '<' {
			end := strings.index_byte(source[position^:], '<')
			if end < 0 do end = len(source) - position^
			decoded, decode_err := decode_literal_xml(source[position^:position^ + end])
			if decode_err.code != .None do return decode_err
			write_canonical_text(builder, decoded)
			delete(decoded)
			position^ += end
			continue
		}
		if strings.has_prefix(source[position^:], "<!--") {
			end := strings.index(source[position^ + 4:], "-->")
			if end < 0 do return Parse_Error{code = .Invalid_XML}
			strings.write_string(builder, source[position^:position^ + 4 + end + 3])
			position^ += 4 + end + 3
			continue
		}
		if strings.has_prefix(source[position^:], "<![CDATA[") {
			end := strings.index(source[position^ + 9:], "]]>")
			if end < 0 do return Parse_Error{code = .Invalid_XML}
			write_canonical_text(builder, source[position^ + 9:position^ + 9 + end])
			position^ += 9 + end + 3
			continue
		}
		if strings.has_prefix(source[position^:], "<?") {
			end := strings.index(source[position^ + 2:], "?>")
			if end < 0 do return Parse_Error{code = .Invalid_XML}
			strings.write_string(builder, source[position^:position^ + 2 + end + 2])
			position^ += 2 + end + 2
			continue
		}
		if strings.has_prefix(source[position^:], "</") {
			name, next, ok := raw_parse_end_tag(source, position^)
			if !ok || len(closing_name) == 0 || name != closing_name do return Parse_Error{code = .Invalid_XML}
			position^ = next
			return {}
		}
		tag, next, ok := raw_parse_start_tag(source, position^)
		if !ok do return Parse_Error{code = .Invalid_XML}
		if err := canonicalize_raw_element(builder, source, &next, tag, inherited, rendered, initial_namespaces, root && first_element); err.code != .None {
			delete(tag.attributes)
			return err
		}
		delete(tag.attributes)
		position^ = next
		first_element = false
	}
	if len(closing_name) > 0 do return Parse_Error{code = .Invalid_XML}
	return {}
}

@(private) canonicalize_raw_element :: proc(builder: ^strings.Builder, source: string, next: ^int, tag: Raw_Start_Tag, inherited: Namespace_Map, rendered: map[string]string, initial_namespaces: []Canonical_Namespace, root: bool) -> Parse_Error {
	namespaces := raw_extend_namespaces(inherited, tag.attributes[:])
	defer delete(namespaces)
	rendered_here := clone_rendered_namespaces(rendered)
	defer delete(rendered_here)
	_, _, _, name_ok := namespace_for_qname(namespaces, tag.name, false)
	if !name_ok do return Parse_Error{code = .Invalid_Namespace}
	visible := make(map[string]bool)
	defer delete(visible)
	prefix, _, has_prefix, split_ok := split_qname(tag.name)
	if !split_ok do return Parse_Error{code = .Invalid_QName}
	if has_prefix {
		if prefix != "xml" do visible[prefix] = true
	} else if _, found := namespaces[""]; found {
		visible[""] = true
	}
	attributes := make([dynamic]Canonical_Attribute)
	defer delete(attributes)
	for attribute in tag.attributes {
		if attribute.name == "xmlns" || strings.has_prefix(attribute.name, "xmlns:") do continue
		attribute_prefix, local, iri, ok := namespace_for_qname(namespaces, attribute.name, true)
		if !ok do return Parse_Error{code = .Invalid_Namespace}
		if attribute_prefix != "" && attribute_prefix != "xml" do visible[attribute_prefix] = true
		decoded, decode_err := decode_literal_xml(attribute.value)
		if decode_err.code != .None do return decode_err
		append(&attributes, Canonical_Attribute{name = attribute.name, value = decoded, namespace = iri, local = local})
	}
	defer for attribute in attributes do delete(attribute.value)
	sort.sort(canonical_attribute_sort_interface(&attributes))
	namespaces_to_render := make([dynamic]Canonical_Namespace)
	defer delete(namespaces_to_render)
	if root && len(visible) == 0 {
		for entry in initial_namespaces {
			if entry.prefix == "xml" do continue
			if previous, found := rendered_here[entry.prefix]; !found || previous != entry.iri do add_canonical_namespace(&namespaces_to_render, entry.prefix, entry.iri)
		}
	} else {
		for visible_prefix in visible {
			iri, found := namespaces[visible_prefix]
			if !found do return Parse_Error{code = .Invalid_Namespace}
			if previous, was_rendered := rendered_here[visible_prefix]; !was_rendered || previous != iri do add_canonical_namespace(&namespaces_to_render, visible_prefix, iri)
		}
		sort.sort(canonical_namespace_sort_interface(&namespaces_to_render))
	}
	strings.write_byte(builder, '<')
	strings.write_string(builder, tag.name)
	for declaration in namespaces_to_render {
		strings.write_byte(builder, ' ')
		if len(declaration.prefix) == 0 {
			strings.write_string(builder, "xmlns")
		} else {
			strings.write_string(builder, "xmlns:")
			strings.write_string(builder, declaration.prefix)
		}
		strings.write_string(builder, "=\"")
		write_canonical_attribute_value(builder, declaration.iri)
		strings.write_byte(builder, '"')
		rendered_here[declaration.prefix] = declaration.iri
	}
	for attribute in attributes {
		strings.write_byte(builder, ' ')
		strings.write_string(builder, attribute.name)
		strings.write_string(builder, "=\"")
		write_canonical_attribute_value(builder, attribute.value)
		strings.write_byte(builder, '"')
	}
	strings.write_byte(builder, '>')
	if !tag.self_closing {
		if err := canonicalize_raw_content(builder, source, next, tag.name, namespaces, rendered_here, nil, false); err.code != .None do return err
	}
	strings.write_string(builder, "</")
	strings.write_string(builder, tag.name)
	strings.write_byte(builder, '>')
	return {}
}
