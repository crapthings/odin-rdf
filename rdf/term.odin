// Package rdf defines the syntax-independent RDF data model.
package rdf

import "core:sync"

// Term_Kind identifies the three RDF 1.1 term categories represented by Term.
Term_Kind :: enum {
	IRI,
	Blank_Node,
	Literal,
}

// Blank_Node_Scope identifies the RDF source in which a blank-node label is
// meaningful. Zero is reserved for caller-managed terms constructed without
// an explicit source scope.
Blank_Node_Scope :: distinct u64

@(private) blank_node_scope_counter: u64

// new_blank_node_scope returns a process-unique, non-zero scope suitable for
// labels originating from one RDF document or caller-managed source.
new_blank_node_scope :: proc() -> Blank_Node_Scope {
	previous := sync.atomic_add_explicit(&blank_node_scope_counter, u64(1), .Relaxed)
	return Blank_Node_Scope(previous + 1)
}

XSD_STRING      :: "http://www.w3.org/2001/XMLSchema#string"
RDF_LANG_STRING :: "http://www.w3.org/1999/02/22-rdf-syntax-ns#langString"

// Term is the low-level, syntax-independent representation of an RDF term.
// Constructors establish RDF datatype invariants but do not validate lexical syntax.
// The caller or parser input owns the memory behind value, language, and datatype.
Term :: struct {
	kind:     Term_Kind,
	value:    string,
	language: string,
	datatype: string,
	scope:    Blank_Node_Scope,
}

// Triple is one RDF statement in subject-predicate-object order.
Triple :: struct {
	subject:   Term,
	predicate: Term,
	object:    Term,
}

// Quad is one RDF dataset statement. When has_graph is false the statement is
// in the default graph and graph is ignored; otherwise graph is an IRI or blank node.
Quad :: struct {
	subject:   Term,
	predicate: Term,
	object:    Term,
	graph:     Term,
	has_graph: bool,
}

// default_graph_quad constructs a dataset statement in the default graph.
default_graph_quad :: proc(triple: Triple) -> Quad {
	return Quad{subject = triple.subject, predicate = triple.predicate, object = triple.object}
}

// named_graph_quad constructs a dataset statement with an explicit graph name.
// Use validate_quad_structure to reject a literal or malformed graph term.
named_graph_quad :: proc(triple: Triple, graph: Term) -> Quad {
	return Quad{subject = triple.subject, predicate = triple.predicate, object = triple.object, graph = graph, has_graph = true}
}

// triple returns the subject-predicate-object portion of a quad.
triple :: proc(quad: Quad) -> Triple {
	return Triple{quad.subject, quad.predicate, quad.object}
}

// iri constructs an IRI term without validating the IRI string.
iri :: proc(value: string) -> Term {
	return Term{kind = .IRI, value = value}
}

// blank_node constructs a blank node. Parsers supply a non-zero document scope;
// callers may pass one when labels from multiple RDF sources can coexist.
blank_node :: proc(value: string, scope: Blank_Node_Scope = {}) -> Term {
	return Term{kind = .Blank_Node, value = value, scope = scope}
}

// literal constructs a simple literal with the xsd:string datatype.
literal :: proc(value: string) -> Term {
	return Term{kind = .Literal, value = value, datatype = XSD_STRING}
}

// language_literal constructs an rdf:langString literal.
language_literal :: proc(value, language: string) -> Term {
	return Term{kind = .Literal, value = value, language = language, datatype = RDF_LANG_STRING}
}

// typed_literal constructs a literal with an explicit datatype IRI.
typed_literal :: proc(value, datatype: string) -> Term {
	return Term{kind = .Literal, value = value, datatype = datatype}
}

// Term_Structure_Error reports a syntax-independent Term invariant violation.
Term_Structure_Error :: enum {
	None,
	Invalid_Term_Kind,
	Unexpected_Language,
	Unexpected_Datatype,
	Missing_Datatype,
	Invalid_Language_Datatype,
}

// Triple_Structure_Error reports an RDF triple-position or term invariant violation.
Triple_Structure_Error :: enum {
	None,
	Invalid_Subject,
	Invalid_Predicate,
	Invalid_Subject_Term,
	Invalid_Predicate_Term,
	Invalid_Object_Term,
}

// Quad_Structure_Error reports a triple or graph-name invariant violation.
Quad_Structure_Error :: enum {
	None,
	Invalid_Triple,
	Invalid_Graph,
	Invalid_Graph_Term,
}

// term_structure_error_message returns a stable, allocation-free description.
term_structure_error_message :: proc(code: Term_Structure_Error) -> string {
	switch code {
	case .None:                      return "no error"
	case .Invalid_Term_Kind:         return "invalid RDF term kind"
	case .Unexpected_Language:       return "language tag is only valid on a literal"
	case .Unexpected_Datatype:       return "datatype is only valid on a literal"
	case .Missing_Datatype:          return "literal datatype is required"
	case .Invalid_Language_Datatype: return "language-tagged literal must use rdf:langString"
	}
	return "unknown error"
}

// triple_structure_error_message returns a stable, allocation-free description.
triple_structure_error_message :: proc(code: Triple_Structure_Error) -> string {
	switch code {
	case .None:                   return "no error"
	case .Invalid_Subject:        return "subject must be an IRI or blank node"
	case .Invalid_Predicate:      return "predicate must be an IRI"
	case .Invalid_Subject_Term:   return "subject has invalid term structure"
	case .Invalid_Predicate_Term: return "predicate has invalid term structure"
	case .Invalid_Object_Term:    return "object has invalid term structure"
	}
	return "unknown error"
}

// quad_structure_error_message returns a stable, allocation-free description.
quad_structure_error_message :: proc(code: Quad_Structure_Error) -> string {
	switch code {
	case .None:               return "no error"
	case .Invalid_Triple:     return "quad contains an invalid RDF triple"
	case .Invalid_Graph:      return "graph name must be an IRI or blank node"
	case .Invalid_Graph_Term: return "graph name has invalid term structure"
	}
	return "unknown error"
}

// validate_term_structure checks RDF data-model invariants only. It does not
// validate IRI, language-tag, or literal lexical forms.
validate_term_structure :: proc(term: Term) -> Term_Structure_Error {
	switch term.kind {
	case .IRI, .Blank_Node:
		if len(term.language) > 0 do return .Unexpected_Language
		if len(term.datatype) > 0 do return .Unexpected_Datatype
	case .Literal:
		if len(term.datatype) == 0 do return .Missing_Datatype
		if len(term.language) > 0 && term.datatype != RDF_LANG_STRING do return .Invalid_Language_Datatype
		if len(term.language) == 0 && term.datatype == RDF_LANG_STRING do return .Invalid_Language_Datatype
	case:
		return .Invalid_Term_Kind
	}
	return .None
}

// validate_triple_structure checks the RDF 1.1 triple-position rules and the
// structural invariants of all three terms.
validate_triple_structure :: proc(triple: Triple) -> Triple_Structure_Error {
	if triple.subject.kind == .Literal do return .Invalid_Subject
	if triple.predicate.kind != .IRI do return .Invalid_Predicate
	if validate_term_structure(triple.subject) != .None do return .Invalid_Subject_Term
	if validate_term_structure(triple.predicate) != .None do return .Invalid_Predicate_Term
	if validate_term_structure(triple.object) != .None do return .Invalid_Object_Term
	return .None
}

// validate_generalized_triple_structure accepts the generalized RDF extension
// in which a predicate may be an IRI or blank node. Callers must opt in to this
// separately; validate_triple_structure remains strict RDF 1.1 by default.
validate_generalized_triple_structure :: proc(triple: Triple) -> Triple_Structure_Error {
	if triple.subject.kind == .Literal do return .Invalid_Subject
	if triple.predicate.kind != .IRI && triple.predicate.kind != .Blank_Node do return .Invalid_Predicate
	if validate_term_structure(triple.subject) != .None do return .Invalid_Subject_Term
	if validate_term_structure(triple.predicate) != .None do return .Invalid_Predicate_Term
	if validate_term_structure(triple.object) != .None do return .Invalid_Object_Term
	return .None
}

// validate_quad_structure checks RDF triple rules and, for named graphs, the
// graph-name kind and term structure. The default graph is not represented by a term.
validate_quad_structure :: proc(quad: Quad) -> Quad_Structure_Error {
	if validate_triple_structure(triple(quad)) != .None do return .Invalid_Triple
	if !quad.has_graph do return .None
	if quad.graph.kind != .IRI && quad.graph.kind != .Blank_Node do return .Invalid_Graph
	if validate_term_structure(quad.graph) != .None do return .Invalid_Graph_Term
	return .None
}

// validate_generalized_quad_structure extends generalized triple validation
// with the same named-graph rules as RDF 1.1 datasets.
validate_generalized_quad_structure :: proc(quad: Quad) -> Quad_Structure_Error {
	if validate_generalized_triple_structure(triple(quad)) != .None do return .Invalid_Triple
	if !quad.has_graph do return .None
	if quad.graph.kind != .IRI && quad.graph.kind != .Blank_Node do return .Invalid_Graph
	if validate_term_structure(quad.graph) != .None do return .Invalid_Graph_Term
	return .None
}
