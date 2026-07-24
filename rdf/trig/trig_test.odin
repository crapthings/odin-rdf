package trig

import "core:strings"
import "core:testing"
import rdf ".."

@(private) collect :: proc(quad: rdf.Quad, data: rawptr) -> bool {
	append(cast(^[dynamic]rdf.Quad)data, quad)
	return true
}

@(private) Graph_Collect_State :: struct {
	quads:      [dynamic]rdf.Quad,
	graph_name: [128]byte,
	graph_len:  int,
	blank_graph: bool,
}

@(private) collect_graphs :: proc(quad: rdf.Quad, data: rawptr) -> bool {
	state := cast(^Graph_Collect_State)data
	append(&state.quads, quad)
	if quad.has_graph && quad.graph.kind == .IRI {
		state.graph_len = copy(state.graph_name[:], transmute([]byte)quad.graph.value)
	}
	if quad.has_graph && quad.graph.kind == .Blank_Node do state.blank_graph = true
	return true
}

@(test)
test_parses_default_and_named_graphs :: proc(t: ^testing.T) {
	input := `@prefix ex: <https://example.test/> .
ex:default ex:p "default" .
ex:graph { ex:s ex:p ex:o }
GRAPH _:other { ex:s ex:p (ex:a ex:b) . }`
	state: Graph_Collect_State
	defer delete(state.quads)
	err := parse(input, collect_graphs, {}, &state)
	testing.expect_value(t, err.code, Error_Code.None)
	testing.expect_value(t, len(state.quads), 7)
	if len(state.quads) == 7 {
		testing.expect(t, !state.quads[0].has_graph)
		testing.expect(t, state.quads[1].has_graph)
		testing.expect_value(t, string(state.graph_name[:state.graph_len]), "https://example.test/graph")
		testing.expect(t, state.quads[2].has_graph)
		testing.expect(t, state.blank_graph)
		for quad in state.quads[2:] do testing.expect(t, quad.has_graph)
	}
}

@(test)
test_parses_blank_property_list_with_trailing_semicolon :: proc(t: ^testing.T) {
	quads := make([dynamic]rdf.Quad)
	defer delete(quads)
	err := parse(`<urn:g> { <urn:outer> <urn:contains> [ <urn:p> <urn:o> ; ] . }`, collect, {}, &quads)
	testing.expect_value(t, err.code, Error_Code.None)
	testing.expect_value(t, len(quads), 2)
	if len(quads) == 2 {
		for quad in quads do testing.expect(t, quad.has_graph)
		testing.expect_value(t, quads[0].subject.value, "trig-genid-0")
		testing.expect_value(t, quads[0].predicate.value, "urn:p")
		testing.expect_value(t, quads[1].subject.value, "urn:outer")
		testing.expect_value(t, quads[1].predicate.value, "urn:contains")
		testing.expect_value(t, quads[1].object.value, "trig-genid-0")
	}
}

@(test)
test_rejects_literal_graph_name_without_emitting :: proc(t: ^testing.T) {
	quads := make([dynamic]rdf.Quad)
	defer delete(quads)
	err := parse(`"not-a-graph" { <urn:s> <urn:p> <urn:o> . }`, collect, {}, &quads)
	testing.expect_value(t, err.code, Error_Code.Expected_Subject)
	testing.expect_value(t, len(quads), 0)
}

@(test)
test_resource_limits_preserve_graph_block_atomicity :: proc(t: ^testing.T) {
	count := 0
	count_sink := proc(_: rdf.Quad, data: rawptr) -> bool {
		(cast(^int)data)^ += 1
		return true
	}
	pending_err := parse(`<urn:g> { <urn:s> <urn:p> <urn:a>, <urn:b> . }`, count_sink, Parse_Options{max_pending_quads = 1}, &count)
	testing.expect_value(t, pending_err.code, Error_Code.Pending_Quad_Limit)
	testing.expect_value(t, count, 0)

	quad_err := parse(`<urn:s> <urn:p> <urn:a> . <urn:g> { <urn:s> <urn:p> <urn:b>, <urn:c> . }`, count_sink, Parse_Options{max_quads = 2}, &count)
	testing.expect_value(t, quad_err.code, Error_Code.Quad_Limit)
	testing.expect_value(t, count, 1)
}

@(test)
test_reader_honors_document_bound :: proc(t: ^testing.T) {
	input := `<urn:g> { <urn:s> <urn:p> <urn:o> . }`
	state: strings.Reader
	result := parse_reader(strings.to_reader(&state, input), proc(_: rdf.Quad, _: rawptr) -> bool { return true }, Reader_Options{chunk_size = 1, max_document_bytes = 1024})
	testing.expect_value(t, result.error.code, Error_Code.None)
	testing.expect_value(t, result.quads, u64(1))
	testing.expect_value(t, result.bytes_read, u64(len(input)))

	limited_state: strings.Reader
	limited := parse_reader(strings.to_reader(&limited_state, input), proc(_: rdf.Quad, _: rawptr) -> bool { return true }, Reader_Options{max_document_bytes = 8})
	testing.expect_value(t, limited.error.code, Error_Code.Document_Too_Large)
}

@(test)
test_error_messages_cover_every_public_code :: proc(t: ^testing.T) {
	for code in Error_Code {
		testing.expect(t, parse_error_message(code) != "unknown error")
	}
}
