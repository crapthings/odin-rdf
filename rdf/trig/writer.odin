// Streaming-safe TriG serialization for RDF dataset statements.
package trig

import "core:strings"
import rdf ".."
import turtle "../turtle"

// Writer_Options selects the explicit compact-IRI policy shared with the
// Turtle writer. The writer never infers prefixes or retains prior quads.
Writer_Options :: struct {
	prefixes: []turtle.Prefix,
}

// Write_Error identifies invalid RDF data or prefix configuration supplied to
// the TriG writer.
Write_Error :: enum {
	None,
	Invalid_Prefix_Label,
	Invalid_Prefix_Namespace,
	Duplicate_Prefix,
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
	Ambiguous_Blank_Node_Label,
}

// write_error_message returns a stable, allocation-free description.
write_error_message :: proc(code: Write_Error) -> string {
	switch code {
	case .None:                      return "no error"
	case .Invalid_Prefix_Label:      return "invalid TriG prefix label"
	case .Invalid_Prefix_Namespace:  return "prefix namespace must be an absolute IRI"
	case .Duplicate_Prefix:          return "duplicate TriG prefix label"
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
	case .Ambiguous_Blank_Node_Label: return "blank-node label refers to multiple source scopes"
	}
	return "unknown error"
}

@(private) turtle_options :: proc(options: Writer_Options) -> turtle.Writer_Options {
	return turtle.Writer_Options{prefixes = options.prefixes}
}

@(private) map_turtle_error :: proc(code: turtle.Write_Error) -> Write_Error {
	switch code {
	case .None:                      return .None
	case .Invalid_Prefix_Label:      return .Invalid_Prefix_Label
	case .Invalid_Prefix_Namespace:  return .Invalid_Prefix_Namespace
	case .Duplicate_Prefix:          return .Duplicate_Prefix
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
	case .Ambiguous_Blank_Node_Label: return .Ambiguous_Blank_Node_Label
	}
	return .Invalid_Term_Kind
}

// write_prefixes atomically appends canonical TriG @prefix directives. The
// directive grammar is shared with Turtle, so this delegates its proven
// validation and escaping policy.
write_prefixes :: proc(builder: ^strings.Builder, prefixes: []turtle.Prefix) -> Write_Error {
	return map_turtle_error(turtle.write_prefixes(builder, prefixes))
}

// write_quad atomically appends one stable TriG quad. Default-graph quads are
// written as Turtle-compatible triples; named graphs use one self-contained
// graph block per quad. This preserves order, supports unbounded streams, and
// deliberately avoids graph grouping or retained writer state.
write_quad :: proc(builder: ^strings.Builder, quad: rdf.Quad, options: Writer_Options = {}) -> Write_Error {
	// Validate options before RDF data, matching the public Turtle writer API.
	validation := strings.builder_make()
	defer strings.builder_destroy(&validation)
	if err := turtle.write_prefixes(&validation, options.prefixes); err != .None do return map_turtle_error(err)

	structure_error := rdf.validate_quad_structure(quad)
	if structure_error == .Invalid_Triple do return .Invalid_Triple
	if structure_error == .Invalid_Graph || structure_error == .Invalid_Graph_Term do return .Invalid_Graph

	temporary := strings.builder_make()
	defer strings.builder_destroy(&temporary)
	turtle_options := turtle_options(options)
	if !quad.has_graph {
		if err := turtle.write_triple(&temporary, rdf.triple(quad), turtle_options); err != .None do return map_turtle_error(err)
	} else {
		if err := turtle.write_term(&temporary, quad.graph, turtle_options); err != .None do return map_turtle_error(err)
		strings.write_string(&temporary, " { ")
		if err := turtle.write_term(&temporary, quad.subject, turtle_options); err != .None do return map_turtle_error(err)
		strings.write_byte(&temporary, ' ')
		if err := turtle.write_term(&temporary, quad.predicate, turtle_options); err != .None do return map_turtle_error(err)
		strings.write_byte(&temporary, ' ')
		if err := turtle.write_term(&temporary, quad.object, turtle_options); err != .None do return map_turtle_error(err)
		strings.write_string(&temporary, " . }\n")
	}
	strings.write_string(builder, strings.to_string(temporary))
	return .None
}
