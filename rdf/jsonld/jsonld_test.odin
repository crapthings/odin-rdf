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

@(test)
test_serializes_a_complete_dataset_to_deterministic_expanded_jsonld :: proc(t: ^testing.T) {
	quads := []rdf.Quad{
		rdf.named_graph_quad(rdf.Triple{
			subject = rdf.blank_node("inside", 7),
			predicate = rdf.iri("https://example.test/name"),
			object = rdf.language_literal("Inside", "en"),
		}, rdf.iri("https://example.test/graph")),
		rdf.default_graph_quad(rdf.Triple{
			subject = rdf.iri("https://example.test/alice"),
			predicate = rdf.iri(RDF_TYPE),
			object = rdf.iri("https://schema.org/Person"),
		}),
		rdf.default_graph_quad(rdf.Triple{
			subject = rdf.iri("https://example.test/alice"),
			predicate = rdf.iri("https://schema.org/name"),
			object = rdf.typed_literal("Alice", "https://example.test/Name"),
		}),
	}
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	testing.expect_value(t, serialize(&builder, quads), Serialize_Error.None)
	expected := `[
  {
    "@id": "https://example.test/alice",
    "@type": ["https://schema.org/Person"],
    "https://schema.org/name": [{"@value": "Alice", "@type": "https://example.test/Name"}]
  },
  {
    "@id": "https://example.test/graph",
    "@graph": [
      {
        "@id": "_:inside",
        "https://example.test/name": [{"@value": "Inside", "@language": "en"}]
      }
    ]
  }
]
`
	testing.expect_value(t, strings.to_string(builder), expected)

	round_trip, parse_err := parse_to_nquads(strings.to_string(builder))
	defer delete(round_trip)
	testing.expect_value(t, parse_err.code, Error_Code.None)
	testing.expect(t, strings.contains(round_trip, `<https://example.test/alice> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <https://schema.org/Person> .`))
	testing.expect(t, strings.contains(round_trip, `<https://example.test/alice> <https://schema.org/name> "Alice"^^<https://example.test/Name> .`))
	testing.expect(t, strings.contains(round_trip, `<https://example.test/name> "Inside"@en <https://example.test/graph> .`))
}

@(test)
test_serializer_rejects_ambiguous_blank_nodes_atomically :: proc(t: ^testing.T) {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	strings.write_string(&builder, "previous\n")
	quads := []rdf.Quad{
		rdf.default_graph_quad(rdf.Triple{subject = rdf.blank_node("same", 1), predicate = rdf.iri("urn:p"), object = rdf.iri("urn:o")}),
		rdf.default_graph_quad(rdf.Triple{subject = rdf.blank_node("same", 2), predicate = rdf.iri("urn:p"), object = rdf.iri("urn:o")}),
	}
	testing.expect_value(t, serialize(&builder, quads), Serialize_Error.Ambiguous_Blank_Node_Label)
	testing.expect_value(t, strings.to_string(builder), "previous\n")
	testing.expect_value(t, serialize(&builder, quads[:1], Serialize_Options{max_quads = 0 - 1}), Serialize_Error.Invalid_Option)
}

@(test)
test_serializer_preserves_non_iri_rdf_type_objects :: proc(t: ^testing.T) {
	quads := []rdf.Quad{rdf.default_graph_quad(rdf.Triple{
		subject = rdf.iri("https://example.test/s"),
		predicate = rdf.iri(RDF_TYPE),
		object = rdf.literal("not-a-class"),
	})}
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	testing.expect_value(t, serialize(&builder, quads), Serialize_Error.None)
	testing.expect(t, strings.contains(strings.to_string(builder), `"http://www.w3.org/1999/02/22-rdf-syntax-ns#type": [{"@value": "not-a-class"}]`))
	round_trip, parse_err := parse_to_nquads(strings.to_string(builder))
	defer delete(round_trip)
	testing.expect_value(t, parse_err.code, Error_Code.None)
	testing.expect(t, strings.contains(round_trip, `<https://example.test/s> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> "not-a-class" .`))
}

@(test)
test_serializer_can_preserve_rdf_type_as_an_ordinary_property :: proc(t: ^testing.T) {
	quads := []rdf.Quad{rdf.default_graph_quad(rdf.Triple{
		subject = rdf.iri("https://example.test/s"),
		predicate = rdf.iri(RDF_TYPE),
		object = rdf.iri("https://example.test/Class"),
	})}
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	testing.expect_value(t, serialize(&builder, quads, Serialize_Options{use_rdf_type = true}), Serialize_Error.None)
	testing.expect(t, strings.contains(strings.to_string(builder), `"http://www.w3.org/1999/02/22-rdf-syntax-ns#type": [{"@id": "https://example.test/Class"}]`))
	testing.expect(t, !strings.contains(strings.to_string(builder), `"@type": [`))
}

@(test)
test_serializer_writes_native_jsonld_scalars_only_when_requested :: proc(t: ^testing.T) {
	quads := []rdf.Quad{
		rdf.default_graph_quad(rdf.Triple{subject = rdf.iri("https://example.test/s"), predicate = rdf.iri("https://example.test/p"), object = rdf.typed_literal("1", XSD_BOOLEAN)}),
		rdf.default_graph_quad(rdf.Triple{subject = rdf.iri("https://example.test/s"), predicate = rdf.iri("https://example.test/p"), object = rdf.typed_literal("+001", XSD_INTEGER)}),
		rdf.default_graph_quad(rdf.Triple{subject = rdf.iri("https://example.test/s"), predicate = rdf.iri("https://example.test/p"), object = rdf.typed_literal("1.1E-1", XSD_DOUBLE)}),
		rdf.default_graph_quad(rdf.Triple{subject = rdf.iri("https://example.test/s"), predicate = rdf.iri("https://example.test/p"), object = rdf.typed_literal("+INF", XSD_DOUBLE)}),
	}
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	testing.expect_value(t, serialize(&builder, quads, Serialize_Options{use_native_types = true}), Serialize_Error.None)
	actual := strings.to_string(builder)
	testing.expect(t, strings.contains(actual, `"@value": true`))
	testing.expect(t, strings.contains(actual, `"@value": 1`))
	testing.expect(t, strings.contains(actual, `"@value": 0.11`))
	testing.expect(t, strings.contains(actual, `"@value": "+INF", "@type": "http://www.w3.org/2001/XMLSchema#double"`))
}

@(test)
test_round_trips_rdf_json_typed_literals_as_jsonld_json_values :: proc(t: ^testing.T) {
	input := `[{"@id":"https://example.test/s","https://example.test/p":[{"@value":{"answer":42},"@type":"@json"}]}]`
	quads, parse_error := parse_to_nquads(input)
	defer delete(quads)
	testing.expect_value(t, parse_error.code, Error_Code.None)
	testing.expect(t, strings.contains(quads, `"{\"answer\":42}"^^<http://www.w3.org/1999/02/22-rdf-syntax-ns#JSON>`))

	quad := rdf.default_graph_quad(rdf.Triple{subject = rdf.iri("https://example.test/s"), predicate = rdf.iri("https://example.test/p"), object = rdf.typed_literal(`{"answer":42}`, RDF_JSON)})
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	testing.expect_value(t, serialize(&builder, []rdf.Quad{quad}), Serialize_Error.None)
	testing.expect(t, strings.contains(strings.to_string(builder), `"@value": {"answer":42}, "@type": "@json"`))
}

@(test)
test_compacts_a_dataset_with_a_local_context_and_round_trips :: proc(t: ^testing.T) {
	head := rdf.blank_node("head", 1)
	tail := rdf.blank_node("tail", 1)
	graph := rdf.iri("https://example.test/graph")
	quads := []rdf.Quad{
		rdf.default_graph_quad(rdf.Triple{subject = rdf.iri("https://example.test/alice"), predicate = rdf.iri("https://example.test/name"), object = rdf.literal("Alice")}),
		rdf.default_graph_quad(rdf.Triple{subject = rdf.iri("https://example.test/alice"), predicate = rdf.iri("https://example.test/knows"), object = rdf.iri("https://example.test/bob")}),
		rdf.default_graph_quad(rdf.Triple{subject = rdf.iri("https://example.test/alice"), predicate = rdf.iri("https://example.test/age"), object = rdf.typed_literal("42", XSD_INTEGER)}),
		rdf.default_graph_quad(rdf.Triple{subject = rdf.iri("https://example.test/alice"), predicate = rdf.iri("https://example.test/items"), object = head}),
		rdf.default_graph_quad(rdf.Triple{subject = head, predicate = rdf.iri(RDF_FIRST), object = rdf.literal("one")}),
		rdf.default_graph_quad(rdf.Triple{subject = head, predicate = rdf.iri(RDF_REST), object = tail}),
		rdf.default_graph_quad(rdf.Triple{subject = tail, predicate = rdf.iri(RDF_FIRST), object = rdf.literal("two")}),
		rdf.default_graph_quad(rdf.Triple{subject = tail, predicate = rdf.iri(RDF_REST), object = rdf.iri(RDF_NIL)}),
		rdf.named_graph_quad(rdf.Triple{subject = rdf.iri("https://example.test/inside"), predicate = rdf.iri("https://example.test/name"), object = rdf.literal("Inside")}, graph),
	}
	context_text := `{"@vocab":"https://example.test/","name":"name","knows":{"@id":"knows","@type":"@vocab"},"age":{"@id":"age","@type":"http://www.w3.org/2001/XMLSchema#integer"},"items":{"@id":"items","@container":"@list"}}`
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	testing.expect_value(t, compact(&builder, quads, context_text), Compact_Error.None)
	output := strings.to_string(builder)
	testing.expect(t, strings.contains(output, `"name": "Alice"`))
	testing.expect(t, strings.contains(output, `"knows": "bob"`))
	testing.expect(t, strings.contains(output, `"age": 42`))
	testing.expect(t, strings.contains(output, `"items": ["one", "two"]`))
	testing.expect(t, strings.contains(output, `"@graph": [`))
	second_builder := strings.builder_make()
	defer strings.builder_destroy(&second_builder)
	testing.expect_value(t, compact(&second_builder, quads, context_text), Compact_Error.None)
	testing.expect_value(t, strings.to_string(second_builder), output)
	round_trip, parse_error := parse_to_nquads(output)
	defer delete(round_trip)
	testing.expect_value(t, parse_error.code, Error_Code.None)
	testing.expect(t, strings.contains(round_trip, `<https://example.test/alice> <https://example.test/name> "Alice" .`))
	testing.expect(t, strings.contains(round_trip, `<https://example.test/alice> <https://example.test/knows> <https://example.test/bob> .`))
	testing.expect(t, strings.contains(round_trip, `<https://example.test/alice> <https://example.test/age> "42"^^<http://www.w3.org/2001/XMLSchema#integer> .`))
	testing.expect(t, strings.contains(round_trip, `<https://example.test/inside> <https://example.test/name> "Inside" <https://example.test/graph> .`))
}

@(test)
test_language_and_index_containers_preserve_rdf_semantics :: proc(t: ^testing.T) {
	context_text := `{"@context":{"label":{"@id":"https://example.test/label","@container":"@language"},"person":{"@id":"https://example.test/person","@container":"@index","@index":"https://example.test/name"}}}`
	input := `{
  "@context": {"label":{"@id":"https://example.test/label","@container":"@language"},"person":{"@id":"https://example.test/person","@container":"@index","@index":"https://example.test/name"}},
  "@id":"https://example.test/article",
  "label":{"en":"Hello","de":["Hallo","Guten Tag"]},
  "person":{"alice":{"@id":"https://example.test/alice"}}
}`
	parsed, parse_error := parse_to_nquads(input)
	defer delete(parsed)
	testing.expect_value(t, parse_error.code, Error_Code.None)
	testing.expect(t, strings.contains(parsed, `<https://example.test/article> <https://example.test/label> "Hello"@en .`))
	testing.expect(t, strings.contains(parsed, `<https://example.test/article> <https://example.test/label> "Hallo"@de .`))
	testing.expect(t, strings.contains(parsed, `<https://example.test/alice> <https://example.test/name> "alice" .`))

	quads := []rdf.Quad{
		rdf.default_graph_quad(rdf.Triple{subject = rdf.iri("https://example.test/article"), predicate = rdf.iri("https://example.test/label"), object = rdf.language_literal("Hello", "en")} ),
		rdf.default_graph_quad(rdf.Triple{subject = rdf.iri("https://example.test/article"), predicate = rdf.iri("https://example.test/label"), object = rdf.language_literal("Hallo", "de")} ),
		rdf.default_graph_quad(rdf.Triple{subject = rdf.iri("https://example.test/article"), predicate = rdf.iri("https://example.test/label"), object = rdf.language_literal("Guten Tag", "de")} ),
	}
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	testing.expect_value(t, compact(&builder, quads, context_text), Compact_Error.None)
	output := strings.to_string(builder)
	testing.expect(t, strings.contains(output, `"label": {"de": ["Guten Tag", "Hallo"], "en": "Hello"}`))
	round_trip, round_trip_error := parse_to_nquads(output)
	defer delete(round_trip)
	testing.expect_value(t, round_trip_error.code, Error_Code.None)
	testing.expect(t, strings.contains(round_trip, `<https://example.test/article> <https://example.test/label> "Hello"@en .`))
	testing.expect(t, strings.contains(round_trip, `<https://example.test/article> <https://example.test/label> "Guten Tag"@de .`))
}

@(test)
test_language_map_none_key_suppresses_the_default_language :: proc(t: ^testing.T) {
	input := `{
  "@context": {
    "@language": "de",
    "label": {"@id": "https://example.test/label", "@container": "@language"}
  },
  "@id": "https://example.test/s",
  "label": {"@none": "plain", "en": "English"}
}`
	actual, err := parse_to_nquads(input)
	defer delete(actual)
	testing.expect_value(t, err.code, Error_Code.None)
	testing.expect(t, strings.contains(actual, `<https://example.test/s> <https://example.test/label> "plain" .`))
	testing.expect(t, !strings.contains(actual, `<https://example.test/s> <https://example.test/label> "plain"@de .`))
	testing.expect(t, strings.contains(actual, `<https://example.test/s> <https://example.test/label> "English"@en .`))
}

@(test)
test_set_combined_with_language_and_index_containers :: proc(t: ^testing.T) {
	input := `{
  "@context": {
    "label": {"@id": "https://example.test/label", "@container": ["@language", "@set"]},
    "item": {"@id": "https://example.test/item", "@container": ["@index", "@set"]}
  },
  "@id": "https://example.test/s",
  "label": {"en": ["One", "Two"]},
  "item": {"first": {"@id": "https://example.test/one"}}
}`
	actual, err := parse_to_nquads(input)
	defer delete(actual)
	testing.expect_value(t, err.code, Error_Code.None)
	testing.expect(t, strings.contains(actual, `<https://example.test/s> <https://example.test/label> "One"@en .`))
	testing.expect(t, strings.contains(actual, `<https://example.test/s> <https://example.test/item> <https://example.test/one> .`))
}

@(test)
test_rejects_duplicate_container_members :: proc(t: ^testing.T) {
	output, err := parse_to_nquads(`{
  "@context": {
    "label": {
      "@id": "https://example.test/label",
      "@container": ["@set", "@set"]
    }
  },
  "label": "duplicate"
}`)
	defer delete(output)
	testing.expect_value(t, err.code, Error_Code.Invalid_Term_Definition)
}

@(test)
test_compaction_does_not_apply_a_default_language_to_plain_rdf_literals :: proc(t: ^testing.T) {
	quads := []rdf.Quad{rdf.default_graph_quad(rdf.Triple{
		subject = rdf.iri("https://example.test/s"),
		predicate = rdf.iri("https://example.test/plain"),
		object = rdf.literal("plain"),
	})}
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	context_text := `{"@language":"de","plain":{"@id":"https://example.test/plain","@language":null}}`
	testing.expect_value(t, compact(&builder, quads, context_text), Compact_Error.None)
	testing.expect(t, strings.contains(strings.to_string(builder), `"plain": "plain"`))
	round_trip, parse_error := parse_to_nquads(strings.to_string(builder))
	defer delete(round_trip)
	testing.expect_value(t, parse_error.code, Error_Code.None)
	testing.expect(t, strings.contains(round_trip, `<https://example.test/s> <https://example.test/plain> "plain" .`))
	testing.expect(t, !strings.contains(round_trip, `<https://example.test/s> <https://example.test/plain> "plain"@de .`))
}

@(test)
test_compaction_array_policy_and_context_failures_are_atomic :: proc(t: ^testing.T) {
	quads := []rdf.Quad{rdf.default_graph_quad(rdf.Triple{subject = rdf.iri("https://example.test/s"), predicate = rdf.iri("https://example.test/name"), object = rdf.literal("Alice")})}
	context_text := `{"name":"https://example.test/name"}`
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	testing.expect_value(t, compact(&builder, quads, context_text, Compact_Options{array_policy = .Preserve}), Compact_Error.None)
	testing.expect(t, strings.contains(strings.to_string(builder), `"name": ["Alice"]`))
	strings.builder_reset(&builder)
	strings.write_string(&builder, "previous\n")
	testing.expect_value(t, compact(&builder, quads, `{`), Compact_Error.Invalid_Context)
	testing.expect_value(t, strings.to_string(builder), "previous\n")
	testing.expect_value(t, compact(&builder, quads, context_text, Compact_Options{context_options = {max_contexts = -1}}), Compact_Error.Invalid_Option)
}

@(test)
test_serializer_collapses_only_unshared_complete_rdf_lists :: proc(t: ^testing.T) {
	a := rdf.blank_node("a", 1)
	b := rdf.blank_node("b", 1)
	quads := []rdf.Quad{
		rdf.default_graph_quad(rdf.Triple{subject = rdf.iri("https://example.test/s"), predicate = rdf.iri("https://example.test/items"), object = a}),
		rdf.default_graph_quad(rdf.Triple{subject = a, predicate = rdf.iri(RDF_FIRST), object = rdf.literal("one")}),
		rdf.default_graph_quad(rdf.Triple{subject = a, predicate = rdf.iri(RDF_REST), object = b}),
		rdf.default_graph_quad(rdf.Triple{subject = b, predicate = rdf.iri(RDF_FIRST), object = rdf.iri("https://example.test/two")}),
		rdf.default_graph_quad(rdf.Triple{subject = b, predicate = rdf.iri(RDF_REST), object = rdf.iri(RDF_NIL)}),
	}
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	testing.expect_value(t, serialize(&builder, quads), Serialize_Error.None)
	output := strings.to_string(builder)
	testing.expect(t, strings.contains(output, `"@list": [{"@value": "one"}, {"@id": "https://example.test/two"}]`))
	testing.expect(t, !strings.contains(output, RDF_FIRST))

	shared := make([dynamic]rdf.Quad)
	defer delete(shared)
	for quad in quads do append(&shared, quad)
	append(&shared, rdf.default_graph_quad(rdf.Triple{subject = rdf.iri("https://example.test/other"), predicate = rdf.iri("https://example.test/items"), object = a}))
	strings.builder_reset(&builder)
	testing.expect_value(t, serialize(&builder, shared[:]), Serialize_Error.None)
	testing.expect(t, strings.contains(strings.to_string(builder), RDF_FIRST))
}

@(test)
test_serializer_preserves_list_nodes_shared_between_named_graphs :: proc(t: ^testing.T) {
	graph := rdf.iri("https://example.test/graph")
	other_graph := rdf.iri("https://example.test/other-graph")
	head := rdf.blank_node("head", 1)
	tail := rdf.blank_node("tail", 1)
	quads := []rdf.Quad{
		rdf.named_graph_quad(rdf.Triple{subject = rdf.iri("https://example.test/s"), predicate = rdf.iri("https://example.test/items"), object = head}, graph),
		rdf.named_graph_quad(rdf.Triple{subject = head, predicate = rdf.iri(RDF_FIRST), object = rdf.literal("one")}, graph),
		rdf.named_graph_quad(rdf.Triple{subject = head, predicate = rdf.iri(RDF_REST), object = tail}, graph),
		rdf.named_graph_quad(rdf.Triple{subject = tail, predicate = rdf.iri(RDF_FIRST), object = rdf.literal("two")}, graph),
		rdf.named_graph_quad(rdf.Triple{subject = tail, predicate = rdf.iri(RDF_REST), object = rdf.iri(RDF_NIL)}, graph),
		rdf.named_graph_quad(rdf.Triple{subject = rdf.iri("https://example.test/other"), predicate = rdf.iri("https://example.test/items"), object = tail}, other_graph),
	}
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	testing.expect_value(t, serialize(&builder, quads), Serialize_Error.None)
	testing.expect(t, strings.contains(strings.to_string(builder), RDF_FIRST))
	testing.expect(t, !strings.contains(strings.to_string(builder), `"@list": [{"@value": "one"}`))

	quads[len(quads) - 1].object = head
	strings.builder_reset(&builder)
	testing.expect_value(t, serialize(&builder, quads), Serialize_Error.None)
	output := strings.to_string(builder)
	testing.expect(t, strings.contains(output, RDF_FIRST))
	testing.expect(t, strings.contains(output, `"@list": [{"@value": "two"}]`))
}

@(test)
test_serializer_merges_named_graph_objects_with_default_graph_properties :: proc(t: ^testing.T) {
	graph := rdf.iri("https://example.test/graph")
	quads := []rdf.Quad{
		rdf.default_graph_quad(rdf.Triple{subject = graph, predicate = rdf.iri(RDF_TYPE), object = rdf.iri("https://example.test/Graph")}),
		rdf.default_graph_quad(rdf.Triple{subject = graph, predicate = rdf.iri("https://example.test/name"), object = rdf.literal("Graph")}),
		rdf.named_graph_quad(rdf.Triple{subject = rdf.iri("https://example.test/inside"), predicate = rdf.iri("https://example.test/name"), object = rdf.literal("Inside")}, graph),
	}
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	testing.expect_value(t, serialize(&builder, quads), Serialize_Error.None)
	output := strings.to_string(builder)
	testing.expect_value(t, strings.count(output, `"@id": "https://example.test/graph"`), 1)
	testing.expect(t, strings.contains(output, `"@graph": [`))
	testing.expect(t, strings.contains(output, `"@type": ["https://example.test/Graph"]`))
	testing.expect(t, strings.contains(output, `"https://example.test/name": [{"@value": "Graph"}]`))
}
