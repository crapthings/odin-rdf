// Deterministic RDF/XML serialization for complete default-graph RDF data.
package rdfxml

import "core:encoding/xml"
import "core:strings"
import "core:unicode/utf8"
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
	Missing_Output,
	Invalid_Writer_Options,
	Invalid_Namespace_Prefix,
	Invalid_Namespace_IRI,
	Duplicate_Namespace_Prefix,
	Reserved_Namespace_Prefix,
	Missing_Predicate_Namespace,
	Blank_Node_Limit,
	Writer_Not_Active,
	Writer_Already_Active,
	Writer_Closed,
	Out_Of_Memory,
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
	case .Missing_Output:            return "output builder is required"
	case .Invalid_Writer_Options:    return "writer options must not be negative"
	case .Invalid_Namespace_Prefix:  return "namespace prefix must be an XML NCName"
	case .Invalid_Namespace_IRI:     return "namespace IRI must be an absolute XML-safe IRI"
	case .Duplicate_Namespace_Prefix:return "duplicate namespace prefix"
	case .Reserved_Namespace_Prefix: return "namespace prefix is reserved by XML or RDF/XML"
	case .Missing_Predicate_Namespace:return "predicate namespace has no declared prefix"
	case .Blank_Node_Limit:          return "blank-node limit reached"
	case .Writer_Not_Active:         return "RDF/XML document writer is not active"
	case .Writer_Already_Active:     return "RDF/XML document writer is already active"
	case .Writer_Closed:             return "RDF/XML document writer is already closed"
	case .Out_Of_Memory:             return "memory allocation failed"
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

// Namespace declares one non-RDF namespace prefix for a document writer. The
// prefix is emitted on the root rdf:RDF element and must be an XML NCName.
Namespace :: struct {
	prefix: string,
	iri:    string,
}

// Document_Writer_Options bounds retained blank-node identity. A zero
// max_blank_nodes selects DEFAULT_MAX_BLANK_NODES; a negative value is invalid.
// The namespace slice and its strings must remain valid until
// destroy_document_writer returns.
Document_Writer_Options :: struct {
	namespaces:      []Namespace,
	max_blank_nodes: int,
}

DEFAULT_MAX_BLANK_NODES :: 100_000

@(private) Document_Blank_Node :: struct {
	value: string,
	scope: rdf.Blank_Node_Scope,
}

// Document_Writer owns copied blank-node labels but borrows the caller's
// namespace slice. Initialize it with init_document_writer, append records
// through write_document_triple, finish the document, then destroy it.
Document_Writer :: struct {
	builder:         ^strings.Builder,
	namespaces:      []Namespace,
	blank_nodes:     [dynamic]Document_Blank_Node,
	max_blank_nodes: int,
	active:          bool,
	closed:          bool,
}

// destroy_document_writer releases copied blank-node labels. It does not close
// an unfinished document; callers must explicitly choose whether to finish one.
destroy_document_writer :: proc(writer: ^Document_Writer) {
	for node in writer.blank_nodes do delete(node.value)
	delete(writer.blank_nodes)
	writer^ = {}
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

@(private) equal_ascii_fold :: proc(value, expected: string) -> bool {
	if len(value) != len(expected) do return false
	for byte, index in value {
		folded := byte
		if folded >= 'A' && folded <= 'Z' do folded += 'a' - 'A'
		if folded != rune(expected[index]) do return false
	}
	return true
}

@(private) reserved_namespace :: proc(namespace: Namespace) -> bool {
	if equal_ascii_fold(namespace.prefix, "rdf") || equal_ascii_fold(namespace.prefix, "xml") || equal_ascii_fold(namespace.prefix, "xmlns") do return true
	return namespace.iri == RDF_NAMESPACE || namespace.iri == XML_NAMESPACE
}

@(private) validate_document_writer_options :: proc(options: Document_Writer_Options) -> Write_Error {
	if options.max_blank_nodes < 0 do return .Invalid_Writer_Options
	for namespace, index in options.namespaces {
		if !valid_xml_name(namespace.prefix) do return .Invalid_Namespace_Prefix
		if !is_absolute_iri(namespace.iri) || !utf8.valid_string(namespace.iri) || !valid_xml_characters(namespace.iri) do return .Invalid_Namespace_IRI
		if reserved_namespace(namespace) do return .Reserved_Namespace_Prefix
		for earlier in options.namespaces[:index] {
			if namespace.prefix == earlier.prefix do return .Duplicate_Namespace_Prefix
		}
	}
	return .None
}

// init_document_writer appends an RDF/XML prolog and root element. Namespace
// declarations are explicit because a stateful writer cannot infer a document-
// wide prefix table without retaining every predicate. Each namespace prefix
// must therefore cover the exact namespace portion of later predicate IRIs.
init_document_writer :: proc(writer: ^Document_Writer, builder: ^strings.Builder, options: Document_Writer_Options = {}) -> Write_Error {
	if builder == nil do return .Missing_Output
	if writer.active do return .Writer_Already_Active
	if options_err := validate_document_writer_options(options); options_err != .None do return options_err
	max_blank_nodes := options.max_blank_nodes
	if max_blank_nodes == 0 do max_blank_nodes = DEFAULT_MAX_BLANK_NODES
	temporary := strings.builder_make()
	defer strings.builder_destroy(&temporary)
	strings.write_string(&temporary, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
	strings.write_string(&temporary, "<rdf:RDF xmlns:rdf=\"")
	strings.write_string(&temporary, RDF_NAMESPACE)
	strings.write_byte(&temporary, '"')
	for namespace in options.namespaces {
		strings.write_string(&temporary, " xmlns:")
		strings.write_string(&temporary, namespace.prefix)
		strings.write_string(&temporary, "=\"")
		write_xml_attribute(&temporary, namespace.iri)
		strings.write_byte(&temporary, '"')
	}
	strings.write_string(&temporary, ">\n")
	writer^ = Document_Writer{
		builder = builder,
		namespaces = options.namespaces,
		blank_nodes = make([dynamic]Document_Blank_Node),
		max_blank_nodes = max_blank_nodes,
		active = true,
	}
	strings.write_string(builder, strings.to_string(temporary))
	return .None
}

@(private) document_blank_node_index :: proc(writer: ^Document_Writer, term: rdf.Term) -> int {
	for node, index in writer.blank_nodes {
		if node.value == term.value && node.scope == term.scope do return index
	}
	return -1
}

@(private) destroy_document_blank_nodes_from :: proc(writer: ^Document_Writer, start: int) {
	for index in start..<len(writer.blank_nodes) do delete(writer.blank_nodes[index].value)
	resize(&writer.blank_nodes, start)
}

@(private) append_document_blank_node :: proc(writer: ^Document_Writer, term: rdf.Term) -> Write_Error {
	cloned, clone_error := strings.clone(term.value)
	if clone_error != nil do return .Out_Of_Memory
	if _, append_error := append(&writer.blank_nodes, Document_Blank_Node{value = cloned, scope = term.scope}); append_error != nil {
		delete(cloned)
		return .Out_Of_Memory
	}
	return .None
}

@(private) count_new_document_blank_nodes :: proc(writer: ^Document_Writer, triple: rdf.Triple) -> int {
	count := 0
	if triple.subject.kind == .Blank_Node && document_blank_node_index(writer, triple.subject) < 0 do count += 1
	if triple.object.kind == .Blank_Node && document_blank_node_index(writer, triple.object) < 0 {
		if triple.subject.kind != .Blank_Node || triple.subject.value != triple.object.value || triple.subject.scope != triple.object.scope do count += 1
	}
	return count
}

@(private) ensure_document_blank_nodes :: proc(writer: ^Document_Writer, triple: rdf.Triple) -> Write_Error {
	if len(writer.blank_nodes) + count_new_document_blank_nodes(writer, triple) > writer.max_blank_nodes do return .Blank_Node_Limit
	start := len(writer.blank_nodes)
	if triple.subject.kind == .Blank_Node && document_blank_node_index(writer, triple.subject) < 0 {
		if err := append_document_blank_node(writer, triple.subject); err != .None do return err
	}
	if triple.object.kind == .Blank_Node && document_blank_node_index(writer, triple.object) < 0 {
		if err := append_document_blank_node(writer, triple.object); err != .None {
			destroy_document_blank_nodes_from(writer, start)
			return err
		}
	}
	return .None
}

@(private) write_document_blank_node_id :: proc(builder: ^strings.Builder, writer: ^Document_Writer, term: rdf.Term) {
	strings.write_string(builder, "b")
	strings.write_i64(builder, i64(document_blank_node_index(writer, term)))
}

@(private) document_predicate_name :: proc(writer: ^Document_Writer, predicate: rdf.Term) -> (prefix, local: string, err: Write_Error) {
	namespace, predicate_local, ok := split_predicate(predicate.value)
	if !ok do return "", "", .Invalid_Property_Name
	if is_rdf_syntax_name(predicate.value) || is_reserved_rdf_name(predicate.value) || predicate.value == RDF_NAMESPACE + "Description" do return "", "", .Reserved_Predicate
	if namespace == RDF_NAMESPACE do return "rdf", predicate_local, .None
	for declared in writer.namespaces {
		if declared.iri == namespace do return declared.prefix, predicate_local, .None
	}
	return "", "", .Missing_Predicate_Namespace
}

@(private) validate_document_triple :: proc(writer: ^Document_Writer, triple: rdf.Triple) -> Write_Error {
	if err := validate_triple(triple); err != .None do return err
	if !valid_term_xml_characters(triple.subject) || !valid_term_xml_characters(triple.predicate) || !valid_term_xml_characters(triple.object) do return .Invalid_XML_Character
	if _, _, err := document_predicate_name(writer, triple.predicate); err != .None do return err
	if triple.object.kind == .Literal && triple.object.datatype == RDF_XML_LITERAL && !valid_xml_literal(triple.object.value) do return .Invalid_XML_Literal
	return .None
}

@(private) write_document_triple_unchecked :: proc(builder: ^strings.Builder, writer: ^Document_Writer, triple: rdf.Triple) {
	strings.write_string(builder, "  <rdf:Description")
	if triple.subject.kind == .IRI {
		strings.write_string(builder, " rdf:about=\"")
		write_xml_attribute(builder, triple.subject.value)
	} else {
		strings.write_string(builder, " rdf:nodeID=\"")
		write_document_blank_node_id(builder, writer, triple.subject)
	}
	strings.write_string(builder, "\">\n")
	prefix, local, _ := document_predicate_name(writer, triple.predicate)
	strings.write_string(builder, "    <")
	strings.write_string(builder, prefix)
	strings.write_byte(builder, ':')
	strings.write_string(builder, local)
	if triple.object.kind == .IRI {
		strings.write_string(builder, " rdf:resource=\"")
		write_xml_attribute(builder, triple.object.value)
		strings.write_string(builder, "\"/>\n")
	} else if triple.object.kind == .Blank_Node {
		strings.write_string(builder, " rdf:nodeID=\"")
		write_document_blank_node_id(builder, writer, triple.object)
		strings.write_string(builder, "\"/>\n")
	} else if triple.object.datatype == RDF_XML_LITERAL {
		strings.write_string(builder, " rdf:parseType=\"Literal\">")
		strings.write_string(builder, triple.object.value)
		strings.write_string(builder, "</")
		strings.write_string(builder, prefix)
		strings.write_byte(builder, ':')
		strings.write_string(builder, local)
		strings.write_string(builder, ">\n")
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
		strings.write_string(builder, "</")
		strings.write_string(builder, prefix)
		strings.write_byte(builder, ':')
		strings.write_string(builder, local)
		strings.write_string(builder, ">\n")
	}
	strings.write_string(builder, "  </rdf:Description>\n")
}

// write_document_triple atomically appends one complete RDF/XML statement to
// an active document writer. A failed record leaves the destination builder
// unchanged. Blank-node labels from callback-scoped terms are copied before
// use and are bounded by Document_Writer_Options.max_blank_nodes.
write_document_triple :: proc(writer: ^Document_Writer, triple: rdf.Triple) -> Write_Error {
	if !writer.active do return .Writer_Not_Active
	if writer.closed do return .Writer_Closed
	if err := validate_document_triple(writer, triple); err != .None do return err
	if err := ensure_document_blank_nodes(writer, triple); err != .None do return err
	temporary := strings.builder_make()
	defer strings.builder_destroy(&temporary)
	write_document_triple_unchecked(&temporary, writer, triple)
	strings.write_string(writer.builder, strings.to_string(temporary))
	return .None
}

// finish_document_writer closes an active RDF/XML document. Once closed, the
// writer rejects additional triples and must be destroyed before reuse.
finish_document_writer :: proc(writer: ^Document_Writer) -> Write_Error {
	if !writer.active do return .Writer_Not_Active
	if writer.closed do return .Writer_Closed
	strings.write_string(writer.builder, "</rdf:RDF>\n")
	writer.closed = true
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
