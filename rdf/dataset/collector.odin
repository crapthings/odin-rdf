// Package dataset provides bounded, owned collection for transient RDF quads.
package dataset

import "core:strings"
import rdf ".."

// Error_Code identifies collector setup, validation, capacity, and allocation
// outcomes. A zero-value code is success.
Error_Code :: enum {
	None,
	Invalid_Option,
	Invalid_Quad,
	Quad_Limit,
	Out_Of_Memory,
}

// error_message returns a stable, allocation-free description.
error_message :: proc(code: Error_Code) -> string {
	switch code {
	case .None:           return "no error"
	case .Invalid_Option: return "collector limits must not be negative"
	case .Invalid_Quad:   return "invalid RDF quad"
	case .Quad_Limit:     return "collector quad limit reached"
	case .Out_Of_Memory:  return "memory allocation failed"
	}
	return "unknown error"
}

// Options controls the collector's retained dataset size. A zero max_quads
// disables the admission limit.
Options :: struct {
	max_quads: int,
}

// Collector owns copied RDF quads and all term strings referenced by them.
// Its quads remain valid until destroy is called. It preserves input order and
// duplicates; it is storage for parser results, not an RDF set implementation.
Collector :: struct {
	quads:      [dynamic]rdf.Quad,
	owned:      [dynamic]string,
	max_quads:  int,
	last_error: Error_Code,
}

// init prepares a collector. Call destroy exactly once after a successful
// initialization, including when a later parse or collection operation fails.
init :: proc(collector: ^Collector, options: Options = {}) -> Error_Code {
	if options.max_quads < 0 {
		collector.last_error = .Invalid_Option
		return collector.last_error
	}
	collector^ = Collector{
		quads = make([dynamic]rdf.Quad),
		owned = make([dynamic]string),
		max_quads = options.max_quads,
	}
	return .None
}

// destroy releases every copied term and retained quad. The collector must not
// be used again unless init is called again.
destroy :: proc(collector: ^Collector) {
	for value in collector.owned do delete(value)
	delete(collector.owned)
	delete(collector.quads)
	collector^ = {}
}

@(private) discard_owned_from :: proc(collector: ^Collector, start: int) {
	for index in start..<len(collector.owned) do delete(collector.owned[index])
	resize(&collector.owned, start)
}

@(private) copy_string :: proc(collector: ^Collector, value: string) -> (string, Error_Code) {
	if len(value) == 0 do return "", .None
	cloned, clone_error := strings.clone(value)
	if clone_error != nil do return "", .Out_Of_Memory
	_, append_error := append(&collector.owned, cloned)
	if append_error != nil {
		delete(cloned)
		return "", .Out_Of_Memory
	}
	return cloned, .None
}

@(private) copy_term :: proc(collector: ^Collector, term: rdf.Term) -> (rdf.Term, Error_Code) {
	result := term
	error: Error_Code
	result.value, error = copy_string(collector, term.value)
	if error != .None do return {}, error
	result.language, error = copy_string(collector, term.language)
	if error != .None do return {}, error
	result.datatype, error = copy_string(collector, term.datatype)
	if error != .None do return {}, error
	return result, .None
}

// add validates and copies one quad into collector. On failure it leaves the
// retained dataset unchanged and records the error in last_error.
add :: proc(collector: ^Collector, quad: rdf.Quad) -> Error_Code {
	if rdf.validate_quad_structure(quad) != .None {
		collector.last_error = .Invalid_Quad
		return collector.last_error
	}
	if collector.max_quads > 0 && len(collector.quads) >= collector.max_quads {
		collector.last_error = .Quad_Limit
		return collector.last_error
	}
	owned_start := len(collector.owned)
	stored: rdf.Quad
	error: Error_Code
	stored.subject, error = copy_term(collector, quad.subject)
	if error != .None {
		discard_owned_from(collector, owned_start)
		collector.last_error = error
		return error
	}
	stored.predicate, error = copy_term(collector, quad.predicate)
	if error != .None {
		discard_owned_from(collector, owned_start)
		collector.last_error = error
		return error
	}
	stored.object, error = copy_term(collector, quad.object)
	if error != .None {
		discard_owned_from(collector, owned_start)
		collector.last_error = error
		return error
	}
	stored.has_graph = quad.has_graph
	if quad.has_graph {
		stored.graph, error = copy_term(collector, quad.graph)
		if error != .None {
			discard_owned_from(collector, owned_start)
			collector.last_error = error
			return error
		}
	}
	_, append_error := append(&collector.quads, stored)
	if append_error != nil {
		discard_owned_from(collector, owned_start)
		collector.last_error = .Out_Of_Memory
		return collector.last_error
	}
	collector.last_error = .None
	return .None
}

// sink adapts a collector for any RDF Quad parser callback. A false result
// means add failed; inspect collector.last_error after parsing to distinguish a
// collector capacity or validation failure from a parser-requested stop.
sink :: proc(quad: rdf.Quad, user_data: rawptr) -> bool {
	collector := cast(^Collector)user_data
	return add(collector, quad) == .None
}

// triple_sink adapts a collector for RDF graph parsers by storing each triple
// as a default-graph quad. It follows the same failure contract as sink.
triple_sink :: proc(triple: rdf.Triple, user_data: rawptr) -> bool {
	collector := cast(^Collector)user_data
	return add(collector, rdf.default_graph_quad(triple)) == .None
}
