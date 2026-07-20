package jsonld

import "core:strings"
import "core:testing"
import json "core:encoding/json"
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

@(private) imported_context :: proc(url: string, _: rawptr) -> (string, bool) {
	switch url {
	case "https://example.test/document/imported.jsonld":
		return `{"@context":{"name":"https://example.test/imported-name","term":"https://example.test/imported-term"}}`, true
	case "https://example.test/document/array.jsonld":
		return `{"@context":[{"term":"https://example.test/term"}]}`, true
	case "https://example.test/document/nested.jsonld":
		return `{"@context":{"@import":"imported.jsonld"}}`, true
	case "https://example.test/document/protected.jsonld":
		return `{"@context":{"protected1":{"@id":"https://example.test/protected1"},"protected2":{"@id":"https://example.test/protected2"}}}`, true
	case "https://w3c.github.io/json-ld-api/tests/expand/so07-context.jsonld":
		return `{"@context":{"protected1":{"@id":"http://example.com/protected1"},"protected2":{"@id":"http://example.com/protected2"}}}`, true
	}
	return "", false
}

@(private) Import_Load_State :: struct {
	calls: int,
}

@(private) counting_imported_context :: proc(url: string, user_data: rawptr) -> (string, bool) {
	state := cast(^Import_Load_State)user_data
	state.calls += 1
	return imported_context(url, nil)
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
test_imported_context_applies_before_local_definitions :: proc(t: ^testing.T) {
	options := Options{base_iri = "https://example.test/document/input.jsonld", document_loader = imported_context}
	actual, err := parse_to_nquads(`{
  "@context": {"@import": "imported.jsonld", "name": "https://example.test/local-name"},
  "@id": "https://example.test/resource",
  "name": "Alice",
  "term": "value"
}`, options)
	defer delete(actual)
	testing.expect_value(t, err.code, Error_Code.None)
	testing.expect(t, strings.contains(actual, `<https://example.test/resource> <https://example.test/local-name> "Alice" .`))
	testing.expect(t, strings.contains(actual, `<https://example.test/resource> <https://example.test/imported-term> "value" .`))

	no_loader, no_loader_err := parse_to_nquads(`{"@context":{"@import":"imported.jsonld"}}`, Options{base_iri = options.base_iri})
	defer delete(no_loader)
	testing.expect_value(t, no_loader_err.code, Error_Code.Remote_Context_Disallowed)
	array_source, array_source_err := parse_to_nquads(`{"@context":{"@import":"array.jsonld"}}`, options)
	defer delete(array_source)
	testing.expect_value(t, array_source_err.code, Error_Code.Invalid_Context)
	nested_source, nested_source_err := parse_to_nquads(`{"@context":{"@import":"nested.jsonld"}}`, options)
	defer delete(nested_source)
	testing.expect_value(t, nested_source_err.code, Error_Code.Invalid_Context)
}

@(test)
test_protected_imported_terms_reject_later_redefinition :: proc(t: ^testing.T) {
	state := State{remote_urls = make(map[string]bool), named_bnodes = make(map[string]rdf.Term), max_contexts = DEFAULT_MAX_CONTEXTS, max_remote = DEFAULT_MAX_REMOTE_CONTEXTS, loader = imported_context, allow_document_containers = true}
	defer destroy_state(&state)
	ctx, make_error := make_context(&state, nil)
	testing.expect_value(t, make_error.code, Error_Code.None)
	ctx.base_iri = "https://example.test/document/input.jsonld"
	protected_context, protected_json_error := json.parse_string(`{"@protected":true,"@import":"protected.jsonld"}`, .JSON, true)
	defer json.destroy_value(protected_context)
	testing.expect_value(t, protected_json_error, json.Error.None)
	apply_error: Parse_Error
	ctx, apply_error = apply_context(&state, &ctx, protected_context)
	testing.expect_value(t, apply_error.code, Error_Code.None)
	imported_definition := ctx.terms["protected1"]
	testing.expect(t, imported_definition.protected)
	redefinition, redefinition_json_error := json.parse_string(`{"protected1":"https://example.test/redefined"}`, .JSON, true)
	defer json.destroy_value(redefinition)
	testing.expect_value(t, redefinition_json_error, json.Error.None)
	_, redefinition_error := apply_context(&state, &ctx, redefinition)
	testing.expect_value(t, redefinition_error.code, Error_Code.Protected_Term_Redefinition)
	merge_state := State{remote_urls = make(map[string]bool), named_bnodes = make(map[string]rdf.Term), max_contexts = DEFAULT_MAX_CONTEXTS, max_remote = DEFAULT_MAX_REMOTE_CONTEXTS, loader = imported_context, allow_document_containers = true}
	defer destroy_state(&merge_state)
	merge_ctx, merge_make_error := make_context(&merge_state, nil)
	testing.expect_value(t, merge_make_error.code, Error_Code.None)
	merge_ctx.base_iri = "https://example.test/document/input.jsonld"
	merged_context, merged_json_error := json.parse_string(`{"@protected":true,"@import":"protected.jsonld","protected1":"https://example.test/override"}`, .JSON, true)
	defer json.destroy_value(merged_context)
	testing.expect_value(t, merged_json_error, json.Error.None)
	merge_ctx, apply_error = apply_context(&merge_state, &merge_ctx, merged_context)
	testing.expect_value(t, apply_error.code, Error_Code.None)
	merged_definition := merge_ctx.terms["protected1"]
	testing.expect_value(t, merged_definition.id, "https://example.test/override")
	testing.expect(t, merged_definition.protected)
	expanded := strings.builder_make()
	defer strings.builder_destroy(&expanded)
	input := `{"@context":{"@vocab":"http://example.com/","@version":1.1,"@protected":true,"@import":"so07-context.jsonld"},"protected1":{"@context":{"protected1":"http://example.com/something-else","protected2":"http://example.com/something-else"},"protected1":"error / property http://example.com/protected1","protected2":"error / property http://example.com/protected2"}}`
	expand_options := Expand_Options{context_options = {base_iri = "https://w3c.github.io/json-ld-api/tests/expand/so07-in.jsonld", document_loader = imported_context}}
	testing.expect_value(t, expand(&expanded, input, expand_options), Expand_Error.Protected_Term_Redefinition)
}

@(test)
test_expand_resolves_each_object_context_once :: proc(t: ^testing.T) {
	load_state := Import_Load_State{}
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	input := `{
  "@context": {"ex": "https://example.test/"},
  "ex:property": {
    "@context": {"@import": "imported.jsonld"},
    "term": "value"
  }
}`
	options := Expand_Options{context_options = {base_iri = "https://example.test/document/input.jsonld", document_loader = counting_imported_context, loader_data = &load_state}}
	testing.expect_value(t, expand_document(&builder, input, options, false, false), Expand_Error.None)
	testing.expect_value(t, load_state.calls, 1)
	testing.expect(t, strings.contains(strings.to_string(builder), `"https://example.test/imported-term"`))
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
	direction_output, direction_err := parse_to_nquads(`{"@context":{"@direction":"ltr"},"https://example.test/name":"Alice"}`)
	defer delete(direction_output)
	testing.expect_value(t, direction_err.code, Error_Code.None)
	testing.expect(t, strings.contains(direction_output, `"Alice"`))
	i18n_output, i18n_err := parse_to_nquads(`{"https://example.test/name":{"@value":"Alice","@language":"EN-US","@direction":"rtl"}}`, Options{rdf_direction = .I18n_Datatype})
	defer delete(i18n_output)
	testing.expect_value(t, i18n_err.code, Error_Code.None)
	testing.expect(t, strings.contains(i18n_output, `<https://www.w3.org/ns/i18n#en-us_rtl>`))
	compound_output, compound_err := parse_to_nquads(`{"https://example.test/name":{"@value":"Alice","@language":"EN-US","@direction":"rtl"}}`, Options{rdf_direction = .Compound_Literal})
	defer delete(compound_output)
	testing.expect_value(t, compound_err.code, Error_Code.None)
	testing.expect(t, strings.contains(compound_output, `<http://www.w3.org/1999/02/22-rdf-syntax-ns#value> "Alice"`))
	testing.expect(t, strings.contains(compound_output, `<http://www.w3.org/1999/02/22-rdf-syntax-ns#language> "en-us"`))
	testing.expect(t, strings.contains(compound_output, `<http://www.w3.org/1999/02/22-rdf-syntax-ns#direction> "rtl"`))
	base_output, base_err := parse_to_nquads(`{"https://example.test/name":"Alice"}`, Options{base_iri = "relative"})
	defer delete(base_output)
	testing.expect_value(t, base_err.code, Error_Code.Invalid_IRI)
	invalid_options_output, invalid_options_err := parse_to_nquads(`{}`, Options{max_contexts = -1})
	defer delete(invalid_options_output)
	testing.expect_value(t, invalid_options_err.code, Error_Code.Invalid_Option)
}

@(test)
test_expands_nested_set_values_and_ignores_nulls :: proc(t: ^testing.T) {
	input := `{
  "@context": {
    "p": "https://example.test/p",
    "items": {"@id":"https://example.test/items", "@container":"@list"}
  },
  "@id": "https://example.test/s",
  "p": {"@set": ["one", {"@set": [null, "two"]}, null]},
  "items": {"@list": [null]}
}`
	actual, err := parse_to_nquads(input)
	defer delete(actual)
	testing.expect_value(t, err.code, Error_Code.None)
	testing.expect(t, strings.contains(actual, `<https://example.test/s> <https://example.test/p> "one" .`))
	testing.expect(t, strings.contains(actual, `<https://example.test/s> <https://example.test/p> "two" .`))
	testing.expect(t, strings.contains(actual, `<https://example.test/s> <https://example.test/items> <http://www.w3.org/1999/02/22-rdf-syntax-ns#nil> .`))
	testing.expect(t, !strings.contains(actual, `"null"`))

	aliased, aliased_err := parse_to_nquads(`{
  "@context": {
    "p": "https://example.test/p",
    "value": "@value",
    "type": "@type",
    "xsd": "http://www.w3.org/2001/XMLSchema#"
  },
  "p": {"value":"2026-07-20", "type":"xsd:date"}
}`)
	defer delete(aliased)
	testing.expect_value(t, aliased_err.code, Error_Code.None)
	testing.expect(t, strings.contains(aliased, `"2026-07-20"^^<http://www.w3.org/2001/XMLSchema#date>`))

	unmapped, unmapped_err := parse_to_nquads(`{"@id":"https://example.test/s","ignored":"no","https://example.test/p":"yes"}`)
	defer delete(unmapped)
	testing.expect_value(t, unmapped_err.code, Error_Code.None)
	testing.expect(t, strings.contains(unmapped, `<https://example.test/s> <https://example.test/p> "yes" .`))
	testing.expect(t, !strings.contains(unmapped, "ignored"))

	language_only, language_only_err := parse_to_nquads(`{"@id":"https://example.test/s","https://example.test/p":{"@language":"en"}}`)
	defer delete(language_only)
	testing.expect_value(t, language_only_err.code, Error_Code.None)
	testing.expect_value(t, language_only, "")
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
test_serializer_rejects_invalid_rdf_json_literals :: proc(t: ^testing.T) {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	quad := rdf.Quad{
		subject = rdf.iri("https://example.test/node"),
		predicate = rdf.iri("https://example.test/value"),
		object = rdf.typed_literal("not-json", RDF_JSON),
	}
	testing.expect_value(t, serialize(&builder, []rdf.Quad{quad}), Serialize_Error.Invalid_JSON_Literal)
	testing.expect_value(t, strings.to_string(builder), "")
}

@(test)
test_round_trips_i18n_direction_datatypes_when_enabled :: proc(t: ^testing.T) {
	quad := rdf.default_graph_quad(rdf.Triple{
		subject = rdf.iri("https://example.test/s"),
		predicate = rdf.iri("https://example.test/label"),
		object = rdf.typed_literal("Hello", "https://www.w3.org/ns/i18n#en-us_rtl"),
	})
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	options := Serialize_Options{rdf_direction = .I18n_Datatype}
	testing.expect_value(t, serialize(&builder, []rdf.Quad{quad}, options), Serialize_Error.None)
	serialized := strings.to_string(builder)
	testing.expect(t, strings.contains(serialized, `"@language": "en-us", "@direction": "rtl"`))
	round_trip, parse_error := parse_to_nquads(serialized, Options{rdf_direction = .I18n_Datatype})
	defer delete(round_trip)
	testing.expect_value(t, parse_error.code, Error_Code.None)
	testing.expect(t, strings.contains(round_trip, `"Hello"^^<https://www.w3.org/ns/i18n#en-us_rtl>`))

	compact_builder := strings.builder_make()
	defer strings.builder_destroy(&compact_builder)
	context_text := `{"direction":"@direction"}`
	testing.expect_value(t, compact(&compact_builder, []rdf.Quad{quad}, context_text, Compact_Options{serializer_options = options}), Compact_Error.None)
	testing.expect(t, strings.contains(strings.to_string(compact_builder), `"direction": "rtl"`))
}

@(test)
test_round_trips_compound_direction_literals_when_enabled :: proc(t: ^testing.T) {
	compound := rdf.blank_node("compound", 1)
	quads := []rdf.Quad{
		rdf.default_graph_quad(rdf.Triple{subject = rdf.iri("https://example.test/s"), predicate = rdf.iri("https://example.test/label"), object = compound}),
		rdf.default_graph_quad(rdf.Triple{subject = compound, predicate = rdf.iri(RDF_VALUE), object = rdf.literal("Hello")}),
		rdf.default_graph_quad(rdf.Triple{subject = compound, predicate = rdf.iri(RDF_LANGUAGE), object = rdf.literal("en-us")}),
		rdf.default_graph_quad(rdf.Triple{subject = compound, predicate = rdf.iri(RDF_DIRECTION), object = rdf.literal("rtl")}),
	}
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	options := Serialize_Options{rdf_direction = .Compound_Literal}
	testing.expect_value(t, serialize(&builder, quads, options), Serialize_Error.None)
	serialized := strings.to_string(builder)
	testing.expect(t, strings.contains(serialized, `"@language": "en-us", "@direction": "rtl"`))
	testing.expect(t, !strings.contains(serialized, RDF_VALUE))
	round_trip, parse_error := parse_to_nquads(serialized, Options{rdf_direction = .Compound_Literal})
	defer delete(round_trip)
	testing.expect_value(t, parse_error.code, Error_Code.None)
	testing.expect(t, strings.contains(round_trip, `<http://www.w3.org/1999/02/22-rdf-syntax-ns#direction> "rtl"`))

	compact_builder := strings.builder_make()
	defer strings.builder_destroy(&compact_builder)
	context_text := `{"direction":"@direction"}`
	testing.expect_value(t, compact(&compact_builder, quads, context_text, Compact_Options{serializer_options = options}), Compact_Error.None)
	testing.expect(t, strings.contains(strings.to_string(compact_builder), `"direction": "rtl"`))

	invalid_quads := []rdf.Quad{
		quads[0], quads[1], quads[2], quads[3],
		rdf.default_graph_quad(rdf.Triple{subject = compound, predicate = rdf.iri(RDF_TYPE), object = rdf.iri("https://example.test/other")}),
	}
	strings.builder_reset(&builder)
	testing.expect_value(t, serialize(&builder, invalid_quads, options), Serialize_Error.None)
	testing.expect(t, strings.contains(strings.to_string(builder), RDF_VALUE))
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
test_compaction_uses_an_imported_context :: proc(t: ^testing.T) {
	quads := []rdf.Quad{rdf.default_graph_quad(rdf.Triple{
		subject = rdf.iri("https://example.test/resource"),
		predicate = rdf.iri("https://example.test/imported-term"),
		object = rdf.literal("value"),
	})}
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	options := Compact_Options{context_options = {base_iri = "https://example.test/document/input.jsonld", document_loader = imported_context}}
	testing.expect_value(t, compact(&builder, quads, `{"@import":"imported.jsonld"}`, options), Compact_Error.None)
	testing.expect(t, strings.contains(strings.to_string(builder), `"term": "value"`))
}

@(test)
test_compaction_relativizes_document_identifiers_against_base :: proc(t: ^testing.T) {
	base := "https://w3c.github.io/json-ld-api/tests/compact/0045-in.jsonld"
	quads := []rdf.Quad{
		rdf.default_graph_quad(rdf.Triple{
			subject = rdf.iri("https://w3c.github.io/json-ld-api/tests/compact/term"),
			predicate = rdf.iri("http://example.com/property"),
			object = rdf.iri("https://w3c.github.io/json-ld-api/tests/parent-node"),
		}),
	}
	context_text := `{"@context":{"term":"http://example.com/terms-are-not-considered-in-id","property":{"@id":"http://example.com/property","@type":"@id"},"@vocab":"http://example.org/vocab-is-not-considered-for-id"}}`
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	options := Compact_Options{context_options = {base_iri = base}}
	testing.expect_value(t, compact(&builder, quads, context_text, options), Compact_Error.None)
	output := strings.to_string(builder)
	testing.expect(t, strings.contains(output, `"@id": "term"`))
	testing.expect(t, strings.contains(output, `"property": "../parent-node"`))
	round_trip, parse_error := parse_to_nquads(output, Options{base_iri = base})
	defer delete(round_trip)
	testing.expect_value(t, parse_error.code, Error_Code.None)
	testing.expect(t, strings.contains(round_trip, `<https://w3c.github.io/json-ld-api/tests/compact/term> <http://example.com/property> <https://w3c.github.io/json-ld-api/tests/parent-node> .`))
}

@(test)
test_compaction_relativizes_keyword_like_path_segments :: proc(t: ^testing.T) {
	quads := []rdf.Quad{
		rdf.default_graph_quad(rdf.Triple{
			subject = rdf.blank_node("root"),
			predicate = rdf.iri("http://example.org/address"),
			object = rdf.iri("http://localhost/@special"),
		}),
	}
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	options := Compact_Options{context_options = {base_iri = "http://localhost/"}}
	testing.expect_value(t, compact(&builder, quads, `{"@context":{"ex":"http://example.org/","@base":"http://localhost/","address":{"@id":"ex:address","@type":"@id"}}}`, options), Compact_Error.None)
	output := strings.to_string(builder)
	testing.expect(t, strings.contains(output, `"address": "./@special"`))
	round_trip, parse_error := parse_to_nquads(output, Options{base_iri = "http://localhost/"})
	defer delete(round_trip)
	testing.expect_value(t, parse_error.code, Error_Code.None)
	testing.expect(t, strings.contains(round_trip, `<http://example.org/address> <http://localhost/@special> .`))
}

@(test)
test_language_and_index_containers_preserve_rdf_semantics :: proc(t: ^testing.T) {
	context_text := `{"@context":{"label":{"@id":"https://example.test/label","@container":"@language"},"person":{"@id":"https://example.test/person","@container":"@index","@index":"https://example.test/name"}}}`
	input := `{
  "@context": {"label":{"@id":"https://example.test/label","@container":"@language"},"person":{"@id":"https://example.test/person","@container":"@index","@index":"https://example.test/name"}},
  "@id":"https://example.test/article",
  "label":{"en":"Hello","de":["Hallo","Guten Tag"]},
  "person":{"alice":{"@id":"https://example.test/alice"},"discarded":null,"alsoDiscarded":{"@value":null}}
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

@(test)
test_expands_document_without_losing_set_or_context_semantics :: proc(t: ^testing.T) {
	input := `{
  "@context": {
    "ex": "https://example.test/",
    "name": "ex:name",
    "homepage": {"@id": "ex:homepage", "@type": "@id"},
    "items": {"@id": "ex:items", "@container": "@list"}
  },
  "@id": "ex:alice",
  "name": {"@set": ["Alice", "A."]},
  "homepage": "https://example.test/alice",
  "items": ["one", 2]
}`
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	testing.expect_value(t, expand(&builder, input, Expand_Options{context_options = {base_iri = "https://example.test/document"}}), Expand_Error.None)
	expected := `[{"@id": "https://example.test/alice", "https://example.test/homepage": [{"@id": "https://example.test/alice"}], "https://example.test/items": [{"@list": [{"@value": "one"}, {"@value": 2}]}], "https://example.test/name": [{"@value": "Alice"}, {"@value": "A."}]}]
`
	testing.expect_value(t, strings.to_string(builder), expected)
}

@(test)
test_expansion_is_atomic_and_bounded :: proc(t: ^testing.T) {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	strings.write_string(&builder, "previous\n")
	input := `{"@context":{"name":"https://example.test/name"},"name":"Alice"}`
	testing.expect_value(t, expand(&builder, input, Expand_Options{max_output_bytes = 4}), Expand_Error.Output_Too_Large)
	testing.expect_value(t, strings.to_string(builder), "previous\n")
	testing.expect_value(t, expand(&builder, `{`), Expand_Error.Invalid_JSON)
	testing.expect_value(t, strings.to_string(builder), "previous\n")
}

@(test)
test_null_term_definitions_suppress_rdf_and_document_properties :: proc(t: ^testing.T) {
	input := `{
  "@context": {"@vocab":"https://example.test/", "ignored":null, "alsoIgnored":{"@id":null}},
  "@id":"https://example.test/s",
  "name":"Alice",
  "ignored":"no",
  "alsoIgnored":"no"
}`
	quads, parse_err := parse_to_nquads(input)
	defer delete(quads)
	testing.expect_value(t, parse_err.code, Error_Code.None)
	testing.expect(t, strings.contains(quads, `<https://example.test/s> <https://example.test/name> "Alice" .`))
	testing.expect(t, !strings.contains(quads, "ignored"))
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	testing.expect_value(t, expand(&builder, input), Expand_Error.None)
	testing.expect(t, !strings.contains(strings.to_string(builder), "ignored"))
}

@(test)
test_null_local_context_resets_to_rdf_term_mappings :: proc(t: ^testing.T) {
	actual, err := parse_to_nquads(`{
  "@context": {
    "child": "https://example.test/child",
    "discarded": "https://example.test/discarded"
  },
  "@id": "https://example.test/root",
  "child": {
    "@context": null,
    "@id": "https://example.test/child-node",
    "discarded": "not emitted",
    "https://example.test/retained": "yes"
  }
}`)
	defer delete(actual)
	testing.expect_value(t, err.code, Error_Code.None)
	testing.expect(t, strings.contains(actual, `<https://example.test/root> <https://example.test/child> <https://example.test/child-node> .`))
	testing.expect(t, strings.contains(actual, `<https://example.test/child-node> <https://example.test/retained> "yes" .`))
	testing.expect(t, !strings.contains(actual, "discarded"))
}

@(test)
test_blank_node_types_remain_blank_nodes_in_rdf :: proc(t: ^testing.T) {
	actual, err := parse_to_nquads(`{"@id":"_:kind","@type":"_:kind"}`)
	defer delete(actual)
	testing.expect_value(t, err.code, Error_Code.None)
	testing.expect(t, strings.contains(actual, `_:b0 <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> _:b0 .`))
}

@(test)
test_boolean_values_honor_term_datatype_coercion :: proc(t: ^testing.T) {
	actual, err := parse_to_nquads(`{
  "@context":{"flag":{"@id":"https://example.test/flag","@type":"https://example.test/boolean"}},
  "flag":true
}`)
	defer delete(actual)
	testing.expect_value(t, err.code, Error_Code.None)
	testing.expect(t, strings.contains(actual, `<https://example.test/flag> "true"^^<https://example.test/boolean> .`))
}

@(test)
test_object_term_definitions_expand_same_context_compact_iris :: proc(t: ^testing.T) {
	actual, err := parse_to_nquads(`{
  "@context": {
    "issue":{"@id":"https://example.test/issue/","@type":"@id"},
    "issue:raisedBy":{"@container":"@set"}
  },
  "issue":"https://example.test/one",
  "issue:raisedBy":"Ada"
}`)
	defer delete(actual)
	testing.expect_value(t, err.code, Error_Code.None)
	testing.expect(t, strings.contains(actual, `<https://example.test/issue/raisedBy> "Ada" .`))
}

@(test)
test_reverse_maps_ignore_unmapped_relative_keys :: proc(t: ^testing.T) {
	actual, err := parse_to_nquads(`{
  "@context":{"knows":"https://example.test/knows"},
  "@id":"https://example.test/alice",
  "@reverse": {
    "knows":{"@id":"https://example.test/bob"},
    "ignored":{"@id":"https://example.test/carol"}
  }
}`)
	defer delete(actual)
	testing.expect_value(t, err.code, Error_Code.None)
	testing.expect(t, strings.contains(actual, `<https://example.test/bob> <https://example.test/knows> <https://example.test/alice> .`))
	testing.expect(t, !strings.contains(actual, "carol"))
}

@(test)
test_later_contexts_redefine_terms_against_their_current_vocab :: proc(t: ^testing.T) {
	actual, err := parse_to_nquads(`{
  "@context": [
    {"v":"https://example.test/first/","term":"v:old"},
    {"@vocab":"https://example.test/second/","term":"term"}
  ],
  "term":"value"
}`)
	defer delete(actual)
	testing.expect_value(t, err.code, Error_Code.None)
	testing.expect(t, strings.contains(actual, `<https://example.test/second/term> "value" .`))
	testing.expect(t, !strings.contains(actual, "first/old"))
}

@(test)
test_free_floating_graph_values_and_lists_do_not_emit_rdf_cells :: proc(t: ^testing.T) {
	actual, err := parse_to_nquads(`{
  "@context":{"name":"https://example.test/name"},
  "@graph":[
    "unanchored value",
    {"@list":["unanchored list value", {"@id":"https://example.test/dropped","name":"dropped"}]},
    {"@id":"https://example.test/kept","name":"kept"}
  ]
}`)
	defer delete(actual)
	testing.expect_value(t, err.code, Error_Code.None)
	testing.expect(t, strings.contains(actual, `<https://example.test/kept> <https://example.test/name> "kept" .`))
	testing.expect(t, !strings.contains(actual, "dropped"))
	testing.expect(t, !strings.contains(actual, RDF_FIRST))
}

@(test)
test_id_coercion_uses_document_relative_iris_not_term_mappings :: proc(t: ^testing.T) {
	actual, err := parse_to_nquads(`{
  "@context": {
    "mapped":"https://example.test/not-an-id-target",
    "link":{"@id":"https://example.test/link","@type":"@id"}
  },
  "@id":"https://example.test/root",
  "link":"mapped"
}`, Options{base_iri = "https://example.test/base/document"})
	defer delete(actual)
	testing.expect_value(t, err.code, Error_Code.None)
	testing.expect(t, strings.contains(actual, `<https://example.test/root> <https://example.test/link> <https://example.test/base/mapped> .`))
	testing.expect(t, !strings.contains(actual, "not-an-id-target"))
}

@(test)
test_type_aliases_all_emit_rdf_types :: proc(t: ^testing.T) {
	actual, err := parse_to_nquads(`{
  "@context":{"@vocab":"https://example.test/","kind":"@type","alsoKind":"@type"},
  "kind":"First",
  "alsoKind":"Second"
}`)
	defer delete(actual)
	testing.expect_value(t, err.code, Error_Code.None)
	testing.expect(t, strings.contains(actual, `<http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <https://example.test/First> .`))
	testing.expect(t, strings.contains(actual, `<http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <https://example.test/Second> .`))
}

@(test)
test_graph_containers_link_named_graphs_to_the_parent_node :: proc(t: ^testing.T) {
	actual, err := parse_to_nquads(`{
  "@context":{"input":{"@id":"https://example.test/input","@container":"@graph"},"value":"https://example.test/value"},
  "input":{"value":"x"}
}`)
	defer delete(actual)
	testing.expect_value(t, err.code, Error_Code.None)
	testing.expect(t, strings.contains(actual, `<https://example.test/input> _:b1 .`))
	testing.expect(t, strings.contains(actual, `<https://example.test/value> "x" _:b1 .`))
}

@(test)
test_index_graph_containers_discard_index_annotations :: proc(t: ^testing.T) {
	actual, err := parse_to_nquads(`{
  "@context":{"@vocab":"https://example.test/","input":{"@container":["@graph","@index"]}},
  "input":{"first":{"value":"x"}}
}`)
	defer delete(actual)
	testing.expect_value(t, err.code, Error_Code.None)
	testing.expect(t, strings.contains(actual, `<https://example.test/input> _:b1 .`))
	testing.expect(t, strings.contains(actual, `<https://example.test/value> "x" _:b1 .`))
	testing.expect(t, !strings.contains(actual, "first"))
}

@(test)
test_id_graph_containers_use_map_keys_as_graph_names :: proc(t: ^testing.T) {
	actual, err := parse_to_nquads(`{
  "@context":{"@vocab":"https://example.test/","input":{"@container":["@graph","@id"]}},
  "input":{"https://graphs.example/one":{"value":"x"}}
}`)
	defer delete(actual)
	testing.expect_value(t, err.code, Error_Code.None)
	testing.expect(t, strings.contains(actual, `<https://example.test/input> <https://graphs.example/one> .`))
	testing.expect(t, strings.contains(actual, `<https://example.test/value> "x" <https://graphs.example/one> .`))
}

@(test)
test_base_null_drops_nodes_with_relative_identifiers :: proc(t: ^testing.T) {
	actual, err := parse_to_nquads(`{
  "@context":{"child":"https://example.test/child","name":"https://example.test/name"},
  "child":{"@context":{"@base":null},"@id":"relative","name":"dropped"}
}`, Options{base_iri = "https://example.test/document"})
	defer delete(actual)
	testing.expect_value(t, err.code, Error_Code.None)
	testing.expect_value(t, actual, "")
}

@(test)
test_id_coercion_resolves_fragment_colons_against_base :: proc(t: ^testing.T) {
	actual, err := parse_to_nquads(`{
  "@context":{"@base":"https://example.test/","item":{"@id":"urn:item:","@type":"@id"}},
  "item":"#part:two"
}`)
	defer delete(actual)
	testing.expect_value(t, err.code, Error_Code.None)
	testing.expect(t, strings.contains(actual, `<urn:item:> <https://example.test/#part:two> .`))
}

@(test)
test_empty_prefix_compact_iris_use_the_vocabulary_mapping :: proc(t: ^testing.T) {
	actual, err := parse_to_nquads(`{
  "@context":{"@vocab":"https://example.test/vocab"},
  ":term":"value"
}`)
	defer delete(actual)
	testing.expect_value(t, err.code, Error_Code.None)
	testing.expect(t, strings.contains(actual, `<https://example.test/vocab:term> "value" .`))
}

@(test)
test_keyword_form_terms_and_iris_are_ignored :: proc(t: ^testing.T) {
	actual, err := parse_to_nquads(`{
  "@context":{"@vocab":"https://example.test/vocab/","@":"https://example.test/vocab/at","@foo.bar":"https://example.test/vocab/foo.bar","ignored":{"@id":"@ignoreMe"}},
  "@":"allowed",
  "@foo.bar":"allowed",
  "ignored":"uses the term name"
}`)
	defer delete(actual)
	testing.expect_value(t, err.code, Error_Code.None)
	testing.expect(t, strings.contains(actual, `<https://example.test/vocab/at> "allowed" .`))
	testing.expect(t, strings.contains(actual, `<https://example.test/vocab/foo.bar> "allowed" .`))
	testing.expect(t, strings.contains(actual, `<https://example.test/vocab/ignored> "uses the term name" .`))
	testing.expect(t, !strings.contains(actual, "@ignoreMe"))
}

@(test)
test_value_objects_reject_invalid_datatype_iris :: proc(t: ^testing.T) {
	actual, err := parse_to_nquads(`{
  "@id":"https://example.test/node",
  "https://example.test/value":{"@value":"x","@type":"https://example.test/type invalid"}
}`)
	defer delete(actual)
	testing.expect_value(t, err.code, Error_Code.Invalid_Value_Object)
}

@(test)
test_type_containers_inject_map_keys_as_node_types :: proc(t: ^testing.T) {
	actual, err := parse_to_nquads(`{
  "@context":{"@vocab":"https://example.test/","items":{"@container":"@type"}},
  "items":{"Person":{"name":"Ada"},"@none":{"name":"Anonymous"}}
}`)
	defer delete(actual)
	testing.expect_value(t, err.code, Error_Code.None)
	testing.expect(t, strings.contains(actual, `<https://example.test/name> "Ada" .`))
	testing.expect(t, strings.contains(actual, `<http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <https://example.test/Person> .`))
	testing.expect(t, strings.contains(actual, `<https://example.test/name> "Anonymous" .`))
	testing.expect(t, strings.count(actual, `<http://www.w3.org/1999/02/22-rdf-syntax-ns#type>`) == 1)
}

@(test)
test_id_containers_use_map_keys_when_values_lack_ids :: proc(t: ^testing.T) {
	actual, err := parse_to_nquads(`{
  "@context":{"@vocab":"https://example.test/","items":{"@container":"@id"}},
  "items":{"https://example.test/ada":{"name":"Ada"},"https://example.test/grace":{"@id":"https://example.test/override","name":"Grace"}}
}`)
	defer delete(actual)
	testing.expect_value(t, err.code, Error_Code.None)
	testing.expect(t, strings.contains(actual, `<https://example.test/ada> <https://example.test/name> "Ada" .`))
	testing.expect(t, strings.contains(actual, `<https://example.test/override> <https://example.test/name> "Grace" .`))
	testing.expect(t, strings.contains(actual, `<https://example.test/items> <https://example.test/ada> .`))
	testing.expect(t, strings.contains(actual, `<https://example.test/items> <https://example.test/override> .`))
}

@(test)
test_graph_containers_keep_referenced_graph_node_names_and_none_keys :: proc(t: ^testing.T) {
	actual, err := parse_to_nquads(`[
  {"@context":{"@vocab":"https://example.test/","input":{"@container":["@graph","@id"]}},"input":{"@none":{"value":"map"}}},
  {"@context":{"@vocab":"https://example.test/","input":{"@container":["@graph","@id"]}},"@id":"_:graph","@graph":[{"value":"reference"}]},
  {"@context":{"@vocab":"https://example.test/","input":{"@container":["@graph","@id"]}},"input":{"@id":"_:graph"}}
]`)
	defer delete(actual)
	testing.expect_value(t, err.code, Error_Code.None)
	testing.expect(t, strings.contains(actual, `<https://example.test/value> "map"`))
	testing.expect(t, strings.contains(actual, `<https://example.test/value> "reference"`))
	testing.expect_value(t, strings.count(actual, `<https://example.test/input>`), 2)
}

@(test)
test_flattens_embedded_and_reverse_nodes_atomically :: proc(t: ^testing.T) {
	input := `{
  "@context": {"knows":"https://example.test/knows", "name":"https://example.test/name"},
  "@id":"https://example.test/alice",
  "name":"Alice",
  "knows":{"@id":"https://example.test/bob", "name":"Bob"},
  "@reverse":{"knows":{"@id":"https://example.test/carol", "name":"Carol"}}
}`
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	strings.write_string(&builder, "previous\n")
	testing.expect_value(t, flatten(&builder, input, Flatten_Options{max_output_bytes = 4}), Flatten_Error.Output_Too_Large)
	testing.expect_value(t, strings.to_string(builder), "previous\n")
	testing.expect_value(t, flatten(&builder, input), Flatten_Error.None)
	expected := `[{"@id": "https://example.test/alice", "https://example.test/knows": [{"@id": "https://example.test/bob"}], "https://example.test/name": [{"@value": "Alice"}]}, {"@id": "https://example.test/bob", "https://example.test/name": [{"@value": "Bob"}]}, {"@id": "https://example.test/carol", "https://example.test/knows": [{"@id": "https://example.test/alice"}], "https://example.test/name": [{"@value": "Carol"}]}]
`
	testing.expect_value(t, strings.to_string(builder)[len("previous\n"):], expected)
}

@(test)
test_flattening_bounds_node_map_and_handles_cycles :: proc(t: ^testing.T) {
	input := `{"@context":{"p":"https://example.test/p"},"@id":"https://example.test/a","p":{"@id":"https://example.test/a"}}`
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	strings.write_string(&builder, "previous\n")
	testing.expect_value(t, flatten(&builder, input, Flatten_Options{max_nodes = 0, max_output_bytes = 4}), Flatten_Error.Output_Too_Large)
	testing.expect_value(t, strings.to_string(builder), "previous\n")
	testing.expect_value(t, flatten(&builder, input), Flatten_Error.None)
	testing.expect(t, strings.contains(strings.to_string(builder), `"https://example.test/p": [{"@id": "https://example.test/a"}]`))
	strings.builder_reset(&builder)
	testing.expect_value(t, flatten(&builder, `[{"@id":"https://example.test/a","https://example.test/p":"a"},{"@id":"https://example.test/b","https://example.test/p":"b"}]`, Flatten_Options{max_nodes = 1}), Flatten_Error.Node_Limit)
	testing.expect_value(t, strings.to_string(builder), "")
}

@(test)
test_expansion_and_flattening_support_transparent_nesting :: proc(t: ^testing.T) {
	input := `{
  "@context":{"@vocab":"https://example.test/", "nest":"@nest"},
  "name":"top",
  "nest":[{"name":"nested"}, {"@type":"Thing", "label":"inside"}]
}`
	expanded := strings.builder_make()
	defer strings.builder_destroy(&expanded)
	testing.expect_value(t, expand(&expanded, input), Expand_Error.None)
	expected_expanded := `[{"@type": ["https://example.test/Thing"], "https://example.test/label": [{"@value": "inside"}], "https://example.test/name": [{"@value": "top"}, {"@value": "nested"}]}]
`
	testing.expect_value(t, strings.to_string(expanded), expected_expanded)
	flattened := strings.builder_make()
	defer strings.builder_destroy(&flattened)
	testing.expect_value(t, flatten(&flattened, input), Flatten_Error.None)
	expected_flattened := `[{"@id": "_:b0", "@type": ["https://example.test/Thing"], "https://example.test/label": [{"@value": "inside"}], "https://example.test/name": [{"@value": "top"}, {"@value": "nested"}]}]
`
	testing.expect_value(t, strings.to_string(flattened), expected_flattened)
	invalid := `{"@context":{"@vocab":"https://example.test/"},"@nest":"no"}`
	testing.expect_value(t, expand(&expanded, invalid), Expand_Error.Invalid_Value_Object)
}

@(test)
test_frame_matching_filters_expanded_node_map :: proc(t: ^testing.T) {
	node_value, node_error := json.parse_string(`{"@id":"https://example.test/library","@type":["https://example.test/Library"],"https://example.test/contains":[{"@id":"https://example.test/book"}]}`, .JSON, true)
	defer json.destroy_value(node_value)
	testing.expect_value(t, node_error, json.Error.None)
	node, node_valid := object_from_value(node_value)
	testing.expect(t, node_valid)
	frame_value, frame_error := json.parse_string(`{"@type":["https://example.test/Library"],"https://example.test/contains":{}}`, .JSON, true)
	defer json.destroy_value(frame_value)
	testing.expect_value(t, frame_error, json.Error.None)
	frame, frame_valid := object_from_value(frame_value)
	testing.expect(t, frame_valid)
	testing.expect(t, frame_matches_node(node, frame))
	wrong_value, wrong_error := json.parse_string(`{"@id":["https://example.test/book"]}`, .JSON, true)
	defer json.destroy_value(wrong_value)
	testing.expect_value(t, wrong_error, json.Error.None)
	wrong, wrong_valid := object_from_value(wrong_value)
	testing.expect(t, wrong_valid)
	testing.expect(t, !frame_matches_node(node, wrong))
}

@(test)
test_frame_accepts_explicit_control :: proc(t: ^testing.T) {
	value, err := json.parse_string(`{"@context":{"ex":"https://example.test/"},"@explicit":true,"ex:p":{"@explicit":true}}`, .JSON, true)
	defer json.destroy_value(value)
	testing.expect_value(t, err, json.Error.None)
	testing.expect(t, !frame_has_unsupported_policy(value))
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	testing.expect_value(t, expand_frame(&builder, `{"@context":{"ex":"https://example.test/"},"@explicit":true,"@type":"ex:T","ex:p":{"@explicit":true}}`), Expand_Error.None)
	testing.expect(t, strings.contains(strings.to_string(builder), `"@explicit": true`))
	strings.builder_reset(&builder)
	testing.expect_value(t, frame(&builder, `{"@context":{"ex":"https://example.test/"},"@id":"ex:a","@type":"ex:T","ex:p":"value"}`, `{"@context":{"ex":"https://example.test/"},"@explicit":true,"@type":"ex:T"}`), Frame_Error.None)
	testing.expect(t, !strings.contains(strings.to_string(builder), `"ex:p"`))
}

@(test)
test_frame_embeds_library_children_and_preserves_context :: proc(t: ^testing.T) {
	input := `{
  "@context": {"dcterms":"http://purl.org/dc/terms/", "ex":"http://example.org/vocab#", "ex:contains":{"@type":"@id"}},
  "@graph": [
    {"@id":"http://example.org/test/#library", "@type":"ex:Library", "ex:contains":"http://example.org/test#book"},
    {"@id":"http://example.org/test#book", "@type":"ex:Book", "dcterms:title":"My Book", "ex:contains":"http://example.org/test#chapter"},
    {"@id":"http://example.org/test#chapter", "@type":"ex:Chapter", "dcterms:title":"Chapter One"}
  ]
}`
	frame_document := `{
  "@context": {"dcterms":"http://purl.org/dc/terms/", "ex":"http://example.org/vocab#"},
  "@type":"ex:Library",
  "ex:contains":{"@type":"ex:Book", "ex:contains":{"@type":"ex:Chapter"}}
}`
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	strings.write_string(&builder, "previous\n")
	testing.expect_value(t, frame(&builder, input, frame_document, Frame_Options{processing_mode = .Json_LD_1_0}), Frame_Error.None)
	actual := strings.to_string(builder)[len("previous\n"):]
	testing.expect(t, strings.contains(actual, `"@graph": [`))
	testing.expect(t, strings.contains(actual, `"@type": "ex:Library"`))
	testing.expect(t, strings.contains(actual, `"@type": "ex:Book"`))
	testing.expect(t, strings.contains(actual, `"@type": "ex:Chapter"`))
	testing.expect(t, strings.contains(actual, `"Chapter One"`))
	strings.builder_reset(&builder)
	testing.expect_value(t, frame(&builder, input, `{"@context":{"ex":"http://example.org/vocab#"},"@type":"ex:Missing"}`), Frame_Error.None)
	testing.expect(t, strings.contains(strings.to_string(builder), `"@graph": []`))
	strings.builder_reset(&builder)
	testing.expect_value(t, frame(&builder, input, frame_document, Frame_Options{max_embedding_depth = 1}), Frame_Error.Embedding_Limit)
	testing.expect_value(t, strings.to_string(builder), "")
	testing.expect_value(t, frame(&builder, input, `{"@context":{"ex":"http://example.org/vocab#"},"@type":"ex:Library","@embed":"@never"}`), Frame_Error.None)
	testing.expect(t, strings.contains(strings.to_string(builder), `"@type": "ex:Library"`))
}

@(test)
test_term_scoped_context_is_retained_and_applied :: proc(t: ^testing.T) {
	parsed, json_error := json.parse_string(`{"p1":{"@context":{"@protected":true,"p2":{"@id":"ex:p2","@type":"@id"}},"@id":"ex:p1"}}`, .JSON, true)
	defer json.destroy_value(parsed)
	testing.expect_value(t, json_error, json.Error.None)
	state := State{remote_urls = make(map[string]bool), named_bnodes = make(map[string]rdf.Term), max_contexts = DEFAULT_MAX_CONTEXTS, max_remote = DEFAULT_MAX_REMOTE_CONTEXTS, allow_document_containers = true}
	defer destroy_state(&state)
	ctx, make_error := make_context(&state, nil)
	testing.expect_value(t, make_error.code, Error_Code.None)
	context_error: Parse_Error
	ctx, context_error = apply_context(&state, &ctx, parsed)
	testing.expect_value(t, context_error.code, Error_Code.None)
	definition := ctx.terms["p1"]
	testing.expect(t, definition.has_local_context)
	scoped, scoped_error := apply_term_scoped_context(&state, &ctx, definition)
	testing.expect_value(t, scoped_error.code, Error_Code.None)
	_, has_p2 := scoped.terms["p2"]
	testing.expect(t, has_p2)
	value, value_error := json.parse_string(`{"@id":"ex:1","@type":"T","p2":"ex:test"}`, .JSON, true)
	defer json.destroy_value(value)
	testing.expect_value(t, value_error, json.Error.None)
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	written, expand_error := expand_write_single(&builder, &state, &ctx, definition, value, true)
	testing.expect(t, written)
	testing.expect_value(t, expand_error, Expand_Error.None)
	testing.expect(t, strings.contains(strings.to_string(builder), `"ex:p2"`))
	full_input := `{"@context":{"T":{"@id":"ex:T","@context":{}},"p1":{"@id":"ex:p1","@context":{"@protected":true,"p2":{"@id":"ex:p2","@type":"@id"}}}},"p1":{"@id":"ex:1","@type":"T","p2":"ex:test"}}`
	full_builder := strings.builder_make()
	defer strings.builder_destroy(&full_builder)
	testing.expect_value(t, expand_document(&full_builder, full_input, Expand_Options{}, false, false), Expand_Error.None)
	testing.expect(t, strings.contains(strings.to_string(full_builder), `"ex:p2"`))
	compact_context, compact_context_error := json.parse_string(`{"@version":1.1,"@vocab":"http://example.org/vocab#","Production":{"@context":{"part":{"@container":"@set","@type":"@id"}}}}`, .JSON, true)
	defer json.destroy_value(compact_context)
	testing.expect_value(t, compact_context_error, json.Error.None)
	compact_state := State{remote_urls = make(map[string]bool), named_bnodes = make(map[string]rdf.Term), max_contexts = DEFAULT_MAX_CONTEXTS, max_remote = DEFAULT_MAX_REMOTE_CONTEXTS, allow_document_containers = true}
	defer destroy_state(&compact_state)
	compact_ctx, compact_make_error := make_context(&compact_state, nil)
	testing.expect_value(t, compact_make_error.code, Error_Code.None)
	compact_apply_error: Parse_Error
	compact_ctx, compact_apply_error = apply_context(&compact_state, &compact_ctx, compact_context)
	testing.expect_value(t, compact_apply_error.code, Error_Code.None)
	node_value, node_error := json.parse_string(`{"@type":["http://example.org/vocab#Production"]}`, .JSON, true)
	defer json.destroy_value(node_value)
	node, node_valid := object_from_value(node_value)
	testing.expect_value(t, node_error, json.Error.None)
	testing.expect(t, node_valid)
	scoped_compact, scoped_compact_error := frame_context_for_node(&compact_state, &compact_ctx, node)
	testing.expect_value(t, scoped_compact_error, Compact_Error.None)
	part_definition, has_part := scoped_compact.terms["part"]
	testing.expect(t, has_part && part_definition.container_set)
	compact_node_value, compact_node_error := json.parse_string(`{"@id":"_:b0","@type":["http://example.org/vocab#Production"],"http://example.org/vocab#part":[{"@id":"_:b1","@type":["http://example.org/vocab#Production"]}]}`, .JSON, true)
	defer json.destroy_value(compact_node_value)
	compact_node, compact_node_valid := object_from_value(compact_node_value)
	testing.expect_value(t, compact_node_error, json.Error.None)
	testing.expect(t, compact_node_valid)
	compact_builder := strings.builder_make()
	defer strings.builder_destroy(&compact_builder)
	testing.expect_value(t, frame_compact_write_node(&compact_builder, &compact_state, &compact_ctx, compact_node, .Compact), Compact_Error.None)
	testing.expect(t, strings.contains(strings.to_string(compact_builder), `"part": [`))
	frame_builder := strings.builder_make()
	defer strings.builder_destroy(&frame_builder)
	frame_input := `{"@context":{"@version":1.1,"@vocab":"http://example.org/vocab#"},"@id":"http://example.org/1","@type":"HumanMadeObject","produced_by":{"@type":"Production","_label":"Top Production","part":{"@type":"Production","_label":"Test Part"}}}`
	frame_document := `{"@context":{"@version":1.1,"@vocab":"http://example.org/vocab#","Production":{"@context":{"part":{"@container":"@set","@type":"@id"}}}},"@id":"http://example.org/1"}`
	testing.expect_value(t, frame(&frame_builder, frame_input, frame_document, Frame_Options{context_options = {base_iri = "https://w3c.github.io/json-ld-framing/tests/frame/0062-in.jsonld"}}), Frame_Error.None)
	testing.expect(t, strings.contains(strings.to_string(frame_builder), `"part": [`))
}
