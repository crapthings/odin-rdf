package nquads

import "core:testing"
import rdf ".."

@(private) Collect_State :: struct {
	quads: [dynamic]rdf.Quad,
	named_graph: [16]byte,
	named_len:   int,
	scopes_match: bool,
}

@(private) collect :: proc(quad: rdf.Quad, data: rawptr) -> bool {
	state := cast(^Collect_State)data
	append(&state.quads, quad)
	if quad.has_graph && quad.graph.kind == .IRI {
		state.named_len = copy(state.named_graph[:], transmute([]byte)quad.graph.value)
	}
	if quad.has_graph && quad.graph.kind == .Blank_Node {
		state.scopes_match = quad.subject.scope == quad.graph.scope
	}
	return true
}

@(private) ignore :: proc(_: rdf.Quad, _: rawptr) -> bool { return true }

@(private) Scope_State :: struct {
	first:  rdf.Blank_Node_Scope,
	second: rdf.Blank_Node_Scope,
	calls:  int,
}

@(private) collect_scope :: proc(quad: rdf.Quad, data: rawptr) -> bool {
	state := cast(^Scope_State)data
	if state.calls == 0 do state.first = quad.subject.scope
	else do state.second = quad.subject.scope
	state.calls += 1
	return true
}

@(test)
test_parse_default_and_named_graphs :: proc(t: ^testing.T) {
	input := `<urn:s> <urn:p> <urn:o> .
<urn:s> <urn:p> "hello"@en <urn:g> .
_:s <urn:p> _:o _:g .`
	state: Collect_State
	defer delete(state.quads)
	err := parse(input, collect, &state)
	testing.expect_value(t, err.code, Error_Code.None)
	testing.expect_value(t, len(state.quads), 3)
	if len(state.quads) == 3 {
		testing.expect(t, !state.quads[0].has_graph)
		testing.expect_value(t, string(state.named_graph[:state.named_len]), "urn:g")
		testing.expect_value(t, state.quads[2].graph.kind, rdf.Term_Kind.Blank_Node)
		testing.expect(t, state.scopes_match)
	}
}

@(test)
test_reject_graph_literal_and_fifth_term :: proc(t: ^testing.T) {
	err := parse(`<urn:s> <urn:p> <urn:o> "graph" .`, ignore)
	testing.expect_value(t, err.code, Error_Code.Invalid_Graph)
	err = parse(`<urn:s> <urn:p> <urn:o> <urn:g> <urn:fifth> .`, ignore)
	testing.expect_value(t, err.code, Error_Code.Trailing_Data)
}

@(test)
test_preserves_term_error_codes_and_locations :: proc(t: ^testing.T) {
	err := parse(`<urn:s> <urn:p> "\q" <urn:g> .`, ignore)
	testing.expect_value(t, err.code, Error_Code.Invalid_Escape)
	testing.expect_value(t, err.line, 1)
	testing.expect_value(t, err.column, 18)

	err = parse("\n<urn:s> <urn:p> <urn:o> <relative> .", ignore)
	testing.expect_value(t, err.code, Error_Code.Invalid_IRI)
	testing.expect_value(t, err.line, 2)
	testing.expect_value(t, err.column, 34)

	err = parse(`<urn:s> <urn:p> "x"@en- <urn:g> .`, ignore)
	testing.expect_value(t, err.code, Error_Code.Invalid_Language_Tag)
}

@(test)
test_minimal_whitespace_and_comments :: proc(t: ^testing.T) {
	input := "# header\n<urn:s><urn:p><urn:o><urn:g>.# tail\n_:s<urn:p>\"x\".\n"
	err := parse(input, ignore)
	testing.expect_value(t, err.code, Error_Code.None)
}

@(test)
test_empty_comments_cr_and_nil_sink :: proc(t: ^testing.T) {
	testing.expect_value(t, parse("", ignore).code, Error_Code.None)
	testing.expect_value(t, parse("# comment\r", ignore).code, Error_Code.None)
	err := parse(`<urn:s> <urn:p> <urn:o> .`, nil)
	testing.expect_value(t, err.code, Error_Code.Missing_Sink)
	testing.expect_value(t, err.line, 1)
	testing.expect_value(t, err.column, 1)
}

@(test)
test_sink_stop_and_document_local_blank_node_scope :: proc(t: ^testing.T) {
	stop := proc(_: rdf.Quad, _: rawptr) -> bool { return false }
	err := parse(`<urn:s> <urn:p> <urn:o> .`, stop)
	testing.expect_value(t, err.code, Error_Code.Stopped)
	testing.expect_value(t, err.line, 1)

	within: Scope_State
	err = parse("_:same <urn:p> <urn:o> _:same .\n_:same <urn:p> <urn:o> .", collect_scope, &within)
	testing.expect_value(t, err.code, Error_Code.None)
	testing.expect(t, within.first != rdf.Blank_Node_Scope(0))
	testing.expect_value(t, within.first, within.second)

	separate: Scope_State
	err = parse(`_:same <urn:p> <urn:o> .`, collect_scope, &separate)
	testing.expect_value(t, err.code, Error_Code.None)
	testing.expect(t, separate.first != within.first)
}

@(test)
test_parse_error_messages_are_stable :: proc(t: ^testing.T) {
	messages := [Error_Code]string{
		.None               = "no error",
		.Unexpected_End     = "unexpected end of input",
		.Expected_Quad      = "expected N-Quads statement",
		.Expected_Term      = "expected RDF term",
		.Expected_IRI       = "expected IRI",
		.Expected_Dot       = "expected terminating dot",
		.Trailing_Data      = "unexpected data after quad",
		.Invalid_UTF8       = "invalid UTF-8",
		.Invalid_IRI        = "invalid absolute IRI",
		.Invalid_Escape     = "invalid escape sequence",
		.Invalid_Unicode_Escape = "invalid Unicode escape",
		.Invalid_Blank_Node = "invalid blank-node label",
		.Invalid_Language_Tag = "invalid language tag",
		.Invalid_Graph      = "graph name must be an IRI or blank node",
		.Missing_Sink       = "sink is required",
		.Invalid_Chunk_Size = "chunk size must not be negative",
		.Invalid_Line_Limit = "line limit must not be negative",
		.Line_Too_Long      = "line exceeds configured limit",
		.Quad_Limit         = "quad limit reached",
		.Reader_Error       = "reader error",
		.No_Progress        = "reader made no progress",
		.Stopped            = "stopped by sink",
	}
	for code in Error_Code do testing.expect_value(t, parse_error_message(code), messages[code])
}

@(test)
test_parser_handles_deterministic_random_bytes :: proc(t: ^testing.T) {
	state := u64(0x6e7175616473)
	buffer: [96]byte
	for length in 0..=len(buffer) {
		for _ in 0..<16 {
			for i in 0..<length {
				state = state * 6364136223846793005 + 1442695040888963407
				buffer[i] = byte(state >> 56)
			}
			_ = parse(string(buffer[:length]), ignore)
		}
	}
	testing.expect(t, true)
}
