// Package jsonld transforms JSON-LD 1.1 documents into RDF datasets.
//
// JSON-LD processing necessarily retains a bounded JSON document and ctx
// state. It is therefore deliberately separate from the line-streaming RDF
// syntaxes in this repository.
package jsonld

import json "core:encoding/json"
import "core:sort"
import "core:strings"
import "core:unicode/utf8"
import rdf ".."
import turtle "../turtle"

RDF_TYPE  :: "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
RDF_FIRST :: "http://www.w3.org/1999/02/22-rdf-syntax-ns#first"
RDF_REST  :: "http://www.w3.org/1999/02/22-rdf-syntax-ns#rest"
RDF_NIL   :: "http://www.w3.org/1999/02/22-rdf-syntax-ns#nil"
RDF_LIST  :: "http://www.w3.org/1999/02/22-rdf-syntax-ns#List"
RDF_JSON  :: "http://www.w3.org/1999/02/22-rdf-syntax-ns#JSON"
RDF_VALUE :: "http://www.w3.org/1999/02/22-rdf-syntax-ns#value"
RDF_DIRECTION :: "http://www.w3.org/1999/02/22-rdf-syntax-ns#direction"
RDF_LANGUAGE  :: "http://www.w3.org/1999/02/22-rdf-syntax-ns#language"
I18N      :: "https://www.w3.org/ns/i18n#"
XSD_BOOLEAN :: "http://www.w3.org/2001/XMLSchema#boolean"
XSD_INTEGER :: "http://www.w3.org/2001/XMLSchema#integer"
XSD_DOUBLE  :: "http://www.w3.org/2001/XMLSchema#double"

// Error_Code identifies JSON syntax, JSON-LD processing, resource-limit, and
// sink outcomes. JSON-LD errors are intentionally stable API diagnostics;
// callers should not depend on the implementation details of core:encoding/json.
Error_Code :: enum {
	None,
	Missing_Sink,
	Invalid_UTF8,
	Invalid_JSON,
	Invalid_Option,
	Invalid_Chunk_Size,
	Reader_Error,
	No_Progress,
	Document_Too_Large,
	Nesting_Limit,
	Context_Limit,
	Remote_Context_Limit,
	Remote_Context_Disallowed,
	Loading_Document_Failed,
	Invalid_Context,
	Invalid_Term_Definition,
	Protected_Term_Redefinition,
	Invalid_IRI,
	Invalid_Value_Object,
	Invalid_List_Object,
	Invalid_Reverse_Property,
	Invalid_Graph,
	Unsupported_Feature,
	Quad_Limit,
	Stopped,
	Out_Of_Memory,
}

// Parse_Error reports a processing outcome. JSON-LD ctx and expansion
// failures do not always have a useful character offset after remote contexts
// and aliases are resolved, so line and column are zero for those failures.
Parse_Error :: struct {
	code:   Error_Code,
	line:   int,
	column: int,
}

// parse_error_message returns a stable, allocation-free description.
parse_error_message :: proc(code: Error_Code) -> string {
	switch code {
	case .None:                       return "no error"
	case .Missing_Sink:               return "sink is required"
	case .Invalid_UTF8:               return "invalid UTF-8"
	case .Invalid_JSON:               return "invalid JSON"
	case .Invalid_Option:             return "parser limits must not be negative"
	case .Invalid_Chunk_Size:         return "chunk size must not be negative"
	case .Reader_Error:               return "reader error"
	case .No_Progress:                return "reader made no progress"
	case .Document_Too_Large:         return "JSON-LD document exceeds configured byte limit"
	case .Nesting_Limit:              return "JSON nesting depth limit reached"
	case .Context_Limit:              return "context limit reached"
	case .Remote_Context_Limit:       return "remote context limit reached"
	case .Remote_Context_Disallowed:  return "remote context requires a document loader"
	case .Loading_Document_Failed:    return "failed to load remote context"
	case .Invalid_Context:            return "invalid JSON-LD context"
	case .Invalid_Term_Definition:    return "invalid JSON-LD term definition"
	case .Protected_Term_Redefinition:return "protected JSON-LD term redefinition"
	case .Invalid_IRI:                return "invalid JSON-LD IRI"
	case .Invalid_Value_Object:       return "invalid JSON-LD value object"
	case .Invalid_List_Object:        return "invalid JSON-LD list object"
	case .Invalid_Reverse_Property:   return "invalid JSON-LD reverse property"
	case .Invalid_Graph:              return "invalid JSON-LD graph name"
	case .Unsupported_Feature:        return "unsupported JSON-LD feature"
	case .Quad_Limit:                 return "quad limit reached"
	case .Stopped:                    return "stopped by sink"
	case .Out_Of_Memory:              return "memory allocation failed"
	}
	return "unknown error"
}

// Document_Loader supplies a remote ctx document. The returned string is
// consumed before the callback returns; callers retain its storage. The loader
// is opt-in so this package never performs implicit network I/O.
Document_Loader :: proc(url: string, user_data: rawptr) -> (document: string, ok: bool)

// RDF_Direction_Mode selects the lossless RDF representation used for JSON-LD
// 1.1 value objects containing @direction. The default follows rdfDirection:
// null and accepts direction metadata without serializing it into RDF.
// I18n_Datatype uses the JSON-LD i18n datatype namespace. Compound_Literal
// uses the RDF value/direction/language blank-node representation.
RDF_Direction_Mode :: enum {
	None,
	I18n_Datatype,
	Compound_Literal,
}

// Options bounds retained state. Zero selects the documented default, except
// max_quads where zero disables the output cap. base_iri must be absolute when
// provided; it is used to resolve document-relative identifiers and contexts.
Options :: struct {
	base_iri:            string,
	max_document_bytes:  int,
	max_nesting_depth:   int,
	max_contexts:        int,
	max_remote_contexts: int,
	max_quads:           int,
	rdf_direction:       RDF_Direction_Mode,
	document_loader:     Document_Loader,
	loader_data:         rawptr,
}

DEFAULT_MAX_DOCUMENT_BYTES  :: 16 * 1024 * 1024
DEFAULT_MAX_NESTING_DEPTH   :: 256
DEFAULT_MAX_CONTEXTS        :: 1024
DEFAULT_MAX_REMOTE_CONTEXTS :: 16

// Sink receives RDF dataset statements. Strings are valid only for the
// callback, matching the ownership contract of the other syntax packages.
Sink :: proc(quad: rdf.Quad, user_data: rawptr) -> bool

@(private) Term_Definition :: struct {
	id:             string,
	type:           string,
	language:       string,
	has_language:   bool,
	language_null:  bool,
	direction:      string,
	has_direction:  bool,
	direction_null: bool,
	container_list: bool,
	container_set:  bool,
	container_language: bool,
	container_index: bool,
	container_graph: bool,
	container_id:    bool,
	container_type:  bool,
	index:          string,
	has_index:      bool,
	reverse:        bool,
	disabled:       bool,
	protected:      bool,
	has_local_context: bool,
	local_context:     string,
}

@(private) Context :: struct {
	terms:            map[string]Term_Definition,
	base_iri:         string,
	vocab:            string,
	language:         string,
	has_language:     bool,
	direction:        string,
	has_direction:    bool,
	has_previous:     bool,
	previous_terms:   map[string]Term_Definition,
	previous_base_iri: string,
	previous_vocab:    string,
	previous_language: string,
	previous_has_language: bool,
	previous_direction: string,
	previous_has_direction: bool,
}

@(private) State :: struct {
	sink:              Sink,
	user_data:         rawptr,
	scope:             rdf.Blank_Node_Scope,
	owned:             [dynamic]string,
	contexts:          [dynamic]map[string]Term_Definition,
	remote_urls:       map[string]bool,
	named_bnodes:      map[string]rdf.Term,
	generated:         u64,
	emitted:           int,
	context_count:     int,
	remote_count:      int,
	max_contexts:      int,
	max_remote:        int,
	max_quads:         int,
	loader:            Document_Loader,
	loader_data:       rawptr,
	allow_document_containers: bool,
	allow_direction:           bool,
	rdf_direction:             RDF_Direction_Mode,
	retain_id_only_nodes:       bool,
	retain_frame_controls:      bool,
	prune_frame_blank_ids:       bool,
	referenced_frame_blank_ids:  map[string]bool,
	canonical_frame_blank_ids:   bool,
	frame_blank_aliases:         map[string]string,
	frame_blank_counter:         u64,
}

@(private) destroy_state :: proc(state: ^State) {
	for value in state.owned do delete(value)
	delete(state.owned)
	for ctx in state.contexts do delete(ctx)
	delete(state.contexts)
	if state.remote_urls != nil do delete(state.remote_urls)
	if state.named_bnodes != nil do delete(state.named_bnodes)
	if state.referenced_frame_blank_ids != nil do delete(state.referenced_frame_blank_ids)
	if state.frame_blank_aliases != nil do delete(state.frame_blank_aliases)
}

@(private) own :: proc(state: ^State, value: string) -> (string, Parse_Error) {
	cloned, alloc_error := strings.clone(value)
	if alloc_error != nil do return "", Parse_Error{code = .Out_Of_Memory}
	append(&state.owned, cloned)
	return cloned, {}
}

@(private) make_context :: proc(state: ^State, parent: ^Context) -> (Context, Parse_Error) {
	if state.context_count >= state.max_contexts do return {}, Parse_Error{code = .Context_Limit}
	state.context_count += 1
	result: Context
	result.terms = make(map[string]Term_Definition)
	if parent != nil {
		result.base_iri = parent.base_iri
		result.vocab = parent.vocab
		result.language = parent.language
		result.has_language = parent.has_language
		result.direction = parent.direction
		result.has_direction = parent.has_direction
		result.has_previous = parent.has_previous
		result.previous_terms = parent.previous_terms
		result.previous_base_iri = parent.previous_base_iri
		result.previous_vocab = parent.previous_vocab
		result.previous_language = parent.previous_language
		result.previous_has_language = parent.previous_has_language
		result.previous_direction = parent.previous_direction
		result.previous_has_direction = parent.previous_has_direction
		for key in parent.terms do result.terms[key] = parent.terms[key]
	}
	return result, {}
}

@(private) retain_context :: proc(state: ^State, ctx: Context) {
	append(&state.contexts, ctx.terms)
}

@(private) discard_unretained_context :: proc(ctx: ^Context, retained: ^bool) {
	if !retained^ do delete(ctx.terms)
}

@(private) set_previous_context :: proc(result, previous: ^Context) {
	if result.has_previous do return
	result.has_previous = true
	result.previous_terms = previous.terms
	result.previous_base_iri = previous.base_iri
	result.previous_vocab = previous.vocab
	result.previous_language = previous.language
	result.previous_has_language = previous.has_language
	result.previous_direction = previous.direction
	result.previous_has_direction = previous.has_direction
}

@(private) previous_context :: proc(ctx: ^Context) -> Context {
	return Context{
		terms = ctx.previous_terms,
		base_iri = ctx.previous_base_iri,
		vocab = ctx.previous_vocab,
		language = ctx.previous_language,
		has_language = ctx.previous_has_language,
		direction = ctx.previous_direction,
		has_direction = ctx.previous_has_direction,
	}
}

@(private) object_value :: proc(object: json.Object, key: string) -> (json.Value, bool) {
	value, ok := object[key]
	return value, ok
}

@(private) string_value :: proc(value: json.Value) -> (string, bool) {
	#partial switch actual in value {
	case json.String: return string(actual), true
	}
	return "", false
}

@(private) bool_value :: proc(value: json.Value) -> (bool, bool) {
	#partial switch actual in value {
	case json.Boolean: return bool(actual), true
	}
	return false, false
}

@(private) object_from_value :: proc(value: json.Value) -> (json.Object, bool) {
	#partial switch actual in value {
	case json.Object: return actual, true
	}
	return nil, false
}

@(private) array_from_value :: proc(value: json.Value) -> (json.Array, bool) {
	#partial switch actual in value {
	case json.Array: return actual, true
	}
	return nil, false
}

@(private) is_keyword :: proc(value: string) -> bool {
	switch value {
	case "@base", "@container", "@context", "@direction", "@graph", "@id", "@import", "@included", "@index", "@json", "@language", "@list", "@nest", "@none", "@prefix", "@propagate", "@protected", "@reverse", "@set", "@type", "@value", "@version", "@vocab": return true
	}
	return false
}

@(private) keyword_for :: proc(ctx: ^Context, key: string) -> string {
	if is_keyword(key) do return key
	if definition, ok := ctx.terms[key]; ok && is_keyword(definition.id) do return definition.id
	return ""
}

@(private) has_iri_scheme :: proc(value: string) -> bool {
	if len(value) == 0 || !((value[0] >= 'A' && value[0] <= 'Z') || (value[0] >= 'a' && value[0] <= 'z')) do return false
	for index in 1..<len(value) {
		c := value[index]
		if c == ':' do return true
		if !((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '+' || c == '-' || c == '.') do return false
	}
	return false
}

@(private) resolve_iri :: proc(state: ^State, base, reference: string) -> (string, Parse_Error) {
	if len(reference) == 0 {
		if len(base) == 0 do return "", Parse_Error{code = .Invalid_IRI}
		return own(state, base)
	}
	// JSON-LD keeps an absolute IRI (including its dot segments) as supplied;
	// only relative references are resolved against the active base.
	if has_iri_scheme(reference) do return own(state, reference)
	if len(base) == 0 do return own(state, reference)
	resolved, ok := turtle.resolve_iri_reference(base, reference)
	if !ok do return "", Parse_Error{code = .Invalid_IRI}
	value, err := own(state, resolved)
	delete(resolved)
	return value, err
}

// expand_iri applies JSON-LD term, compact-IRI, vocabulary, and base rules.
@(private) expand_iri :: proc(state: ^State, ctx: ^Context, value: string, vocab, document_relative: bool) -> (string, Parse_Error) {
	if is_keyword(value) do return value, {}
	if definition, ok := ctx.terms[value]; ok && len(definition.id) > 0 do return definition.id, {}
	if colon := strings.index_byte(value, ':'); colon >= 0 {
		prefix, suffix := value[:colon], value[colon + 1:]
		if prefix != "_" && !strings.has_prefix(suffix, "//") {
			if definition, ok := ctx.terms[prefix]; ok && len(definition.id) > 0 {
				builder := strings.builder_make()
				defer strings.builder_destroy(&builder)
				strings.write_string(&builder, definition.id)
				strings.write_string(&builder, suffix)
				return own(state, strings.to_string(builder))
			}
		}
		return own(state, value)
	}
	if vocab && len(ctx.vocab) > 0 {
		builder := strings.builder_make()
		defer strings.builder_destroy(&builder)
		strings.write_string(&builder, ctx.vocab)
		strings.write_string(&builder, value)
		return own(state, strings.to_string(builder))
	}
	if document_relative do return resolve_iri(state, ctx.base_iri, value)
	return own(state, value)
}

// expand_identifier_iri follows the document-relative branch of IRI
// expansion for node identifiers and @id-coerced values. A term definition is
// not itself an identifier value, but its prefix remains available in a
// compact IRI such as ex:item.
@(private) expand_identifier_iri :: proc(state: ^State, ctx: ^Context, value: string) -> (string, Parse_Error) {
	// Without a document base there is no document-relative target to resolve.
	// Preserve the package's established term fallback for that bounded mode.
	if len(ctx.base_iri) == 0 do return expand_iri(state, ctx, value, false, true)
	if is_keyword(value) do return value, {}
	if colon := strings.index_byte(value, ':'); colon >= 0 {
		prefix, suffix := value[:colon], value[colon + 1:]
		if prefix != "_" && !strings.has_prefix(suffix, "//") {
			if definition, ok := ctx.terms[prefix]; ok && len(definition.id) > 0 {
				builder := strings.builder_make()
				defer strings.builder_destroy(&builder)
				strings.write_string(&builder, definition.id)
				strings.write_string(&builder, suffix)
				return own(state, strings.to_string(builder))
			}
		}
		return own(state, value)
	}
	return resolve_iri(state, ctx.base_iri, value)
}

@(private) apply_container :: proc(state: ^State, definition: ^Term_Definition, value: json.Value) -> bool {
	items: [dynamic]json.Value
	defer delete(items)
	if _, is_string := string_value(value); is_string {
		append(&items, value)
	} else if array, is_array := array_from_value(value); is_array {
		for item in array do append(&items, item)
	} else {
		return false
	}
	if len(items) == 0 do return false
	for item in items {
		container, valid := string_value(item)
		if !valid do return false
		switch container {
		case "@list":
			if definition.container_list do return false
			definition.container_list = true
		case "@set":
			if definition.container_set do return false
			definition.container_set = true
		case "@language":
			if definition.container_language do return false
			definition.container_language = true
		case "@index":
			if definition.container_index do return false
			definition.container_index = true
		case "@graph":
			if !state.allow_document_containers || definition.container_graph do return false
			definition.container_graph = true
		case "@id":
			if !state.allow_document_containers || definition.container_id do return false
			definition.container_id = true
		case "@type":
			if !state.allow_document_containers || definition.container_type do return false
			definition.container_type = true
		case: return false
		}
	}
	// The supported combinations retain the same RDF interpretation as their
	// single-container counterparts. Graph containers are document-level only.
	if definition.container_list && (definition.container_language || definition.container_index) do return false
	if definition.container_language && definition.container_index do return false
	if definition.container_graph && (definition.container_list || definition.container_language) do return false
	if definition.container_id && (definition.container_list || definition.container_language || definition.container_index) do return false
	if definition.container_type && (definition.container_list || definition.container_language || definition.container_index || definition.container_id) do return false
	return true
}

@(private) apply_context :: proc(state: ^State, current: ^Context, value: json.Value, propagate := true) -> (Context, Parse_Error) {
	return apply_context_inner(state, current, value, false, propagate)
}

@(private) term_definitions_match :: proc(a, b: Term_Definition) -> bool {
	return a.id == b.id &&
		a.type == b.type &&
		a.language == b.language &&
		a.has_language == b.has_language &&
		a.language_null == b.language_null &&
		a.direction == b.direction &&
		a.has_direction == b.has_direction &&
		a.direction_null == b.direction_null &&
		a.container_list == b.container_list &&
		a.container_set == b.container_set &&
		a.container_language == b.container_language &&
		a.container_index == b.container_index &&
		a.container_graph == b.container_graph &&
		a.container_id == b.container_id &&
		a.container_type == b.container_type &&
		a.index == b.index &&
		a.has_index == b.has_index &&
		a.reverse == b.reverse &&
		a.disabled == b.disabled &&
		a.has_local_context == b.has_local_context &&
		a.local_context == b.local_context
}

@(private) set_term_definition :: proc(state: ^State, result, inherited: ^Context, term: string, definition: Term_Definition) -> Parse_Error {
	updated := definition
	if previous, found := inherited.terms[term]; found && previous.protected {
		if !term_definitions_match(previous, definition) do return Parse_Error{code = .Protected_Term_Redefinition}
		updated.protected = true
	}
	owned_term, own_error := own(state, term)
	if own_error.code != .None do return own_error
	result.terms[owned_term] = updated
	return {}
}

// imported_context prevents a sourced context from importing another source.
// JSON-LD 1.1 permits one @import indirection only; outer context members are
// applied afterwards and therefore deliberately override imported definitions.
@(private) apply_context_inner :: proc(state: ^State, current: ^Context, value: json.Value, imported_context, propagate: bool) -> (Context, Parse_Error) {
	#partial switch _ in value {
	case json.Null:
		result, err := make_context(state, nil)
		if err.code != .None do return {}, err
		// A null local context resets the active term, vocabulary, language, and
		// direction settings. Keep the document base available for relative IRIs.
		result.base_iri = current.base_iri
		retain_context(state, result)
		return result, {}
	}
	if array, ok := array_from_value(value); ok {
		result := current^
		array_propagate := propagate
		for index in 0..<len(array) {
			item := array[index]
			item_propagate := propagate
			if object, is_object := object_from_value(item); is_object {
				if propagate_value, found := object_value(object, "@propagate"); found {
					valid: bool
					item_propagate, valid = bool_value(propagate_value)
					if !valid do return {}, Parse_Error{code = .Invalid_Context}
				}
			}
			if index > 0 && item_propagate != array_propagate do return {}, Parse_Error{code = .Invalid_Context}
			array_propagate = item_propagate
			updated, err := apply_context_inner(state, &result, item, imported_context, item_propagate)
			if err.code != .None do return {}, err
			result = updated
		}
		return result, {}
	}
	if remote, ok := string_value(value); ok {
		if state.loader == nil do return {}, Parse_Error{code = .Remote_Context_Disallowed}
		url, err := expand_iri(state, current, remote, false, true)
		if err.code != .None do return {}, err
		if url in state.remote_urls do return {}, Parse_Error{code = .Invalid_Context}
		if state.remote_count >= state.max_remote do return {}, Parse_Error{code = .Remote_Context_Limit}
		state.remote_count += 1
		state.remote_urls[url] = true
		defer delete_key(&state.remote_urls, url)
		document, loaded := state.loader(url, state.loader_data)
		if !loaded do return {}, Parse_Error{code = .Loading_Document_Failed}
		parsed, json_error := json.parse_string(strings.trim_space(document), .JSON, true)
		if json_error != .None do return {}, Parse_Error{code = .Loading_Document_Failed}
		defer json.destroy_value(parsed)
		remote_object, object_ok := object_from_value(parsed)
		if !object_ok do return {}, Parse_Error{code = .Invalid_Context}
		remote_context, context_ok := object_value(remote_object, "@context")
		if !context_ok do return {}, Parse_Error{code = .Invalid_Context}
		return apply_context_inner(state, current, remote_context, imported_context, propagate)
	}
	object, ok := object_from_value(value)
	if !ok do return {}, Parse_Error{code = .Invalid_Context}
	active_propagate := propagate
	if propagate_value, found := object_value(object, "@propagate"); found {
		active_propagate, ok = bool_value(propagate_value)
		if !ok do return {}, Parse_Error{code = .Invalid_Context}
	}
	default_protected := false
	if protected_value, found := object_value(object, "@protected"); found {
		valid: bool
		default_protected, valid = bool_value(protected_value)
		if !valid do return {}, Parse_Error{code = .Invalid_Context}
	}
	protected_terms := make([dynamic]string)
	defer delete(protected_terms)
	imported_relative_ids := make(map[string]string)
	defer delete(imported_relative_ids)
	context_base := current^
	if import_value, found := object_value(object, "@import"); found {
		if imported_context do return {}, Parse_Error{code = .Invalid_Context}
		import_reference, valid := string_value(import_value)
		if !valid do return {}, Parse_Error{code = .Invalid_Context}
		if state.loader == nil do return {}, Parse_Error{code = .Remote_Context_Disallowed}
		url, err := resolve_iri(state, current.base_iri, import_reference)
		if err.code != .None do return {}, err
		if url in state.remote_urls do return {}, Parse_Error{code = .Invalid_Context}
		if state.remote_count >= state.max_remote do return {}, Parse_Error{code = .Remote_Context_Limit}
		state.remote_count += 1
		state.remote_urls[url] = true
		defer delete_key(&state.remote_urls, url)
		document, loaded := state.loader(url, state.loader_data)
		if !loaded do return {}, Parse_Error{code = .Loading_Document_Failed}
		parsed, json_error := json.parse_string(strings.trim_space(document), .JSON, true)
		if json_error != .None do return {}, Parse_Error{code = .Loading_Document_Failed}
		defer json.destroy_value(parsed)
		import_document, document_ok := object_from_value(parsed)
		if !document_ok do return {}, Parse_Error{code = .Invalid_Context}
		imported_value, context_ok := object_value(import_document, "@context")
		if !context_ok do return {}, Parse_Error{code = .Invalid_Context}
		if _, is_array := array_from_value(imported_value); is_array do return {}, Parse_Error{code = .Invalid_Context}
		imported_object, imported_object_ok := object_from_value(imported_value)
		if !imported_object_ok do return {}, Parse_Error{code = .Invalid_Context}
		if default_protected {
			for term in imported_object {
				if strings.has_prefix(term, "@") do continue
				owned_term, term_error := own(state, term)
				if term_error.code != .None do return {}, term_error
				append(&protected_terms, owned_term)
			}
		}
		for term, definition_value in imported_object {
			if strings.has_prefix(term, "@") do continue
			definition_object, definition_ok := object_from_value(definition_value)
			if !definition_ok do continue
			identifier_value, has_identifier := object_value(definition_object, "@id")
			identifier, identifier_valid := string_value(identifier_value)
			if !has_identifier || !identifier_valid || has_iri_scheme(identifier) || strings.index_byte(identifier, ':') >= 0 || is_keyword(identifier) do continue
			owned_term, term_error := own(state, term)
			if term_error.code != .None do return {}, term_error
			owned_identifier, identifier_error := own(state, identifier)
			if identifier_error.code != .None do return {}, identifier_error
			imported_relative_ids[owned_term] = owned_identifier
		}
		context_base, err = apply_context_inner(state, current, imported_value, true, active_propagate)
		if err.code != .None do return {}, err
	}
	for key in object {
		if key == "@import" do continue
		if key == "@direction" do continue
		if key == "@propagate" do continue
		if key == "@protected" {
			continue
		}
		if key == "@version" {
			if !state.allow_document_containers do return {}, Parse_Error{code = .Unsupported_Feature}
			#partial switch version in object[key] {
			case json.Float:   if f64(version) != 1.1 do return {}, Parse_Error{code = .Invalid_Context}
			case json.Integer: if i64(version) != 1 do return {}, Parse_Error{code = .Invalid_Context}
			case: return {}, Parse_Error{code = .Invalid_Context}
			}
		}
	}
	result, make_error := make_context(state, &context_base)
	if make_error.code != .None do return {}, make_error
	result_retained := false
	defer discard_unretained_context(&result, &result_retained)
	if !active_propagate do set_previous_context(&result, current)
	if base_value, found := object_value(object, "@base"); found {
		if base_value_string, valid := string_value(base_value); valid {
			base, err := resolve_iri(state, current.base_iri, base_value_string)
			if err.code != .None do return {}, err
			result.base_iri = base
		} else {
			#partial switch null in base_value { case json.Null: result.base_iri = ""; case: return {}, Parse_Error{code = .Invalid_Context} }
		}
	}
	if vocab_value, found := object_value(object, "@vocab"); found {
		if vocab_value_string, valid := string_value(vocab_value); valid {
			vocab, err := expand_iri(state, &result, vocab_value_string, true, true)
			if err.code != .None do return {}, err
			result.vocab = vocab
		} else {
			#partial switch null in vocab_value { case json.Null: result.vocab = ""; case: return {}, Parse_Error{code = .Invalid_Context} }
		}
	}
	// A sourced context is merged into the containing context. Its relative
	// term identifiers therefore use the containing @vocab when one is present.
	for term, relative_id in imported_relative_ids {
		definition, found := result.terms[term]
		if !found do continue
		delete_key(&result.terms, term)
		identifier, identifier_error := expand_iri(state, &result, relative_id, true, true)
		if identifier_error.code != .None do return {}, identifier_error
		definition.id = identifier
		result.terms[term] = definition
	}
	if language_value, found := object_value(object, "@language"); found {
		if language, valid := string_value(language_value); valid {
			lowercase := strings.to_lower(language)
			result.language, make_error = own(state, lowercase)
			delete(lowercase)
			if make_error.code != .None do return {}, make_error
			result.has_language = true
		} else {
			#partial switch null in language_value { case json.Null: result.language = ""; result.has_language = false; case: return {}, Parse_Error{code = .Invalid_Context} }
		}
	}
	if direction_value, found := object_value(object, "@direction"); found {
		if !state.allow_direction do return {}, Parse_Error{code = .Unsupported_Feature}
		#partial switch null in direction_value {
		case json.Null:
			result.direction = ""
			result.has_direction = false
		case:
			direction, valid := string_value(direction_value)
			if !valid || (direction != "ltr" && direction != "rtl") do return {}, Parse_Error{code = .Invalid_Context}
			result.direction = direction == "ltr" ? "ltr" : "rtl"
			result.has_direction = true
		}
	}
	// Context object iteration is deliberately unordered. Establish absolute
	// prefix mappings first so a later compact IRI such as ex:friend does not
	// depend on map iteration order.
	for term, definition_value in object {
		if strings.has_prefix(term, "@") do continue
		id, simple := string_value(definition_value)
		if !simple {
			definition_object, object_ok := object_from_value(definition_value)
			if object_ok {
				identifier_value, has_identifier := object_value(definition_object, "@id")
				if has_identifier do id, simple = string_value(identifier_value)
			}
		}
		if !simple || !(strings.has_prefix(id, "http://") || strings.has_prefix(id, "https://") || strings.has_prefix(id, "urn:") || strings.has_prefix(id, "_:")) do continue
		identifier, err := own(state, id)
		if err.code != .None do return {}, err
		owned_term, term_error := own(state, term)
		if term_error.code != .None do return {}, term_error
		result.terms[owned_term] = Term_Definition{id = identifier}
	}
	for term, definition_value in object {
		if strings.has_prefix(term, "@") do continue
		// A redefinition must not resolve its own identifier through a previous
		// context definition. Other local prefix mappings remain available.
		delete_key(&result.terms, term)
		definition := Term_Definition{protected = default_protected}
		is_null := false
		#partial switch _ in definition_value { case json.Null: is_null = true }
		if is_null {
			if err := set_term_definition(state, &result, &context_base, term, Term_Definition{disabled = true, protected = default_protected}); err.code != .None do return {}, err
			continue
		}
		if simple_id, simple := string_value(definition_value); simple {
			id, err := expand_iri(state, &result, simple_id, true, true)
			if err.code != .None do return {}, err
			definition.id = id
			if definition_err := set_term_definition(state, &result, &context_base, term, definition); definition_err.code != .None do return {}, definition_err
			continue
		}
		definition_object, object_ok := object_from_value(definition_value)
		if !object_ok do return {}, Parse_Error{code = .Invalid_Term_Definition}
		if reverse_value, found := object_value(definition_object, "@reverse"); found {
			reverse, valid := string_value(reverse_value)
			if !valid do return {}, Parse_Error{code = .Invalid_Term_Definition}
			definition.id, make_error = expand_iri(state, &result, reverse, true, true)
			if make_error.code != .None do return {}, make_error
			definition.reverse = true
		} else if id_value, has_identifier := object_value(definition_object, "@id"); has_identifier {
			#partial switch null in id_value {
			case json.Null:
				definition.id = ""
				definition.disabled = true
			case:
				id, valid := string_value(id_value)
				if !valid do return {}, Parse_Error{code = .Invalid_Term_Definition}
				definition.id, make_error = expand_iri(state, &result, id, true, true)
				if make_error.code != .None do return {}, make_error
			}
		} else {
			definition.id, make_error = expand_iri(state, &result, term, true, false)
			if make_error.code != .None do return {}, make_error
		}
		if type_value, found := object_value(definition_object, "@type"); found {
			type_name, valid := string_value(type_value)
			if !valid do return {}, Parse_Error{code = .Invalid_Term_Definition}
			if type_name == "@id" { definition.type = "@id" } else if type_name == "@vocab" { definition.type = "@vocab" } else if type_name == "@json" { definition.type = "@json" } else {
				definition.type, make_error = expand_iri(state, &result, type_name, true, true)
				if make_error.code != .None do return {}, make_error
			}
		}
		if language_value, found := object_value(definition_object, "@language"); found {
			#partial switch null in language_value {
		case json.Null:
			definition.language = ""
			definition.has_language = false
			definition.language_null = true
			case:
				language, valid := string_value(language_value)
				if !valid do return {}, Parse_Error{code = .Invalid_Term_Definition}
				lowercase := strings.to_lower(language)
				definition.language, make_error = own(state, lowercase)
				delete(lowercase)
				if make_error.code != .None do return {}, make_error
				definition.has_language = true
			}
		}
		if direction_value, found := object_value(definition_object, "@direction"); found {
			if !state.allow_direction do return {}, Parse_Error{code = .Unsupported_Feature}
			#partial switch null in direction_value {
			case json.Null:
				definition.direction = ""
				definition.has_direction = false
				definition.direction_null = true
			case:
				direction, valid := string_value(direction_value)
				if !valid || (direction != "ltr" && direction != "rtl") do return {}, Parse_Error{code = .Invalid_Term_Definition}
				definition.direction = direction == "ltr" ? "ltr" : "rtl"
				definition.has_direction = true
			}
		}
		if container_value, found := object_value(definition_object, "@container"); found {
			if !apply_container(state, &definition, container_value) do return {}, Parse_Error{code = .Invalid_Term_Definition}
		}
		if index_value, found := object_value(definition_object, "@index"); found {
			index_name, valid := string_value(index_value)
			if !valid || !definition.container_index do return {}, Parse_Error{code = .Invalid_Term_Definition}
			if index_name == "@index" {
				definition.index = "@index"
			} else {
				definition.index, make_error = expand_iri(state, &result, index_name, true, true)
				if make_error.code != .None do return {}, make_error
			}
			definition.has_index = true
		}
		if local_context, found := object_value(definition_object, "@context"); found {
			serialized := strings.builder_make()
			if !compact_write_raw_json(&serialized, local_context) {
				strings.builder_destroy(&serialized)
				return {}, Parse_Error{code = .Invalid_Term_Definition}
			}
			definition.local_context, make_error = own(state, strings.to_string(serialized))
			strings.builder_destroy(&serialized)
			if make_error.code != .None do return {}, make_error
			definition.has_local_context = true
		}
		if protected_value, found := object_value(definition_object, "@protected"); found {
			protected, valid := bool_value(protected_value)
			if !valid do return {}, Parse_Error{code = .Invalid_Term_Definition}
			definition.protected = protected
		}
		if definition_err := set_term_definition(state, &result, &context_base, term, definition); definition_err.code != .None do return {}, definition_err
	}
	for term in protected_terms {
		if _, locally_defined := object_value(object, term); locally_defined do continue
		definition, found := result.terms[term]
		if !found do continue
		definition.protected = true
		result.terms[term] = definition
	}
	retain_context(state, result)
	result_retained = true
	return result, {}
}

// Term-scoped contexts apply to values of a term and to nodes whose type is
// represented by that term. They are non-propagating by default; an explicit
// @propagate: true in the scoped context opts into propagation. Keeping the
// parsed form as owned JSON text makes contexts safe to retain after their
// source document has been released.
@(private) apply_term_scoped_context :: proc(state: ^State, current: ^Context, definition: Term_Definition) -> (Context, Parse_Error) {
	if !definition.has_local_context do return current^, {}
	value, json_error := json.parse_string(definition.local_context, .JSON, true)
	if json_error != .None do return {}, Parse_Error{code = .Invalid_Context}
	defer json.destroy_value(value)
	return apply_context(state, current, value, false)
}

@(private) blank_node :: proc(state: ^State) -> (rdf.Term, Parse_Error) {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	strings.write_string(&builder, "b")
	strings.write_u64(&builder, state.generated)
	state.generated += 1
	label, err := own(state, strings.to_string(builder))
	if err.code != .None do return {}, err
	return rdf.blank_node(label, state.scope), {}
}

@(private) expanded_identifier_term :: proc(state: ^State, id: string) -> (rdf.Term, Parse_Error) {
	if strings.has_prefix(id, "_:") {
		if len(id) <= 2 do return {}, Parse_Error{code = .Invalid_IRI}
		if node, exists := state.named_bnodes[id]; exists do return node, {}
		node, node_err := blank_node(state)
		if node_err.code != .None do return {}, node_err
		state.named_bnodes[id] = node
		return node, {}
	}
	return rdf.iri(id), {}
}

@(private) identifier_term :: proc(state: ^State, ctx: ^Context, value: string) -> (rdf.Term, Parse_Error) {
	id, err := expand_identifier_iri(state, ctx, value)
	if err.code != .None do return {}, err
	return expanded_identifier_term(state, id)
}

// preassign_blank_nodes makes explicit JSON-LD blank-node identifiers stable
// before anonymous nodes are generated. It also prevents a later _:label from
// colliding with a generated bN label in the exposed RDF dataset.
@(private) preassign_blank_nodes :: proc(state: ^State, value: json.Value) -> Parse_Error {
	if array, is_array := array_from_value(value); is_array {
		for index in 0..<len(array) {
			if err := preassign_blank_nodes(state, array[index]); err.code != .None do return err
		}
		return {}
	}
	object, is_object := object_from_value(value)
	if !is_object do return {}
	if id_value, has_id := object_value(object, "@id"); has_id {
		if id, is_string := string_value(id_value); is_string && strings.has_prefix(id, "_:") && !(id in state.named_bnodes) {
			node, node_err := blank_node(state)
			if node_err.code != .None do return node_err
			state.named_bnodes[id] = node
		}
	}
	keys := make([dynamic]string)
	defer delete(keys)
	for key in object do append(&keys, key)
	sort.sort(sort.Interface{
		collection = rawptr(&keys),
		len = proc(it: sort.Interface) -> int {
			keys := cast(^[dynamic]string)it.collection
			return len(keys^)
		},
		less = proc(it: sort.Interface, i, j: int) -> bool {
			keys := cast(^[dynamic]string)it.collection
			return strings.compare(keys[i], keys[j]) < 0
		},
		swap = proc(it: sort.Interface, i, j: int) {
			keys := cast(^[dynamic]string)it.collection
			keys[i], keys[j] = keys[j], keys[i]
		},
	})
	for key in keys {
		child := object[key]
		if key == "@context" do continue
		if err := preassign_blank_nodes(state, child); err.code != .None do return err
	}
	return {}
}

@(private) emit :: proc(state: ^State, subject, predicate, object: rdf.Term, graph: rdf.Quad) -> Parse_Error {
	if state.max_quads > 0 && state.emitted >= state.max_quads do return Parse_Error{code = .Quad_Limit}
	quad := graph
	quad.subject = subject
	quad.predicate = predicate
	quad.object = object
	if !state.sink(quad, state.user_data) do return Parse_Error{code = .Stopped}
	state.emitted += 1
	return {}
}

@(private) numeric_literal :: proc(state: ^State, value: json.Value, datatype: string = "") -> (rdf.Term, Parse_Error) {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	#partial switch actual in value {
	case json.Integer:
		strings.write_i64(&builder, i64(actual))
		if datatype == XSD_DOUBLE do strings.write_string(&builder, ".0E0")
		lexical, err := own(state, strings.to_string(builder))
		if err.code != .None do return {}, err
		output_datatype := len(datatype) == 0 ? XSD_INTEGER : datatype
		return rdf.typed_literal(lexical, output_datatype), {}
	case json.Float:
		strings.write_float(&builder, f64(actual), 'E', -1, 64)
		raw := strings.to_string(builder)
		separator := strings.index_byte(raw, 'E')
		if separator < 0 do return {}, Parse_Error{code = .Invalid_Value_Object}
		canonical := strings.builder_make()
		defer strings.builder_destroy(&canonical)
		mantissa := raw[:separator]
		strings.write_string(&canonical, mantissa)
		if strings.index_byte(mantissa, '.') < 0 do strings.write_string(&canonical, ".0")
		strings.write_byte(&canonical, 'E')
		exponent := raw[separator + 1:]
		if len(exponent) > 0 && exponent[0] == '+' do exponent = exponent[1:]
		negative := len(exponent) > 0 && exponent[0] == '-'
		if negative {
			strings.write_byte(&canonical, '-')
			exponent = exponent[1:]
		}
		for len(exponent) > 1 && exponent[0] == '0' do exponent = exponent[1:]
		strings.write_string(&canonical, exponent)
		lexical, err := own(state, strings.to_string(canonical))
		if err.code != .None do return {}, err
		output_datatype := len(datatype) == 0 ? XSD_DOUBLE : datatype
		return rdf.typed_literal(lexical, output_datatype), {}
	}
	return {}, Parse_Error{code = .Invalid_Value_Object}
}

@(private) direction_for_value :: proc(ctx: ^Context, definition: Term_Definition) -> (string, bool) {
	if definition.has_direction do return definition.direction, true
	if definition.direction_null do return "", false
	if ctx.has_direction do return ctx.direction, true
	return "", false
}

@(private) language_for_value :: proc(ctx: ^Context, definition: Term_Definition) -> (string, bool) {
	if definition.has_language do return definition.language, true
	if definition.language_null do return "", false
	if ctx.has_language do return ctx.language, true
	return "", false
}

@(private) i18n_direction_literal :: proc(state: ^State, text, language, direction: string) -> (rdf.Term, Parse_Error) {
	lowercase := strings.to_lower(language)
	defer delete(lowercase)
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	strings.write_string(&builder, I18N)
	strings.write_string(&builder, lowercase)
	strings.write_byte(&builder, '_')
	strings.write_string(&builder, direction)
	datatype, own_error := own(state, strings.to_string(builder))
	if own_error.code != .None do return {}, own_error
	return rdf.typed_literal(text, datatype), {}
}

@(private) compound_direction_literal :: proc(state: ^State, text, language, direction: string, graph: rdf.Quad) -> (rdf.Term, Parse_Error) {
	node, node_error := blank_node(state)
	if node_error.code != .None do return {}, node_error
	if emit_error := emit(state, node, rdf.iri(RDF_VALUE), rdf.literal(text), graph); emit_error.code != .None do return {}, emit_error
	if emit_error := emit(state, node, rdf.iri(RDF_DIRECTION), rdf.literal(direction), graph); emit_error.code != .None do return {}, emit_error
	if len(language) > 0 {
		lowercase := strings.to_lower(language)
		defer delete(lowercase)
		if emit_error := emit(state, node, rdf.iri(RDF_LANGUAGE), rdf.literal(lowercase), graph); emit_error.code != .None do return {}, emit_error
	}
	return node, {}
}

@(private) primitive_literal :: proc(state: ^State, ctx: ^Context, definition: Term_Definition, value: json.Value, graph: rdf.Quad) -> (rdf.Term, Parse_Error) {
	#partial switch actual in value {
	case json.String:
		text := string(actual)
		if definition.type == "@id" {
			return identifier_term(state, ctx, text)
		}
		if definition.type == "@vocab" {
			id, err := expand_iri(state, ctx, text, true, true)
			if err.code != .None do return {}, err
			return rdf.iri(id), {}
		}
		if len(definition.type) > 0 && definition.type != "@json" {
			return rdf.typed_literal(text, definition.type), {}
		}
		language, has_language := language_for_value(ctx, definition)
		direction, has_direction := direction_for_value(ctx, definition)
		if has_direction {
			if state.rdf_direction == .I18n_Datatype do return i18n_direction_literal(state, text, language, direction)
			if state.rdf_direction == .Compound_Literal do return compound_direction_literal(state, text, language, direction, graph)
		}
		if has_language do return rdf.language_literal(text, language), {}
		return rdf.literal(text), {}
	case json.Boolean:
		lexical := bool(actual) ? "true" : "false"
		type_iri := definition.type
		if type_iri == "@id" || type_iri == "@vocab" || type_iri == "@json" do type_iri = ""
		if len(type_iri) > 0 do return rdf.typed_literal(lexical, type_iri), {}
		return rdf.typed_literal(lexical, XSD_BOOLEAN), {}
	case json.Integer, json.Float:
		type_iri := definition.type
		if type_iri == "@id" || type_iri == "@vocab" || type_iri == "@json" do type_iri = ""
		return numeric_literal(state, value, type_iri)
	case json.Null:
		return {}, Parse_Error{code = .Invalid_Value_Object}
	}
	return {}, Parse_Error{code = .Invalid_Value_Object}
}

@(private) value_object_term :: proc(state: ^State, ctx: ^Context, object: json.Object, graph: rdf.Quad) -> (rdf.Term, Parse_Error) {
	value, found := has_keyword(object, ctx, "@value")
	if !found do return {}, Parse_Error{code = .Invalid_Value_Object}
	direction := ""
	has_direction := false
	if direction_value, direction_found := has_keyword(object, ctx, "@direction"); direction_found {
		direction_value_text, direction_valid := string_value(direction_value)
		if !direction_valid || (direction_value_text != "ltr" && direction_value_text != "rtl") do return {}, Parse_Error{code = .Invalid_Value_Object}
		direction = direction_value_text
		has_direction = true
	}
	if type_value, has_type := has_keyword(object, ctx, "@type"); has_type {
		type_name, valid := string_value(type_value)
		if !valid do return {}, Parse_Error{code = .Invalid_Value_Object}
		if has_direction do return {}, Parse_Error{code = .Invalid_Value_Object}
		if type_name == "@json" {
			encoded, marshal_error := json.marshal(value)
			if marshal_error != nil do return {}, Parse_Error{code = .Invalid_Value_Object}
			defer delete(encoded)
			lexical, own_error := own(state, string(encoded))
			if own_error.code != .None do return {}, own_error
			return rdf.typed_literal(lexical, RDF_JSON), {}
		}
	}
	#partial switch actual in value {
	case json.Null:
		return {}, Parse_Error{code = .Invalid_Value_Object}
	case json.Boolean, json.Integer, json.Float:
		if has_direction do return {}, Parse_Error{code = .Invalid_Value_Object}
		return primitive_literal(state, ctx, {}, value, graph)
	case json.String:
		text := string(actual)
		language := ""
		has_language := false
		if language_value, language_found := has_keyword(object, ctx, "@language"); language_found {
			parsed_language, valid := string_value(language_value)
			if !valid do return {}, Parse_Error{code = .Invalid_Value_Object}
			language = parsed_language
			has_language = true
		}
		if has_direction {
			if state.rdf_direction == .I18n_Datatype do return i18n_direction_literal(state, text, language, direction)
			if state.rdf_direction == .Compound_Literal do return compound_direction_literal(state, text, language, direction, graph)
		}
		if has_language do return rdf.language_literal(text, language), {}
		if type_value, has_type := has_keyword(object, ctx, "@type"); has_type {
			type_name, valid := string_value(type_value)
			if !valid || type_name == "@id" || type_name == "@vocab" do return {}, Parse_Error{code = .Invalid_Value_Object}
			datatype, err := expand_iri(state, ctx, type_name, true, true)
			if err.code != .None do return {}, err
			return rdf.typed_literal(text, datatype), {}
		}
		return rdf.literal(text), {}
	}
	return {}, Parse_Error{code = .Invalid_Value_Object}
}

@(private) has_keyword :: proc(object: json.Object, ctx: ^Context, keyword: string) -> (json.Value, bool) {
	for key, value in object {
		if keyword_for(ctx, key) == keyword do return value, true
	}
	return {}, false
}

@(private) graph_has_node_name :: proc(object: json.Object, ctx: ^Context, top_level: bool) -> bool {
	if !top_level do return true
	for key in object {
		keyword := keyword_for(ctx, key)
		if keyword != "@context" && keyword != "@graph" do return true
	}
	return false
}

@(private) process_value_set_aware :: proc(state: ^State, ctx: ^Context, definition: Term_Definition, value: json.Value, graph: rdf.Quad) -> ([dynamic]rdf.Term, Parse_Error) {
	result := make([dynamic]rdf.Term)
	#partial switch _ in value {
	case json.Null:
		return result, {}
	}
	if array, is_array := array_from_value(value); is_array {
		for item in array {
			terms, err := process_value_set_aware(state, ctx, definition, item, graph)
			if err.code != .None {
				delete(terms)
				delete(result)
				return {}, err
			}
			for term in terms do append(&result, term)
			delete(terms)
		}
		return result, {}
	}
	if object, is_object := object_from_value(value); is_object {
		active_context := ctx^
		if context_value, found := object_value(object, "@context"); found {
			updated, context_err := apply_context(state, ctx, context_value)
			if context_err.code != .None {
				delete(result)
				return {}, context_err
			}
			active_context = updated
		}
		if value_value, has_value := has_keyword(object, &active_context, "@value"); has_value {
			#partial switch _ in value_value {
			case json.Null:
				return result, {}
			}
		} else if _, has_language := has_keyword(object, &active_context, "@language"); has_language {
			return result, {}
		}
		if set_value, found := has_keyword(object, &active_context, "@set"); found {
			for key in object {
				keyword := keyword_for(&active_context, key)
				if keyword != "@context" && keyword != "@set" && keyword != "@index" {
					delete(result)
					return {}, Parse_Error{code = .Invalid_Value_Object}
				}
			}
			terms, set_err := process_value_set_aware(state, &active_context, definition, set_value, graph)
			if set_err.code != .None {
				delete(terms)
				delete(result)
				return {}, set_err
			}
			for term in terms do append(&result, term)
			delete(terms)
			return result, {}
		}
	}
	term, err := process_value(state, ctx, definition, value, graph)
	if err.code != .None {
		delete(result)
		return {}, err
	}
	append(&result, term)
	return result, {}
}

@(private) process_list :: proc(state: ^State, ctx: ^Context, definition: Term_Definition, value: json.Value, graph: rdf.Quad) -> (rdf.Term, Parse_Error) {
	items, items_err := process_value_set_aware(state, ctx, definition, value, graph)
	defer delete(items)
	if items_err.code != .None do return {}, items_err
	if len(items) == 0 do return rdf.iri(RDF_NIL), {}
	first, err := blank_node(state)
	if err.code != .None do return {}, err
	current := first
	for object, index in items {
		if emit_err := emit(state, current, rdf.iri(RDF_FIRST), object, graph); emit_err.code != .None do return {}, emit_err
		if index + 1 == len(items) {
			if emit_err := emit(state, current, rdf.iri(RDF_REST), rdf.iri(RDF_NIL), graph); emit_err.code != .None do return {}, emit_err
		} else {
			next, node_err := blank_node(state)
			if node_err.code != .None do return {}, node_err
			if emit_err := emit(state, current, rdf.iri(RDF_REST), next, graph); emit_err.code != .None do return {}, emit_err
			current = next
		}
	}
	return first, {}
}

@(private) container_list_value :: proc(ctx: ^Context, value: json.Value) -> json.Value {
	if object, is_object := object_from_value(value); is_object {
		if list, found := has_keyword(object, ctx, "@list"); found do return list
	}
	return value
}

// process_language_map turns a language container into its RDF values. The
// language is part of the RDF literal, so it remains available to FromRDF and
// can later be compacted back into a language map.
@(private) process_language_map :: proc(state: ^State, ctx: ^Context, definition: Term_Definition, value: json.Value, graph: rdf.Quad) -> ([dynamic]rdf.Term, Parse_Error) {
	result := make([dynamic]rdf.Term)
	map_object, valid := object_from_value(value)
	if !valid {
		delete(result)
		return {}, Parse_Error{code = .Invalid_Value_Object}
	}
	for language, mapped_value in map_object {
		mapped_definition := definition
		mapped_definition.has_language = false
		mapped_definition.language_null = false
		if language == "@none" {
			mapped_definition.language_null = true
		} else {
			lowercase := strings.to_lower(language)
			language_value, own_error := own(state, lowercase)
			delete(lowercase)
			if own_error.code != .None {
				delete(result)
				return {}, own_error
			}
			mapped_definition.language = language_value
			mapped_definition.has_language = true
		}
		terms, err := process_value_set_aware(state, ctx, mapped_definition, mapped_value, graph)
		if err.code != .None {
			delete(terms)
			delete(result)
			return {}, err
		}
		for term in terms do append(&result, term)
		delete(terms)
	}
	return result, {}
}

// process_index_map deliberately treats ordinary @index entries as JSON-LD
// annotation: RDF has no index slot. A custom @index property, however, is
// data and becomes a normal RDF statement as required by JSON-LD 1.1.
@(private) process_index_map :: proc(state: ^State, ctx: ^Context, definition: Term_Definition, value: json.Value, graph: rdf.Quad) -> ([dynamic]rdf.Term, Parse_Error) {
	result := make([dynamic]rdf.Term)
	map_object, valid := object_from_value(value)
	if !valid {
		delete(result)
		return {}, Parse_Error{code = .Invalid_Value_Object}
	}
	for index_key, mapped_value in map_object {
		terms, err := process_value_set_aware(state, ctx, definition, mapped_value, graph)
		if err.code != .None {
			delete(terms)
			delete(result)
			return {}, err
		}
		for term in terms {
			if definition.has_index && definition.index != "@index" && index_key != "@none" {
				if term.kind == .Literal {
					delete(terms)
					delete(result)
					return {}, Parse_Error{code = .Invalid_Value_Object}
				}
				if emit_err := emit(state, term, rdf.iri(definition.index), rdf.literal(index_key), graph); emit_err.code != .None {
					delete(terms)
					delete(result)
					return {}, emit_err
				}
			}
			append(&result, term)
		}
		delete(terms)
	}
	return result, {}
}

// A container map is distinguished from an ordinary node/value object by its
// keys. Accepting an ordinary value here keeps RDF-originated compact output
// parseable when index annotations were intentionally unavailable to restore.
@(private) is_container_map :: proc(value: json.Value) -> bool {
	object, valid := object_from_value(value)
	if !valid do return false
	for key in object {
		// @none is a valid language/index map key, not a node-object keyword.
		if strings.has_prefix(key, "@") && key != "@none" do return false
	}
	return true
}

@(private) process_node :: proc(state: ^State, ctx: ^Context, object: json.Object, graph: rdf.Quad, top_level := false) -> (rdf.Term, Parse_Error) {
	active_context := ctx^
	if context_value, found := object_value(object, "@context"); found {
		updated, context_err := apply_context(state, ctx, context_value)
		if context_err.code != .None do return {}, context_err
		active_context = updated
	}
	if value, found := has_keyword(object, &active_context, "@value"); found {
		_ = value
		return value_object_term(state, &active_context, object, graph)
	}
	if list, found := has_keyword(object, &active_context, "@list"); found {
		return process_list(state, &active_context, {}, list, graph)
	}
	if set_value, found := has_keyword(object, &active_context, "@set"); found {
		terms, set_err := process_value_set_aware(state, &active_context, {}, set_value, graph)
		delete(terms)
		if set_err.code != .None do return {}, set_err
		return {}, {}
	}

	subject: rdf.Term
	if id_value, found := has_keyword(object, &active_context, "@id"); found {
		id, valid := string_value(id_value)
		if !valid do return {}, Parse_Error{code = .Invalid_IRI}
		term, id_err := identifier_term(state, &active_context, id)
		if id_err.code != .None do return {}, id_err
		subject = term
	} else {
		term, node_err := blank_node(state)
		if node_err.code != .None do return {}, node_err
		subject = term
	}

	for key, type_value in object {
		if keyword_for(&active_context, key) != "@type" do continue
		types, array := array_from_value(type_value)
		count := array ? len(types) : 1
		for index in 0..<count {
			type_item := array ? types[index] : type_value
			type_name, valid := string_value(type_item)
			if !valid do return {}, Parse_Error{code = .Invalid_IRI}
			type_iri, type_err := expand_iri(state, &active_context, type_name, true, true)
			if type_err.code != .None do return {}, type_err
			type_term, term_err := expanded_identifier_term(state, type_iri)
			if term_err.code != .None do return {}, term_err
			if emit_err := emit(state, subject, rdf.iri(RDF_TYPE), type_term, graph); emit_err.code != .None do return {}, emit_err
		}
	}

	for key, property_value in object {
		keyword := keyword_for(&active_context, key)
		if keyword == "@context" || keyword == "@id" || keyword == "@type" || keyword == "@value" || keyword == "@list" || keyword == "@index" do continue
		if keyword == "@set" || keyword == "@direction" do return {}, Parse_Error{code = .Unsupported_Feature}
		if keyword == "@graph" {
			graph_quad := graph
			if graph_has_node_name(object, &active_context, top_level) {
				graph_quad.has_graph = true
				graph_quad.graph = subject
			}
			if graph_nodes, array := array_from_value(property_value); array {
				for index in 0..<len(graph_nodes) {
					node_value := graph_nodes[index]
					node, valid := object_from_value(node_value)
					// Free-floating values do not produce RDF statements. A list has
					// no graph-visible anchor either, so do not emit its RDF cells.
					if !valid do continue
					if _, is_list := has_keyword(node, &active_context, "@list"); is_list do continue
					if _, graph_err := process_node(state, &active_context, node, graph_quad); graph_err.code != .None do return {}, graph_err
				}
			} else {
				node, valid := object_from_value(property_value)
				if !valid do return {}, Parse_Error{code = .Invalid_Graph}
				if _, is_list := has_keyword(node, &active_context, "@list"); is_list do continue
				if _, graph_err := process_node(state, &active_context, node, graph_quad); graph_err.code != .None do return {}, graph_err
			}
			continue
		}
		if keyword == "@included" {
			included, array := array_from_value(property_value)
			included_count := array ? len(included) : 1
			for index in 0..<included_count {
				node_value := array ? included[index] : property_value
				node, valid := object_from_value(node_value)
				if !valid do return {}, Parse_Error{code = .Invalid_Graph}
				if _, included_err := process_node(state, &active_context, node, graph); included_err.code != .None do return {}, included_err
			}
			continue
		}
		if keyword == "@reverse" {
			reverse_object, valid := object_from_value(property_value)
			if !valid do return {}, Parse_Error{code = .Invalid_Reverse_Property}
			for reverse_key, reverse_value in reverse_object {
				definition := active_context.terms[reverse_key]
				if definition.disabled do continue
				if len(definition.id) == 0 && len(active_context.vocab) == 0 && !has_iri_scheme(reverse_key) && strings.index_byte(reverse_key, ':') < 0 do continue
				predicate_iri, predicate_err := expand_iri(state, &active_context, reverse_key, true, false)
				if predicate_err.code != .None || len(predicate_iri) == 0 || is_keyword(predicate_iri) { return {}, Parse_Error{code = .Invalid_Reverse_Property} }
				if strings.has_prefix(predicate_iri, "_:") do continue
				values, array := array_from_value(reverse_value)
				value_count := array ? len(values) : 1
				for index in 0..<value_count {
					reverse_item := array ? values[index] : reverse_value
					object_term, value_err := process_value(state, &active_context, definition, reverse_item, graph)
					if value_err.code != .None || object_term.kind == .Literal { return {}, Parse_Error{code = .Invalid_Reverse_Property} }
					if definition.reverse {
						if emit_err := emit(state, subject, rdf.iri(predicate_iri), object_term, graph); emit_err.code != .None do return {}, emit_err
					} else if emit_err := emit(state, object_term, rdf.iri(predicate_iri), subject, graph); emit_err.code != .None do return {}, emit_err
				}
			}
			continue
		}
		if keyword == "@nest" {
			nested, valid := object_from_value(property_value)
			if !valid do return {}, Parse_Error{code = .Invalid_Value_Object}
			// @nest is syntactic sugar: process its ordinary entries against the same subject.
			for nested_key, nested_value in nested {
				definition := active_context.terms[nested_key]
				if definition.disabled do continue
				if len(definition.id) == 0 && len(active_context.vocab) == 0 && !has_iri_scheme(nested_key) && strings.index_byte(nested_key, ':') < 0 do continue
				predicate_iri, predicate_err := expand_iri(state, &active_context, nested_key, true, false)
				if predicate_err.code != .None || len(predicate_iri) == 0 || is_keyword(predicate_iri) { return {}, Parse_Error{code = .Invalid_IRI} }
				// Blank node identifiers may be used for node and type identifiers,
				// but cannot occupy RDF's predicate position.
				if strings.has_prefix(predicate_iri, "_:") do continue
				if definition.container_list {
					list, list_err := process_list(state, &active_context, definition, container_list_value(&active_context, nested_value), graph)
					if list_err.code != .None do return {}, list_err
					if emit_err := emit(state, subject, rdf.iri(predicate_iri), list, graph); emit_err.code != .None do return {}, emit_err
					continue
				}
				object_terms, values_err := process_value_set_aware(state, &active_context, definition, nested_value, graph)
				if values_err.code != .None {
					delete(object_terms)
					return {}, values_err
				}
				for object_term in object_terms {
					if emit_err := emit(state, subject, rdf.iri(predicate_iri), object_term, graph); emit_err.code != .None {
						delete(object_terms)
						return {}, emit_err
					}
				}
				delete(object_terms)
			}
			continue
		}
		if len(keyword) > 0 do continue
		definition := active_context.terms[key]
		if definition.disabled do continue
		if len(definition.id) == 0 && len(active_context.vocab) == 0 && !has_iri_scheme(key) && strings.index_byte(key, ':') < 0 do continue
		predicate_iri, predicate_err := expand_iri(state, &active_context, key, true, false)
		if predicate_err.code != .None || len(predicate_iri) == 0 || is_keyword(predicate_iri) { return {}, Parse_Error{code = .Invalid_IRI} }
		// JSON-LD drops properties whose expanded predicate is a blank node;
		// RDF predicates must be IRIs.
		if strings.has_prefix(predicate_iri, "_:") do continue
		if (definition.container_language || definition.container_index) && is_container_map(property_value) {
			mapped: [dynamic]rdf.Term
			mapped_error: Parse_Error
			if definition.container_language {
				mapped, mapped_error = process_language_map(state, &active_context, definition, property_value, graph)
			} else {
				mapped, mapped_error = process_index_map(state, &active_context, definition, property_value, graph)
			}
			if mapped_error.code != .None do return {}, mapped_error
			for mapped_term in mapped {
				if definition.reverse {
					if mapped_term.kind == .Literal {
						delete(mapped)
						return {}, Parse_Error{code = .Invalid_Reverse_Property}
					}
					if emit_err := emit(state, mapped_term, rdf.iri(predicate_iri), subject, graph); emit_err.code != .None {
						delete(mapped)
						return {}, emit_err
					}
				} else if emit_err := emit(state, subject, rdf.iri(predicate_iri), mapped_term, graph); emit_err.code != .None {
					delete(mapped)
					return {}, emit_err
				}
			}
			delete(mapped)
			continue
		}
		if definition.container_list {
			list, list_err := process_list(state, &active_context, definition, container_list_value(&active_context, property_value), graph)
			if list_err.code != .None do return {}, list_err
			if definition.reverse {
				if list.kind == .Literal do return {}, Parse_Error{code = .Invalid_Reverse_Property}
				if emit_err := emit(state, list, rdf.iri(predicate_iri), subject, graph); emit_err.code != .None do return {}, emit_err
			} else if emit_err := emit(state, subject, rdf.iri(predicate_iri), list, graph); emit_err.code != .None { return {}, emit_err }
			continue
		}
		object_terms, values_err := process_value_set_aware(state, &active_context, definition, property_value, graph)
		if values_err.code != .None {
			delete(object_terms)
			return {}, values_err
		}
		for object_term in object_terms {
			if definition.reverse {
				if object_term.kind == .Literal {
					delete(object_terms)
					return {}, Parse_Error{code = .Invalid_Reverse_Property}
				}
				if emit_err := emit(state, object_term, rdf.iri(predicate_iri), subject, graph); emit_err.code != .None {
					delete(object_terms)
					return {}, emit_err
				}
			} else if emit_err := emit(state, subject, rdf.iri(predicate_iri), object_term, graph); emit_err.code != .None {
				delete(object_terms)
				return {}, emit_err
			}
		}
		delete(object_terms)
	}
	return subject, {}
}

@(private) process_value :: proc(state: ^State, ctx: ^Context, definition: Term_Definition, value: json.Value, graph: rdf.Quad) -> (rdf.Term, Parse_Error) {
	if object, is_object := object_from_value(value); is_object {
		if value_object, has_value := has_keyword(object, ctx, "@value"); has_value {
			_ = value_object
			return value_object_term(state, ctx, object, graph)
		}
		if list, has_list := has_keyword(object, ctx, "@list"); has_list do return process_list(state, ctx, definition, list, graph)
		return process_node(state, ctx, object, graph)
	}
	if _, is_array := array_from_value(value); is_array do return {}, Parse_Error{code = .Invalid_Value_Object}
	return primitive_literal(state, ctx, definition, value, graph)
}

@(private) scan_depth :: proc(input: string, maximum: int) -> Parse_Error {
	depth := 0
	in_string := false
	escaped := false
	line, column := 1, 1
	for byte in input {
		if in_string {
			if escaped { escaped = false } else if byte == '\\' { escaped = true } else if byte == '"' { in_string = false }
		} else {
			switch byte {
			case '"': in_string = true
			case '{', '[':
				depth += 1
				if depth > maximum do return Parse_Error{code = .Nesting_Limit, line = line, column = column}
			case '}', ']': if depth > 0 do depth -= 1
			}
		}
		if byte == '\n' { line += 1; column = 1 } else { column += 1 }
	}
	return {}
}

// parse transforms one complete JSON-LD document to RDF dataset statements.
// It retains input-derived JSON and ctx state until completion, then
// destroys it before returning. Use max_document_bytes for untrusted input.
parse :: proc(input: string, sink: Sink, options: Options = {}, user_data: rawptr = nil) -> Parse_Error {
	if sink == nil do return Parse_Error{code = .Missing_Sink, line = 1, column = 1}
	if !utf8.valid_string(input) do return Parse_Error{code = .Invalid_UTF8, line = 1, column = 1}
	max_document_bytes := options.max_document_bytes
	if max_document_bytes == 0 do max_document_bytes = DEFAULT_MAX_DOCUMENT_BYTES
	if max_document_bytes < 0 do return Parse_Error{code = .Invalid_Option, line = 1, column = 1}
	if len(input) > max_document_bytes do return Parse_Error{code = .Document_Too_Large, line = 1, column = 1}
	max_depth := options.max_nesting_depth
	if max_depth == 0 do max_depth = DEFAULT_MAX_NESTING_DEPTH
	if max_depth < 0 do return Parse_Error{code = .Invalid_Option, line = 1, column = 1}
	if depth_err := scan_depth(input, max_depth); depth_err.code != .None do return depth_err
	// core:encoding/json accepts the document grammar but its value parser does
	// not retain a root value when trailing whitespace remains after an object.
	// JSON permits that whitespace, so normalize it before materializing the AST.
	document := strings.trim_space(input)
	parsed, json_error := json.parse_string(document, .JSON, true)
	if json_error != .None do return Parse_Error{code = .Invalid_JSON, line = 1, column = 1}
	defer json.destroy_value(parsed)
	max_contexts := options.max_contexts
	if max_contexts == 0 do max_contexts = DEFAULT_MAX_CONTEXTS
	max_remote := options.max_remote_contexts
	if max_remote == 0 do max_remote = DEFAULT_MAX_REMOTE_CONTEXTS
	if max_contexts < 0 || max_remote < 0 || options.max_quads < 0 do return Parse_Error{code = .Invalid_Option, line = 1, column = 1}
	state := State{
		sink = sink,
		user_data = user_data,
		scope = rdf.new_blank_node_scope(),
		remote_urls = make(map[string]bool),
		named_bnodes = make(map[string]rdf.Term),
		max_contexts = max_contexts,
		max_remote = max_remote,
		max_quads = options.max_quads,
		rdf_direction = options.rdf_direction,
		loader = options.document_loader,
		loader_data = options.loader_data,
		allow_document_containers = true,
		allow_direction = true,
	}
	defer destroy_state(&state)
	if blank_err := preassign_blank_nodes(&state, parsed); blank_err.code != .None do return blank_err
	ctx, context_err := make_context(&state, nil)
	if context_err.code != .None do return context_err
	retain_context(&state, ctx)
	if len(options.base_iri) > 0 {
		if !has_iri_scheme(options.base_iri) do return Parse_Error{code = .Invalid_IRI}
		base, base_err := resolve_iri(&state, options.base_iri, "")
		if base_err.code != .None do return base_err
		ctx.base_iri = base
	}
	graph: rdf.Quad
	if array, is_array := array_from_value(parsed); is_array {
		for index in 0..<len(array) {
			value := array[index]
			object, valid := object_from_value(value)
			if !valid do return Parse_Error{code = .Invalid_Value_Object}
			if _, process_err := process_node(&state, &ctx, object, graph, true); process_err.code != .None do return process_err
		}
		return {}
	}
	object, valid := object_from_value(parsed)
	if !valid do return Parse_Error{code = .Invalid_Value_Object}
	_, process_err := process_node(&state, &ctx, object, graph, true)
	return process_err
}
