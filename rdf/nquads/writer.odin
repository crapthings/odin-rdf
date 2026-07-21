package nquads

import "core:strings"
import rdf ".."
import ntriples "../ntriples"

// Writer_Options selects explicit extensions to the strict RDF 1.1 N-Quads
// writer. The default rejects blank-node predicates.
Writer_Options :: struct {
	allow_generalized_rdf: bool,
}

// Write_Error identifies why a quad cannot be serialized as N-Quads.
Write_Error :: enum {
	None,
	Invalid_Triple,
	Invalid_Graph,
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
}

// write_error_message returns a stable, allocation-free description.
write_error_message :: proc(code: Write_Error) -> string {
	switch code {
	case .None:                      return "no error"
	case .Invalid_Triple:            return "quad contains an invalid RDF triple"
	case .Invalid_Graph:             return "graph name must be an IRI or blank node"
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
	}
	return "unknown error"
}

@(private) map_term_error :: proc(code: ntriples.Write_Error) -> Write_Error {
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

// write_quad_with_options atomically appends one canonical-layout N-Quads
// record. Generalized RDF serialization requires explicit opt-in.
write_quad_with_options :: proc(builder: ^strings.Builder, quad: rdf.Quad, options: Writer_Options = {}) -> Write_Error {
	structure_error := options.allow_generalized_rdf ? rdf.validate_generalized_quad_structure(quad) : rdf.validate_quad_structure(quad)
	if structure_error == .Invalid_Triple do return .Invalid_Triple
	if structure_error == .Invalid_Graph || structure_error == .Invalid_Graph_Term do return .Invalid_Graph

	temporary := strings.builder_make()
	defer strings.builder_destroy(&temporary)
	terms := [3]rdf.Term{quad.subject, quad.predicate, quad.object}
	for term, i in terms {
		if i > 0 do strings.write_byte(&temporary, ' ')
		if err := ntriples.write_term(&temporary, term); err != .None do return map_term_error(err)
	}
	if quad.has_graph {
		strings.write_byte(&temporary, ' ')
		if err := ntriples.write_term(&temporary, quad.graph); err != .None do return map_term_error(err)
	}
	strings.write_string(&temporary, " .\n")
	strings.write_string(builder, strings.to_string(temporary))
	return .None
}

// write_quad is the strict RDF 1.1 convenience form.
write_quad :: proc(builder: ^strings.Builder, quad: rdf.Quad) -> Write_Error {
	return write_quad_with_options(builder, quad)
}
