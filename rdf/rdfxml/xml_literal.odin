// XMLLiteral fragment serialization for rdf:parseType="Literal".
package rdfxml

import "core:sort"
import "core:strings"
import xml "core:encoding/xml"

@(private) Canonical_Namespace :: struct {
	prefix: string,
	iri:    string,
}

@(private) Canonical_Attribute :: struct {
	name:      string,
	value:     string,
	namespace: string,
	local:     string,
}

@(private) literal_in_scope_namespaces :: proc(doc: ^xml.Document, property_id: xml.Element_ID) -> [dynamic]Canonical_Namespace {
	chain := make([dynamic]xml.Element_ID)
	defer delete(chain)
	current := property_id
	for {
		append(&chain, current)
		if current == 0 do break
		current = doc.elements[current].parent
	}
	result := make([dynamic]Canonical_Namespace)
	for index := len(chain) - 1; index >= 0; index -= 1 {
		for attribute in doc.elements[chain[index]].attribs {
			prefix: string
			if attribute.key == "xmlns" {
				prefix = ""
			} else if strings.has_prefix(attribute.key, "xmlns:") {
				prefix = attribute.key[len("xmlns:"):]
			} else {
				continue
			}
			found := false
			for &entry in result {
				if entry.prefix == prefix {
					entry.iri = attribute.val
					found = true
					break
				}
			}
			if !found do append(&result, Canonical_Namespace{prefix = prefix, iri = attribute.val})
		}
	}
	return result
}

@(private) clone_literal_namespaces :: proc(source: Namespace_Map) -> Namespace_Map {
	result := make(Namespace_Map)
	for prefix, iri in source do result[prefix] = iri
	return result
}

@(private) clone_rendered_namespaces :: proc(source: map[string]string) -> map[string]string {
	result := make(map[string]string)
	if source != nil do for prefix, iri in source do result[prefix] = iri
	return result
}

@(private) add_canonical_namespace :: proc(namespaces: ^[dynamic]Canonical_Namespace, prefix, iri: string) {
	for &entry in namespaces^ {
		if entry.prefix == prefix {
			entry.iri = iri
			return
		}
	}
	append(namespaces, Canonical_Namespace{prefix = prefix, iri = iri})
}

@(private) canonical_namespace_sort_interface :: proc(namespaces: ^[dynamic]Canonical_Namespace) -> sort.Interface {
	return sort.Interface{
		collection = rawptr(namespaces),
		len = proc(it: sort.Interface) -> int {
			namespaces := cast(^[dynamic]Canonical_Namespace)it.collection
			return len(namespaces^)
		},
		less = proc(it: sort.Interface, i, j: int) -> bool {
			namespaces := cast(^[dynamic]Canonical_Namespace)it.collection
			return strings.compare(namespaces[i].prefix, namespaces[j].prefix) < 0
		},
		swap = proc(it: sort.Interface, i, j: int) {
			namespaces := cast(^[dynamic]Canonical_Namespace)it.collection
			namespaces[i], namespaces[j] = namespaces[j], namespaces[i]
		},
	}
}

@(private) canonical_attribute_sort_interface :: proc(attributes: ^[dynamic]Canonical_Attribute) -> sort.Interface {
	return sort.Interface{
		collection = rawptr(attributes),
		len = proc(it: sort.Interface) -> int {
			attributes := cast(^[dynamic]Canonical_Attribute)it.collection
			return len(attributes^)
		},
		less = proc(it: sort.Interface, i, j: int) -> bool {
			attributes := cast(^[dynamic]Canonical_Attribute)it.collection
			if result := strings.compare(attributes[i].namespace, attributes[j].namespace); result != 0 do return result < 0
			return strings.compare(attributes[i].local, attributes[j].local) < 0
		},
		swap = proc(it: sort.Interface, i, j: int) {
			attributes := cast(^[dynamic]Canonical_Attribute)it.collection
			attributes[i], attributes[j] = attributes[j], attributes[i]
		},
	}
}

@(private) namespace_for_qname :: proc(namespaces: Namespace_Map, name: string, attribute: bool) -> (prefix, local, iri: string, ok: bool) {
	name_prefix, name_local, has_prefix, valid := split_qname(name)
	if !valid do return "", "", "", false
	prefix, local = name_prefix, name_local
	if !has_prefix {
		if attribute do return "", name_local, "", true
		iri = namespaces[""]
		return "", name_local, iri, true
	}
	if name_prefix == "xml" do return name_prefix, name_local, XML_NAMESPACE, true
	iri, ok = namespaces[name_prefix]
	return name_prefix, name_local, iri, ok
}

@(private) write_canonical_text :: proc(builder: ^strings.Builder, value: string) {
	for index in 0..<len(value) {
		byte := value[index]
		switch byte {
		case '&':  strings.write_string(builder, "&amp;")
		case '<':  strings.write_string(builder, "&lt;")
		case '>':  strings.write_string(builder, "&gt;")
		case '\r': strings.write_string(builder, "&#xD;")
		case:      strings.write_byte(builder, byte)
		}
	}
}

@(private) write_canonical_attribute_value :: proc(builder: ^strings.Builder, value: string) {
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
