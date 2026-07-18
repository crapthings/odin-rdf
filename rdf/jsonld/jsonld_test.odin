package jsonld

import "core:strings"
import "core:testing"
import rdf ".."
import nquads "../nquads"

@(private) Collect_State :: struct {
	builder: strings.Builder,
	count:   int,
}

@(private) collect_quad :: proc(quad: rdf.Quad, user_data: rawptr) -> bool {
	state := cast(^Collect_State)user_data
	if nquads.write_quad(&state.builder, quad) != .None do return false
	state.count += 1
	return true
}

@(private) parse_to_nquads :: proc(input: string, options: Options = {}) -> (string, Parse_Error) {
	state := Collect_State{builder = strings.builder_make()}
	defer strings.builder_destroy(&state.builder)
	err := parse(input, collect_quad, options, &state)
	return strings.clone(strings.to_string(state.builder)) or_else "", err
}

@(private) remote_context :: proc(url: string, _: rawptr) -> (string, bool) {
	if url == "https://example.test/context" do return `{"@context":{"name":"https://schema.org/name"}}`, true
	return "", false
}

@(test)
test_basic_context_and_typed_values :: proc(t: ^testing.T) {
	actual, err := parse_to_nquads(`
{
  "@context": {"ex": "https://example.test/", "friend": {"@id": "ex:friend", "@type": "@id"}},
  "@id": "ex:alice",
  "ex:name": "Alice",
  "friend": "ex:bob",
  "ex:count": 4,
  "ex:active": true
}`)
	defer delete(actual)
	testing.expect_value(t, err.code, Error_Code.None)
	testing.expect(t, strings.contains(actual, `<https://example.test/alice> <https://example.test/name> "Alice" .`))
	testing.expect(t, strings.contains(actual, `<https://example.test/alice> <https://example.test/friend> <https://example.test/bob> .`))
	testing.expect(t, strings.contains(actual, `<https://example.test/alice> <https://example.test/count> "4"^^<http://www.w3.org/2001/XMLSchema#integer> .`))
	testing.expect(t, strings.contains(actual, `<https://example.test/alice> <https://example.test/active> "true"^^<http://www.w3.org/2001/XMLSchema#boolean> .`))
}

@(test)
test_list_reverse_named_graph_and_remote_context :: proc(t: ^testing.T) {
	actual, err := parse_to_nquads(`
{
  "@context": ["https://example.test/context", {"ex": "https://example.test/", "back": {"@reverse": "ex:knows"}}],
  "@id": "ex:alice",
  "name": "Alice",
  "back": {"@id": "ex:bob"},
  "ex:items": {"@list": ["one", "two"]},
  "@graph": {"@id": "ex:inside", "name": "Inside"}
}` , Options{document_loader = remote_context})
	defer delete(actual)
	testing.expect_value(t, err.code, Error_Code.None)
	testing.expect(t, strings.contains(actual, `<https://example.test/alice> <https://schema.org/name> "Alice" .`))
	testing.expect(t, strings.contains(actual, `<https://example.test/bob> <https://example.test/knows> <https://example.test/alice> .`))
	testing.expect(t, strings.contains(actual, `<https://example.test/inside> <https://schema.org/name> "Inside" <https://example.test/alice> .`))
	testing.expect(t, strings.contains(actual, `<http://www.w3.org/1999/02/22-rdf-syntax-ns#first> "one"`))
}

@(test)
test_resource_limits_and_invalid_remote_context :: proc(t: ^testing.T) {
	depth_output, depth_err := parse_to_nquads(`{"@context":{"ex":"https://example.test/"},"ex:a":{"ex:b":{"ex:c":"x"}}}`, Options{max_nesting_depth = 2})
	defer delete(depth_output)
	testing.expect_value(t, depth_err.code, Error_Code.Nesting_Limit)
	byte_output, byte_err := parse_to_nquads(`{"@id":"https://example.test/a"}`, Options{max_document_bytes = 4})
	defer delete(byte_output)
	testing.expect_value(t, byte_err.code, Error_Code.Document_Too_Large)
	remote_output, remote_err := parse_to_nquads(`{"@context":"https://example.test/context","name":"Alice"}`)
	defer delete(remote_output)
	testing.expect_value(t, remote_err.code, Error_Code.Remote_Context_Disallowed)
	quad_output, quad_err := parse_to_nquads(`{"https://example.test/a":"one","https://example.test/b":"two"}`, Options{max_quads = 1})
	defer delete(quad_output)
	testing.expect_value(t, quad_err.code, Error_Code.Quad_Limit)
	unsupported_output, unsupported_err := parse_to_nquads(`{"@context":{"@direction":"ltr"},"https://example.test/name":"Alice"}`)
	defer delete(unsupported_output)
	testing.expect_value(t, unsupported_err.code, Error_Code.Unsupported_Feature)
	base_output, base_err := parse_to_nquads(`{"https://example.test/name":"Alice"}`, Options{base_iri = "relative"})
	defer delete(base_output)
	testing.expect_value(t, base_err.code, Error_Code.Invalid_IRI)
	invalid_options_output, invalid_options_err := parse_to_nquads(`{}`, Options{max_contexts = -1})
	defer delete(invalid_options_output)
	testing.expect_value(t, invalid_options_err.code, Error_Code.Invalid_Option)
}

@(test)
test_reader_retains_one_bounded_document :: proc(t: ^testing.T) {
	input := `{"@context":{"ex":"https://example.test/"},"@id":"ex:alice","ex:name":"Alice"}`
	reader_state: strings.Reader
	state := Collect_State{builder = strings.builder_make()}
	defer strings.builder_destroy(&state.builder)
	result := parse_reader(strings.to_reader(&reader_state, input), collect_quad, Reader_Options{chunk_size = 3, max_document_bytes = 1024}, &state)
	testing.expect_value(t, result.error.code, Error_Code.None)
	testing.expect_value(t, result.quads, u64(1))
	testing.expect_value(t, result.bytes_read, u64(len(input)))

	limited_reader: strings.Reader
	limited_state := Collect_State{builder = strings.builder_make()}
	defer strings.builder_destroy(&limited_state.builder)
	limited := parse_reader(strings.to_reader(&limited_reader, input), collect_quad, Reader_Options{max_document_bytes = 8}, &limited_state)
	testing.expect_value(t, limited.error.code, Error_Code.Document_Too_Large)
	invalid_chunk := parse_reader(strings.to_reader(&limited_reader, input), collect_quad, Reader_Options{chunk_size = -1}, &limited_state)
	testing.expect_value(t, invalid_chunk.error.code, Error_Code.Invalid_Chunk_Size)
}
