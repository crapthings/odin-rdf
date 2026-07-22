// Document-level JSON-LD expansion. This path deliberately runs before RDF
// conversion so JSON-LD-only constructs such as @set and @index are retained.
package jsonld

import json "core:encoding/json"
import "core:sort"
import "core:strings"
import "core:unicode/utf8"
import rdf ".."

Expand_Error :: enum {
	None,
	Invalid_Option,
	Invalid_UTF8,
	Invalid_JSON,
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
	Unsupported_Feature,
	Output_Too_Large,
	Out_Of_Memory,
}

expand_error_message :: proc(code: Expand_Error) -> string {
	switch code {
	case .None:                       return "no error"
	case .Invalid_Option:             return "expansion options are invalid"
	case .Invalid_UTF8:               return "invalid UTF-8"
	case .Invalid_JSON:               return "invalid JSON"
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
	case .Unsupported_Feature:        return "unsupported JSON-LD expansion feature"
	case .Output_Too_Large:           return "expanded JSON-LD exceeds configured byte limit"
	case .Out_Of_Memory:              return "memory allocation failed"
	}
	return "unknown error"
}

// Expand_Options keeps the existing, opt-in document-loader contract and adds
// an independent bound for the materialized expanded document. A zero output
// bound selects DEFAULT_MAX_EXPANDED_OUTPUT_BYTES.
Expand_Options :: struct {
	context_options:  Options,
	max_output_bytes: int,
	// preserve_top_level_graph keeps a document-level @graph object instead of
	// unwrapping it. Explicit Web HTML extraction uses this when combining more
	// than one script document.
	preserve_top_level_graph: bool,
}

DEFAULT_MAX_EXPANDED_OUTPUT_BYTES :: 32 * 1024 * 1024

@(private) expand_from_parse_error :: proc(err: Parse_Error) -> Expand_Error {
	#partial switch err.code {
	case .None:                       return .None
	case .Invalid_Option:             return .Invalid_Option
	case .Invalid_UTF8:               return .Invalid_UTF8
	case .Invalid_JSON:               return .Invalid_JSON
	case .Document_Too_Large:         return .Document_Too_Large
	case .Nesting_Limit:              return .Nesting_Limit
	case .Context_Limit:              return .Context_Limit
	case .Remote_Context_Limit:       return .Remote_Context_Limit
	case .Remote_Context_Disallowed:  return .Remote_Context_Disallowed
	case .Loading_Document_Failed:    return .Loading_Document_Failed
	case .Invalid_Context:            return .Invalid_Context
	case .Invalid_Term_Definition:    return .Invalid_Term_Definition
	case .Protected_Term_Redefinition:return .Protected_Term_Redefinition
	case .Invalid_IRI:                return .Invalid_IRI
	case .Invalid_Value_Object:       return .Invalid_Value_Object
	case .Invalid_List_Object:        return .Invalid_List_Object
	case .Invalid_Reverse_Property:   return .Invalid_Reverse_Property
	case .Unsupported_Feature:        return .Unsupported_Feature
	case .Out_Of_Memory:              return .Out_Of_Memory
	case:                             return .Unsupported_Feature
	}
}

@(private) expand_sorted_keys :: proc(object: json.Object) -> [dynamic]string {
	keys := make([dynamic]string)
	for key in object do append(&keys, key)
	sort.sort(sort.Interface{
		collection = rawptr(&keys),
		len = proc(it: sort.Interface) -> int { return len((cast(^[dynamic]string)it.collection)^) },
		less = proc(it: sort.Interface, i, j: int) -> bool {
			keys := cast(^[dynamic]string)it.collection
			return strings.compare(keys[i], keys[j]) < 0
		},
		swap = proc(it: sort.Interface, i, j: int) {
			keys := cast(^[dynamic]string)it.collection
			keys[i], keys[j] = keys[j], keys[i]
		},
	})
	return keys
}

@(private) expand_write_member_prefix :: proc(builder: ^strings.Builder, first: ^bool, key: string) {
	if !first^ do strings.write_string(builder, ", ")
	write_json_string(builder, key)
	strings.write_string(builder, ": ")
	first^ = false
}

@(private) expand_is_null :: proc(value: json.Value) -> bool {
	#partial switch _ in value { case json.Null: return true }
	return false
}

@(private) expand_is_null_value_object :: proc(object: json.Object, ctx: ^Context) -> bool {
	value, has_value := has_keyword(object, ctx, "@value")
	return has_value && expand_is_null(value)
}

@(private) expand_is_json_value_object :: proc(object: json.Object, ctx: ^Context) -> bool {
	type_value, has_type := has_keyword(object, ctx, "@type")
	type_name, valid_type := string_value(type_value)
	return has_type && valid_type && (type_name == "@json" || keyword_for(ctx, type_name) == "@json")
}

@(private) expand_apply_local_context :: proc(state: ^State, current: ^Context, value: json.Value) -> (Context, Expand_Error) {
	#partial switch _ in value {
	case json.Null:
		result, err := make_context(state, nil)
		if err.code != .None do return {}, expand_from_parse_error(err)
		// A null local context restores the initial context, including the
		// document base rather than a parent node's local @base override.
		result.base_iri = state.initial_base_iri
		retain_context(state, result)
		return result, .None
	}
	result, err := apply_context(state, current, value)
	if err.code != .None do return {}, expand_from_parse_error(err)
	return result, .None
}

@(private) expand_rolls_back_context :: proc(ctx: ^Context, object: json.Object) -> bool {
	if !ctx.has_previous do return false
	if _, has_value := has_keyword(object, ctx, "@value"); has_value do return false
	if len(object) != 1 do return true
	_, has_id := has_keyword(object, ctx, "@id")
	return !has_id
}

@(private) expand_apply_type_scoped_contexts :: proc(state: ^State, current: ^Context, object: json.Object) -> (Context, Expand_Error) {
	result := current^
	type_context := current^
	for key, value in object {
		if keyword_for(&type_context, key) != "@type" do continue
		types, is_array := array_from_value(value)
		count := is_array ? len(types) : 1
		// Type-scoped contexts are applied in reverse type order. This lets the
		// first compacted type term govern properties when several scopes define
		// the same term.
		for index := count - 1; index >= 0; index -= 1 {
			type_name, valid := string_value(is_array ? types[index] : value)
			if !valid {
				if state.retain_frame_controls do continue
				return {}, .Invalid_IRI
			}
			definition, found := type_context.terms[type_name]
			if !found || !definition.has_local_context do continue
			updated, context_err := apply_term_scoped_context(state, &result, definition)
			if context_err.code != .None do return {}, expand_from_parse_error(context_err)
			result = updated
		}
	}
	return result, .None
}

// expand_resolve_object_base_context applies rollback, property-scoped, and
// local contexts without applying type-scoped contexts. Type identifiers are
// expanded against exactly this context, while node properties use the
// type-scoped context derived from it.
@(private) expand_resolve_object_base_context :: proc(state: ^State, current: ^Context, definition: Term_Definition, object: json.Object, from_map := false) -> (Context, Expand_Error) {
	result := current^
	if !from_map && expand_rolls_back_context(&result, object) do result = previous_context(&result)
	if definition.has_local_context {
		updated, context_err := apply_term_scoped_context(state, &result, definition, true, true)
		if context_err.code != .None do return {}, expand_from_parse_error(context_err)
		result = updated
	}
	if context_value, has_context := object_value(object, "@context"); has_context {
		updated, context_err := expand_apply_local_context(state, &result, context_value)
		if context_err != .None do return {}, context_err
		result = updated
	}
	return result, .None
}

// Resolves the context which governs an object value. A non-propagated context
// rolls back at each newly entered node object, before property-, local-, and
// type-scoped contexts are applied. Callers expanding an @id/@type map pass
// from_map to keep the map's deliberately selected context.
@(private) expand_resolve_object_context :: proc(state: ^State, current: ^Context, definition: Term_Definition, object: json.Object, from_map := false) -> (Context, Expand_Error) {
	base, base_err := expand_resolve_object_base_context(state, current, definition, object, from_map)
	if base_err != .None do return {}, base_err
	return expand_apply_type_scoped_contexts(state, &base, object)
}

@(private) expand_write_identifier :: proc(builder: ^strings.Builder, state: ^State, ctx: ^Context, value: json.Value, vocab: bool) -> Expand_Error {
	text, valid := string_value(value)
	if !valid do return .Invalid_IRI
	expanded, err := expand_iri(state, ctx, text, vocab, true)
	if err.code != .None do return expand_from_parse_error(err)
	write_json_string(builder, expanded)
	return .None
}

// expand_iri uses an empty string to signal a keyword-shaped value that JSON-LD
// must ignore. Expanded JSON-LD represents that absent identifier as null.
@(private) expand_write_identifier_value :: proc(builder: ^strings.Builder, identifier: string) {
	if len(identifier) == 0 {
		strings.write_string(builder, "null")
	} else {
		write_json_string(builder, identifier)
	}
}

@(private) expand_write_primitive :: proc(builder: ^strings.Builder, state: ^State, ctx: ^Context, definition: Term_Definition, value: json.Value) -> Expand_Error {
	// Property-scoped contexts apply to scalar values as well as object values.
	// In particular, @id and @vocab coercion must resolve against the scoped
	// base/vocabulary (W3C c023/c024).
	active_context := ctx^
	if definition.has_local_context {
		updated, context_err := apply_term_scoped_context(state, &active_context, definition, true, true)
		if context_err.code != .None do return expand_from_parse_error(context_err)
		active_context = updated
	}
	if definition.type == "@id" || definition.type == "@vocab" {
		text, valid := string_value(value)
		if valid {
			expanded := ""
		iri_error: Parse_Error
		if definition.type == "@id" {
			expanded, iri_error = expand_identifier_iri(state, &active_context, text)
		} else {
			expanded, iri_error = expand_iri(state, &active_context, text, true, true)
			}
			if iri_error.code != .None do return expand_from_parse_error(iri_error)
			strings.write_string(builder, `{"@id": `)
			expand_write_identifier_value(builder, expanded)
			strings.write_byte(builder, '}')
			return .None
		}
		// Native values do not become node identifiers merely because the term
		// carries @id or @vocab coercion; they remain ordinary value objects.
		strings.write_string(builder, `{"@value": `)
		if !compact_write_raw_json(builder, value) do return .Invalid_Value_Object
		strings.write_byte(builder, '}')
		return .None
	}
	strings.write_string(builder, `{"@value": `)
	if !compact_write_raw_json(builder, value) do return .Invalid_Value_Object
	if len(definition.type) > 0 && definition.type != "@none" {
		strings.write_string(builder, `, "@type": `)
		write_json_string(builder, definition.type)
	} else if text, is_string := string_value(value); is_string {
		_ = text
		if definition.has_language {
			strings.write_string(builder, `, "@language": `)
			write_json_string(builder, definition.language)
		} else if !definition.language_null && active_context.has_language {
			strings.write_string(builder, `, "@language": `)
			write_json_string(builder, active_context.language)
		}
		if definition.has_direction {
			strings.write_string(builder, `, "@direction": `)
			write_json_string(builder, definition.direction)
		} else if !definition.direction_null && active_context.has_direction {
			strings.write_string(builder, `, "@direction": `)
			write_json_string(builder, active_context.direction)
		}
	}
	strings.write_byte(builder, '}')
	return .None
}

@(private) expand_write_value_object :: proc(builder: ^strings.Builder, state: ^State, ctx: ^Context, object: json.Object) -> (bool, Expand_Error) {
	value, has_value := has_keyword(object, ctx, "@value")
	if !has_value do return false, .Invalid_Value_Object
	for key in object {
		keyword := keyword_for(ctx, key)
		if keyword != "@value" && keyword != "@type" && keyword != "@language" && keyword != "@direction" && keyword != "@index" do return false, .Invalid_Value_Object
	}
	type_value, has_type := has_keyword(object, ctx, "@type")
	language_value, has_language := has_keyword(object, ctx, "@language")
	if !state.retain_frame_controls {
		if has_type && has_language do return false, .Invalid_Value_Object
		if _, value_is_array := array_from_value(value); value_is_array {
			type_name, type_is_string := string_value(type_value)
			if !has_type || !type_is_string || (type_name != "@json" && keyword_for(ctx, type_name) != "@json") do return false, .Invalid_Value_Object
		}
	}
	#partial switch _ in value {
	case json.Null:
		if has_type {
			type_name, valid_type := string_value(type_value)
			if valid_type && (type_name == "@json" || keyword_for(ctx, type_name) == "@json") {
				strings.write_string(builder, `{"@value": null, "@type": "@json"}`)
				return true, .None
			}
		}
		return false, .None
	}
	direction_value, has_direction := has_keyword(object, ctx, "@direction")
	if has_direction && !state.retain_frame_controls {
		if has_type do return false, .Invalid_Value_Object
		direction, valid := string_value(direction_value)
		if !valid || (direction != "ltr" && direction != "rtl") do return false, .Invalid_Value_Object
	}
	if has_language && !state.retain_frame_controls {
		if _, value_is_string := string_value(value); !value_is_string do return false, .Invalid_Value_Object
	}
	strings.write_string(builder, `{"@value": `)
	if !compact_write_raw_json(builder, value) do return false, .Invalid_Value_Object
	if has_language {
		if language_object, is_object := object_from_value(language_value); state.retain_frame_controls && is_object {
			strings.write_string(builder, `, "@language": `)
			if !compact_write_raw_json(builder, language_object) do return false, .Invalid_Value_Object
		} else if language_array, is_array := array_from_value(language_value); state.retain_frame_controls && is_array {
			strings.write_string(builder, `, "@language": `)
			if !compact_write_raw_json(builder, language_array) do return false, .Invalid_Value_Object
		} else {
			language, valid := string_value(language_value)
			if !valid do return false, .Invalid_Value_Object
			strings.write_string(builder, `, "@language": `)
			lowercase := strings.to_lower(language)
			write_json_string(builder, lowercase)
			delete(lowercase)
		}
	} else if has_type {
		strings.write_string(builder, `, "@type": `)
		if type_object, is_object := object_from_value(type_value); state.retain_frame_controls && is_object {
			if !compact_write_raw_json(builder, type_object) do return false, .Invalid_Value_Object
		} else if type_array, is_array := array_from_value(type_value); state.retain_frame_controls && is_array {
			strings.write_byte(builder, '[')
			for item, index in type_array {
				if index > 0 do strings.write_string(builder, ", ")
				type_name, valid := string_value(item)
				if !valid do return false, .Invalid_Value_Object
				expanded, err := expand_iri(state, ctx, type_name, true, true)
				if err.code != .None do return false, expand_from_parse_error(err)
				if !valid_absolute_iri(expanded) do return false, .Invalid_Value_Object
				expand_write_identifier_value(builder, expanded)
			}
			strings.write_byte(builder, ']')
		} else {
			type_name, valid := string_value(type_value)
			if !valid do return false, .Invalid_Value_Object
			if type_name == "@json" || keyword_for(ctx, type_name) == "@json" {
				write_json_string(builder, "@json")
			} else {
				expanded, err := expand_iri(state, ctx, type_name, true, true)
				if err.code != .None do return false, expand_from_parse_error(err)
				if !valid_absolute_iri(expanded) do return false, .Invalid_Value_Object
				write_json_string(builder, expanded)
			}
		}
	}
	if has_direction {
		direction, _ := string_value(direction_value)
		strings.write_string(builder, `, "@direction": `)
		write_json_string(builder, direction == "ltr" ? "ltr" : "rtl")
	}
	if index_value, has_index := has_keyword(object, ctx, "@index"); has_index {
		index, valid := string_value(index_value)
		if !valid do return false, .Invalid_Value_Object
		strings.write_string(builder, `, "@index": `)
		write_json_string(builder, index)
	}
	strings.write_byte(builder, '}')
	return true, .None
}

@(private) expand_validate_list_values :: proc(state: ^State, expanded: string) -> Expand_Error {
	// JSON-LD 1.1 permits a list to contain another list; 1.0 does not.
	if state.allow_document_containers do return .None
	parsed, json_err := json.parse_string(expanded, .JSON, true)
	if json_err != .None do return .Invalid_List_Object
	defer json.destroy_value(parsed)
	values, valid := array_from_value(parsed)
	if !valid do return .Invalid_List_Object
	for item in values {
		object, is_object := object_from_value(item)
		if !is_object do continue
		if _, has_list := object_value(object, "@list"); has_list do return .Invalid_List_Object
	}
	return .None
}

@(private) expand_validate_list_object :: proc(ctx: ^Context, object: json.Object) -> Expand_Error {
	for key in object {
		if key == "@context" do continue
		keyword := keyword_for(ctx, key)
		if keyword != "@list" && keyword != "@index" do return .Invalid_List_Object
	}
	return .None
}

@(private) expand_write_list :: proc(builder: ^strings.Builder, state: ^State, ctx: ^Context, definition: Term_Definition, value: json.Value) -> Expand_Error {
	temporary := strings.builder_make()
	defer strings.builder_destroy(&temporary)
	if err := expand_write_values(&temporary, state, ctx, definition, value); err != .None do return err
	if err := expand_validate_list_values(state, strings.to_string(temporary)); err != .None do return err
	strings.write_string(builder, `{"@list": `)
	strings.write_string(builder, strings.to_string(temporary))
	strings.write_byte(builder, '}')
	return .None
}

// List containers preserve each nested source array as a nested @list. The
// generic value writer intentionally flattens arrays for ordinary properties,
// so it cannot be used directly for this JSON-LD-specific shape.
@(private) expand_write_list_container_item :: proc(builder: ^strings.Builder, state: ^State, ctx: ^Context, definition: Term_Definition, value: json.Value, first: ^bool) -> Expand_Error {
	if array, is_array := array_from_value(value); is_array {
		if !first^ do strings.write_string(builder, ", ")
		strings.write_string(builder, `{"@list": [`)
		nested_first := true
		for item in array {
			if err := expand_write_list_container_item(builder, state, ctx, definition, item, &nested_first); err != .None do return err
		}
		strings.write_string(builder, "]}")
		first^ = false
		return .None
	}
	return expand_write_values_item(builder, state, ctx, definition, value, first)
}

@(private) expand_write_list_container_values :: proc(builder: ^strings.Builder, state: ^State, ctx: ^Context, definition: Term_Definition, value: json.Value) -> Expand_Error {
	strings.write_byte(builder, '[')
	first := true
	if array, is_array := array_from_value(value); is_array {
		for item in array {
			if err := expand_write_list_container_item(builder, state, ctx, definition, item, &first); err != .None do return err
		}
	} else if err := expand_write_list_container_item(builder, state, ctx, definition, value, &first); err != .None do return err
	strings.write_byte(builder, ']')
	return .None
}

@(private) expand_validate_list_container_values :: proc(state: ^State, ctx: ^Context, definition: Term_Definition, value: json.Value) -> Expand_Error {
	if state.allow_document_containers || definition.type == "@json" do return .None
	if values, is_array := array_from_value(value); is_array {
		for item in values {
			if err := expand_validate_list_container_values(state, ctx, definition, item); err != .None do return err
		}
		return .None
	}
	object, is_object := object_from_value(value)
	if !is_object do return .None
	if _, has_list := has_keyword(object, ctx, "@list"); has_list do return .Invalid_List_Object
	return .None
}

@(private) expand_write_values_item :: proc(builder: ^strings.Builder, state: ^State, ctx: ^Context, definition: Term_Definition, value: json.Value, first: ^bool) -> Expand_Error {
	// @json coercion applies to the complete JSON value, including arrays and
	// null, before ordinary property-array expansion can flatten or elide it.
	if definition.type == "@json" {
		temporary := strings.builder_make()
		defer strings.builder_destroy(&temporary)
		written, err := expand_write_single(&temporary, state, ctx, definition, value, true)
		if err != .None || !written do return err
		if !first^ do strings.write_string(builder, ", ")
		strings.write_string(builder, strings.to_string(temporary))
		first^ = false
		return .None
	}
	if array, is_array := array_from_value(value); is_array {
		for item in array {
			if err := expand_write_values_item(builder, state, ctx, definition, item, first); err != .None do return err
		}
		return .None
	}
	if object, is_object := object_from_value(value); is_object {
		active, context_err := expand_resolve_object_context(state, ctx, definition, object)
		if context_err != .None do return context_err
		if set_value, has_set := has_keyword(object, &active, "@set"); has_set {
			return expand_write_values_item(builder, state, &active, definition, set_value, first)
		}
		temporary := strings.builder_make()
		defer strings.builder_destroy(&temporary)
		written, err := expand_write_single_resolved(&temporary, state, &active, definition, value, true)
		if err != .None || !written do return err
		if !first^ do strings.write_string(builder, ", ")
		strings.write_string(builder, strings.to_string(temporary))
		first^ = false
		return .None
	}
	temporary := strings.builder_make()
	defer strings.builder_destroy(&temporary)
	written, err := expand_write_single(&temporary, state, ctx, definition, value, true)
	if err != .None || !written do return err
	if !first^ do strings.write_string(builder, ", ")
	strings.write_string(builder, strings.to_string(temporary))
	first^ = false
	return .None
}

@(private) expand_write_values :: proc(builder: ^strings.Builder, state: ^State, ctx: ^Context, definition: Term_Definition, value: json.Value) -> Expand_Error {
	strings.write_byte(builder, '[')
	first := true
	if err := expand_write_values_item(builder, state, ctx, definition, value, &first); err != .None do return err
	strings.write_byte(builder, ']')
	return .None
}

// A reverse property may only point at node objects. Validate the fully
// expanded values so @id/@vocab coercion remains valid while value and list
// objects are rejected (JSON-LD expansion algorithm, reverse-property step).
@(private) expand_validate_reverse_values :: proc(expanded: string) -> Expand_Error {
	parsed, json_err := json.parse_string(expanded, .JSON, true)
	if json_err != .None do return .Invalid_Reverse_Property
	defer json.destroy_value(parsed)
	values, valid := array_from_value(parsed)
	if !valid do return .Invalid_Reverse_Property
	for item in values {
		object, is_object := object_from_value(item)
		if !is_object do return .Invalid_Reverse_Property
		if _, has_value := object_value(object, "@value"); has_value do return .Invalid_Reverse_Property
		if _, has_list := object_value(object, "@list"); has_list do return .Invalid_Reverse_Property
	}
	return .None
}

@(private) expand_validate_included_values :: proc(ctx: ^Context, value: json.Value) -> Expand_Error {
	if values, is_array := array_from_value(value); is_array {
		for item in values {
			if err := expand_validate_included_values(ctx, item); err != .None do return err
		}
		return .None
	}
	object, valid := object_from_value(value)
	if !valid do return .Invalid_Value_Object
	if _, has_value := has_keyword(object, ctx, "@value"); has_value do return .Invalid_Value_Object
	if _, has_list := has_keyword(object, ctx, "@list"); has_list do return .Invalid_Value_Object
	return .None
}

// Keyword aliases are separate source members but one expanded keyword. Merge
// their expanded values before serializing so ordinary JSON object semantics
// cannot discard every member except the last alias.
@(private) expand_write_keyword_alias_values :: proc(builder: ^strings.Builder, state: ^State, ctx: ^Context, object: json.Object, keys: []string, keyword: string) -> Expand_Error {
	strings.write_byte(builder, '[')
	first := true
	for key in keys {
		if keyword_for(ctx, key) != keyword do continue
		if keyword == "@included" {
			if err := expand_validate_included_values(ctx, object[key]); err != .None do return err
		}
		if err := expand_write_values_item(builder, state, ctx, {}, object[key], &first); err != .None do return err
	}
	strings.write_byte(builder, ']')
	return .None
}

@(private) expand_is_none_key :: proc(ctx: ^Context, value: string) -> bool {
	return value == "@none" || keyword_for(ctx, value) == "@none"
}

@(private) expand_write_language_map :: proc(builder: ^strings.Builder, state: ^State, ctx: ^Context, definition: Term_Definition, value: json.Value) -> Expand_Error {
	object, valid := object_from_value(value)
	if !valid do return .Invalid_Value_Object
	strings.write_byte(builder, '[')
	first := true
	keys := expand_sorted_keys(object)
	defer delete(keys)
	for language in keys {
		mapped := object[language]
		values, is_array := array_from_value(mapped)
		count := is_array ? len(values) : 1
		for index in 0..<count {
			item := is_array ? values[index] : mapped
			#partial switch _ in item { case json.Null: continue }
			if _, is_string := string_value(item); !is_string do return .Invalid_Value_Object
			if !first do strings.write_string(builder, ", ")
			mapped_definition := definition
			none_key := expand_is_none_key(ctx, language)
			mapped_definition.has_language = !none_key
			mapped_definition.language_null = none_key
			if mapped_definition.has_language {
				lowercase := strings.to_lower(language)
				mapped_definition.language, _ = own(state, lowercase)
				delete(lowercase)
			}
			if err := expand_write_primitive(builder, state, ctx, mapped_definition, item); err != .None do return err
			first = false
		}
	}
	strings.write_byte(builder, ']')
	return .None
}

// A custom @index property is ordinary expanded data. When the mapped object
// already supplies that property, the map key is prepended to its values
// instead of being emitted as a duplicate JSON member (whose last occurrence
// would silently discard the source values in ordinary JSON parsers).
@(private) expand_write_object_with_custom_index :: proc(builder: ^strings.Builder, expanded, index_property, index_values: string) -> Expand_Error {
	parsed, json_err := json.parse_string(expanded, .JSON, true)
	if json_err != .None do return .Invalid_Value_Object
	defer json.destroy_value(parsed)
	object, valid := object_from_value(parsed)
	if !valid do return .Invalid_Value_Object
	if _, is_value := object_value(object, "@value"); is_value do return .Invalid_Value_Object
	strings.write_byte(builder, '{')
	first := true
	found_index := false
	keys := expand_sorted_keys(object)
	defer delete(keys)
	for key in keys {
		expand_write_member_prefix(builder, &first, key)
		if key != index_property {
			if !compact_write_raw_json(builder, object[key]) do return .Invalid_Value_Object
			continue
		}
		found_index = true
		existing, is_array := array_from_value(object[key])
		if !is_array || len(index_values) < 2 do return .Invalid_Value_Object
		strings.write_byte(builder, '[')
		strings.write_string(builder, index_values[1:len(index_values) - 1])
		for item in existing {
			strings.write_string(builder, ", ")
			if !compact_write_raw_json(builder, item) do return .Invalid_Value_Object
		}
		strings.write_byte(builder, ']')
	}
	if !found_index {
		expand_write_member_prefix(builder, &first, index_property)
		strings.write_string(builder, index_values)
	}
	strings.write_byte(builder, '}')
	return .None
}

@(private) expand_write_indexed_item :: proc(builder: ^strings.Builder, state: ^State, ctx: ^Context, definition: Term_Definition, index_key: string, value: json.Value, first: ^bool) -> Expand_Error {
	if array, is_array := array_from_value(value); is_array {
		for item in array {
			if err := expand_write_indexed_item(builder, state, ctx, definition, index_key, item, first); err != .None do return err
		}
		return .None
	}
	if object, is_object := object_from_value(value); is_object {
		// An index-map entry stays in the context selected by its containing
		// map. In particular, a type-map's scoped context must not roll back
		// before expanding nested index-map values (W3C c013).
		active, context_err := expand_resolve_object_context(state, ctx, definition, object, true)
		if context_err != .None do return context_err
		if set_value, has_set := has_keyword(object, &active, "@set"); has_set do return expand_write_indexed_item(builder, state, &active, definition, index_key, set_value, first)
		temporary := strings.builder_make()
		defer strings.builder_destroy(&temporary)
		written, err := expand_write_single_resolved(&temporary, state, &active, definition, value, true)
		if err != .None || !written do return err
		expanded := strings.to_string(temporary)
		explicit_index := false
		_, explicit_index = has_keyword(object, ctx, "@index")
		if !explicit_index && !expand_is_none_key(ctx, index_key) && definition.has_index && definition.index != "@index" {
			index_definition, found_definition := context_definition_for_iri(ctx, definition.index)
			if !found_definition do index_definition = {}
			index_values := strings.builder_make()
			defer strings.builder_destroy(&index_values)
			if index_error := expand_write_values(&index_values, state, ctx, index_definition, json.String(index_key)); index_error != .None do return index_error
			if !first^ do strings.write_string(builder, ", ")
			if index_error := expand_write_object_with_custom_index(builder, expanded, definition.index, strings.to_string(index_values)); index_error != .None do return index_error
			first^ = false
			return .None
		}
		if !first^ do strings.write_string(builder, ", ")
		strings.write_string(builder, expanded[:len(expanded) - 1])
		if !explicit_index && !expand_is_none_key(ctx, index_key) {
			if len(expanded) > 2 do strings.write_string(builder, ", ")
			if definition.has_index && definition.index != "@index" {
				index_definition, found_definition := context_definition_for_iri(ctx, definition.index)
				if !found_definition do index_definition = {}
				index_values := strings.builder_make()
				defer strings.builder_destroy(&index_values)
				if index_error := expand_write_values(&index_values, state, ctx, index_definition, json.String(index_key)); index_error != .None do return index_error
				write_json_string(builder, definition.index)
				strings.write_string(builder, ": ")
				strings.write_string(builder, strings.to_string(index_values))
			} else {
				write_json_string(builder, "@index")
				strings.write_string(builder, ": ")
				write_json_string(builder, index_key)
			}
		}
		strings.write_byte(builder, '}')
		first^ = false
		return .None
	}
	temporary := strings.builder_make()
	defer strings.builder_destroy(&temporary)
	written, err := expand_write_single(&temporary, state, ctx, definition, value, true)
	if err != .None || !written do return err
	expanded := strings.to_string(temporary)
	explicit_index := false
	if !explicit_index && !expand_is_none_key(ctx, index_key) && definition.has_index && definition.index != "@index" {
		index_definition, found_definition := context_definition_for_iri(ctx, definition.index)
		if !found_definition do index_definition = {}
		index_values := strings.builder_make()
		defer strings.builder_destroy(&index_values)
		if index_error := expand_write_values(&index_values, state, ctx, index_definition, json.String(index_key)); index_error != .None do return index_error
		if !first^ do strings.write_string(builder, ", ")
		if index_error := expand_write_object_with_custom_index(builder, expanded, definition.index, strings.to_string(index_values)); index_error != .None do return index_error
		first^ = false
		return .None
	}
	if !first^ do strings.write_string(builder, ", ")
	strings.write_string(builder, expanded[:len(expanded) - 1])
	if !explicit_index && !expand_is_none_key(ctx, index_key) {
		if len(expanded) > 2 do strings.write_string(builder, ", ")
		if definition.has_index && definition.index != "@index" {
			index_definition, found_definition := context_definition_for_iri(ctx, definition.index)
			if !found_definition do index_definition = {}
			index_values := strings.builder_make()
			defer strings.builder_destroy(&index_values)
			if index_error := expand_write_values(&index_values, state, ctx, index_definition, json.String(index_key)); index_error != .None do return index_error
			write_json_string(builder, definition.index)
			strings.write_string(builder, ": ")
			strings.write_string(builder, strings.to_string(index_values))
		} else {
			write_json_string(builder, "@index")
			strings.write_string(builder, ": ")
			write_json_string(builder, index_key)
		}
	}
	strings.write_byte(builder, '}')
	first^ = false
	return .None
}

@(private) expand_write_index_map :: proc(builder: ^strings.Builder, state: ^State, ctx: ^Context, definition: Term_Definition, value: json.Value) -> Expand_Error {
	object, valid := object_from_value(value)
	if !valid do return .Invalid_Value_Object
	strings.write_byte(builder, '[')
	first := true
	keys := expand_sorted_keys(object)
	defer delete(keys)
	for key in keys {
		if err := expand_write_indexed_item(builder, state, ctx, definition, key, object[key], &first); err != .None do return err
	}
	strings.write_byte(builder, ']')
	return .None
}

@(private) Expand_Property :: struct {
	key:   string,
	value: string,
}

@(private) expand_destroy_properties :: proc(properties: ^[dynamic]Expand_Property) {
	for property in properties^ {
		delete(property.key)
		delete(property.value)
	}
	delete(properties^)
}

@(private) expand_sort_properties :: proc(properties: ^[dynamic]Expand_Property) {
	sort.sort(sort.Interface{
		collection = rawptr(properties),
		len = proc(it: sort.Interface) -> int { return len((cast(^[dynamic]Expand_Property)it.collection)^) },
		less = proc(it: sort.Interface, i, j: int) -> bool {
			properties := cast(^[dynamic]Expand_Property)it.collection
			return strings.compare(properties[i].key, properties[j].key) < 0
		},
		swap = proc(it: sort.Interface, i, j: int) {
			properties := cast(^[dynamic]Expand_Property)it.collection
			properties[i], properties[j] = properties[j], properties[i]
		},
	})
}

@(private) expand_append_property :: proc(properties: ^[dynamic]Expand_Property, key, value: string) -> Expand_Error {
	for &property in properties {
		if property.key != key do continue
		merged := strings.builder_make()
		strings.write_string(&merged, property.value[:len(property.value) - 1])
		if len(property.value) > 2 && len(value) > 2 do strings.write_string(&merged, ", ")
		if len(value) > 2 {
			strings.write_string(&merged, value[1:len(value)])
		} else {
			strings.write_byte(&merged, ']')
		}
		copy, clone_error := strings.clone(strings.to_string(merged))
		strings.builder_destroy(&merged)
		if clone_error != nil do return .Out_Of_Memory
		delete(property.value)
		property.value = copy
		return .None
	}
	key_copy, key_error := strings.clone(key)
	if key_error != nil do return .Out_Of_Memory
	value_copy, value_error := strings.clone(value)
	if value_error != nil {
		delete(key_copy)
		return .Out_Of_Memory
	}
	append(properties, Expand_Property{key = key_copy, value = value_copy})
	return .None
}

@(private) expand_append_types :: proc(state: ^State, ctx: ^Context, properties: ^[dynamic]Expand_Property, value: json.Value) -> Expand_Error {
	temporary := strings.builder_make()
	defer strings.builder_destroy(&temporary)
	strings.write_byte(&temporary, '[')
	first := true
	types, is_array := array_from_value(value)
	count := is_array ? len(types) : 1
	for index in 0..<count {
		item := is_array ? types[index] : value
		name, valid := string_value(item)
		if !valid do return .Invalid_IRI
		expanded, err := expand_iri(state, ctx, name, true, true)
		if err.code != .None do return expand_from_parse_error(err)
		if !first do strings.write_string(&temporary, ", ")
		write_json_string(&temporary, expanded)
		first = false
	}
	strings.write_byte(&temporary, ']')
	return expand_append_property(properties, "@type", strings.to_string(temporary))
}

// Framing retains type maps so @default can supply a type for an otherwise
// untyped match. The map structure is framing control data, but its default
// type value still has to be expanded before it is copied into the expanded
// frame and later compacted into the result.
@(private) expand_write_frame_type_map :: proc(builder: ^strings.Builder, state: ^State, ctx: ^Context, value: json.Value) -> Expand_Error {
	type_map, valid := object_from_value(value)
	if !valid do return .Invalid_Value_Object
	keys := expand_sorted_keys(type_map)
	defer delete(keys)
	strings.write_byte(builder, '{')
	first := true
	for key in keys {
		if !first do strings.write_string(builder, ", ")
		write_json_string(builder, key)
		strings.write_string(builder, ": ")
		map_value := type_map[key]
		if key == "@default" {
			types, is_array := array_from_value(map_value)
			count := is_array ? len(types) : 1
			if is_array do strings.write_byte(builder, '[')
			for index in 0..<count {
				if index > 0 do strings.write_string(builder, ", ")
				item := is_array ? types[index] : map_value
				type_name, type_valid := string_value(item)
				if !type_valid do return .Invalid_Value_Object
				expanded, expand_error := expand_iri(state, ctx, type_name, true, true)
				if expand_error.code != .None do return expand_from_parse_error(expand_error)
				write_json_string(builder, expanded)
			}
			if is_array do strings.write_byte(builder, ']')
		} else if !compact_write_raw_json(builder, map_value) do return .Invalid_Value_Object
		first = false
	}
	strings.write_byte(builder, '}')
	return .None
}

@(private) expand_write_graph_item :: proc(builder: ^strings.Builder, state: ^State, ctx: ^Context, definition: Term_Definition, value: json.Value, map_key: string) -> Expand_Error {
	strings.write_string(builder, `{"@graph": `)
	// A graph container adds its map-key metadata to an existing graph object;
	// it must not wrap that object's @graph member in a second graph object.
	if object, is_object := object_from_value(value); is_object {
		active, context_err := expand_resolve_object_context(state, ctx, definition, object)
		if context_err != .None do return context_err
		if graph_value, has_graph := has_keyword(object, &active, "@graph"); has_graph && (definition.container_index || definition.container_id) {
			if err := expand_write_values(builder, state, &active, {}, graph_value); err != .None do return err
		} else {
			if err := expand_write_values(builder, state, ctx, definition, value); err != .None do return err
		}
	} else {
		if err := expand_write_values(builder, state, ctx, definition, value); err != .None do return err
	}
	if definition.container_id && !expand_is_none_key(ctx, map_key) {
		id, iri_err := expand_iri(state, ctx, map_key, false, true)
		if iri_err.code != .None do return expand_from_parse_error(iri_err)
		strings.write_string(builder, `, "@id": `)
		write_json_string(builder, id)
	} else if definition.container_index && !expand_is_none_key(ctx, map_key) {
		if definition.has_index && definition.index != "@index" {
			index_definition, found_definition := context_definition_for_iri(ctx, definition.index)
			if !found_definition do index_definition = {}
			index_values := strings.builder_make()
			defer strings.builder_destroy(&index_values)
			if index_error := expand_write_values(&index_values, state, ctx, index_definition, json.String(map_key)); index_error != .None do return index_error
			strings.write_string(builder, ", ")
			write_json_string(builder, definition.index)
			strings.write_string(builder, ": ")
			strings.write_string(builder, strings.to_string(index_values))
		} else {
			strings.write_string(builder, `, "@index": `)
			write_json_string(builder, map_key)
		}
	}
	strings.write_byte(builder, '}')
	return .None
}

@(private) expand_write_graph_container :: proc(builder: ^strings.Builder, state: ^State, ctx: ^Context, definition: Term_Definition, value: json.Value) -> Expand_Error {
	strings.write_byte(builder, '[')
	first := true
	if definition.container_index || definition.container_id {
		entries, valid := object_from_value(value)
		if !valid do return .Invalid_Value_Object
		keys := expand_sorted_keys(entries)
		defer delete(keys)
		for key in keys {
			values, is_array := array_from_value(entries[key])
			count := is_array ? len(values) : 1
			for value_index in 0..<count {
				if !first do strings.write_string(builder, ", ")
				item := is_array ? values[value_index] : entries[key]
				if err := expand_write_graph_item(builder, state, ctx, definition, item, key); err != .None do return err
				first = false
			}
		}
	} else {
		values, is_array := array_from_value(value)
		count := is_array ? len(values) : 1
		for index in 0..<count {
			if !first do strings.write_string(builder, ", ")
			item := is_array ? values[index] : value
			if err := expand_write_graph_item(builder, state, ctx, definition, item, "@none"); err != .None do return err
			first = false
		}
	}
	strings.write_byte(builder, ']')
	return .None
}

@(private) expand_write_id_type_map_item :: proc(builder: ^strings.Builder, state: ^State, ctx: ^Context, definition: Term_Definition, map_key: string, value: json.Value) -> Expand_Error {
	map_context := ctx^
	if map_context.has_previous do map_context = previous_context(&map_context)
	if definition.container_type {
		if type_definition, found := ctx.terms[map_key]; found && type_definition.has_local_context {
			updated, context_err := apply_term_scoped_context(state, &map_context, type_definition)
			if context_err.code != .None do return expand_from_parse_error(context_err)
			map_context = updated
		}
	}
	none_key := expand_is_none_key(ctx, map_key)
	if definition.container_type {
		if text, is_string := string_value(value); is_string {
			if len(definition.type) > 0 && definition.type != "@id" && definition.type != "@vocab" do return .Invalid_Value_Object
			identifier, iri_err := expand_iri(state, &map_context, text, definition.type == "@vocab", true)
			if iri_err.code != .None do return expand_from_parse_error(iri_err)
			strings.write_string(builder, `{"@id": `)
			write_json_string(builder, identifier)
			if !none_key {
				injected_type, type_err := expand_iri(state, ctx, map_key, true, true)
				if type_err.code != .None do return expand_from_parse_error(type_err)
				strings.write_string(builder, `, "@type": [`)
				write_json_string(builder, injected_type)
				strings.write_byte(builder, ']')
			}
			strings.write_byte(builder, '}')
			return .None
		}
	}
	temporary := strings.builder_make()
	written, value_err := expand_write_single(&temporary, state, &map_context, definition, value, true, true)
	if value_err != .None || !written { strings.builder_destroy(&temporary); return value_err }
	parsed, json_err := json.parse_string(strings.to_string(temporary), .JSON, true)
	strings.builder_destroy(&temporary)
	if json_err != .None do return .Invalid_Value_Object
	defer json.destroy_value(parsed)
	object, valid := object_from_value(parsed)
	if !valid do return .Invalid_Value_Object
	injected_id := ""
	injected_type := ""
	if definition.container_id && !none_key {
		expanded, iri_err := expand_iri(state, ctx, map_key, false, true)
		if iri_err.code != .None do return expand_from_parse_error(iri_err)
		injected_id = expanded
	} else if definition.container_type && !none_key {
		expanded, iri_err := expand_iri(state, ctx, map_key, true, true)
		if iri_err.code != .None do return expand_from_parse_error(iri_err)
		injected_type = expanded
	}
	strings.write_byte(builder, '{')
	first := true
	if len(injected_type) > 0 {
		expand_write_member_prefix(builder, &first, "@type")
		strings.write_byte(builder, '[')
		write_json_string(builder, injected_type)
		if existing, has_type := object_value(object, "@type"); has_type {
			items, is_array := array_from_value(existing)
			if !is_array do return .Invalid_Value_Object
			for item in items {
				strings.write_string(builder, ", ")
				if !compact_write_raw_json(builder, item) do return .Invalid_Value_Object
			}
		}
		strings.write_byte(builder, ']')
	}
	keys := expand_sorted_keys(object)
	defer delete(keys)
	for key in keys {
		if key == "@type" && len(injected_type) > 0 do continue
		expand_write_member_prefix(builder, &first, key)
		if !compact_write_raw_json(builder, object[key]) do return .Invalid_Value_Object
	}
	if len(injected_id) > 0 {
		if _, has_id := object_value(object, "@id"); !has_id {
			expand_write_member_prefix(builder, &first, "@id")
			write_json_string(builder, injected_id)
		}
	}
	strings.write_byte(builder, '}')
	return .None
}

@(private) expand_write_id_type_container :: proc(builder: ^strings.Builder, state: ^State, ctx: ^Context, definition: Term_Definition, value: json.Value) -> Expand_Error {
	entries, valid := object_from_value(value)
	if !valid do return .Invalid_Value_Object
	strings.write_byte(builder, '[')
	first := true
	keys := expand_sorted_keys(entries)
	defer delete(keys)
	for key in keys {
		values, is_array := array_from_value(entries[key])
		count := is_array ? len(values) : 1
		for index in 0..<count {
			if !first do strings.write_string(builder, ", ")
			item := is_array ? values[index] : entries[key]
			if err := expand_write_id_type_map_item(builder, state, ctx, definition, key, item); err != .None do return err
			first = false
		}
	}
	strings.write_byte(builder, ']')
	return .None
}

@(private) expand_append_node_property :: proc(state: ^State, ctx: ^Context, properties, reverse_properties: ^[dynamic]Expand_Property, key: string, definition: Term_Definition, value: json.Value) -> Expand_Error {
	expanded_key, err := expand_iri(state, ctx, key, true, false)
	if err.code != .None do return expand_from_parse_error(err)
	if !has_iri_scheme(expanded_key) && !strings.has_prefix(expanded_key, "_:") do return .None
	temporary := strings.builder_make()
	value_err: Expand_Error
	_, map_value := object_from_value(value)
	if definition.container_graph {
		value_err = expand_write_graph_container(&temporary, state, ctx, definition, value)
	} else if definition.container_id || definition.container_type {
		value_err = expand_write_id_type_container(&temporary, state, ctx, definition, value)
	} else if definition.container_language && map_value {
		value_err = expand_write_language_map(&temporary, state, ctx, definition, value)
	} else if definition.container_index && map_value {
		value_err = expand_write_index_map(&temporary, state, ctx, definition, value)
	} else if definition.container_list {
		already_list := false
		if value_object, is_object := object_from_value(value); is_object {
			_, already_list = has_keyword(value_object, ctx, "@list")
		}
		if already_list {
			value_err = expand_write_values(&temporary, state, ctx, definition, value)
		} else {
			if list_err := expand_validate_list_container_values(state, ctx, definition, value); list_err != .None {
				strings.builder_destroy(&temporary)
				return list_err
			}
			strings.write_byte(&temporary, '[')
			strings.write_string(&temporary, `{"@list": `)
			value_err = expand_write_list_container_values(&temporary, state, ctx, definition, value)
			strings.write_string(&temporary, "}]")
		}
	} else {
		value_err = expand_write_values(&temporary, state, ctx, definition, value)
	}
	if value_err != .None { strings.builder_destroy(&temporary); return value_err }
	if definition.reverse {
		if reverse_err := expand_validate_reverse_values(strings.to_string(temporary)); reverse_err != .None {
			strings.builder_destroy(&temporary)
			return reverse_err
		}
	}
	drop_property := expand_is_null(value) && definition.type != "@json"
	if value_object, is_object := object_from_value(value); is_object {
		if expand_is_null_value_object(value_object, ctx) && !expand_is_json_value_object(value_object, ctx) do drop_property = true
		_, has_language := has_keyword(value_object, ctx, "@language")
		_, has_value := has_keyword(value_object, ctx, "@value")
		if has_language && !has_value && strings.to_string(temporary) == "[]" do drop_property = true
	}
	if drop_property {
		strings.builder_destroy(&temporary)
		return .None
	}
	target := properties
	if definition.reverse do target = reverse_properties
	append_err := expand_append_property(target, expanded_key, strings.to_string(temporary))
	strings.builder_destroy(&temporary)
	return append_err
}

@(private) expand_context_for_nest :: proc(state: ^State, current: ^Context, key: string) -> (Context, Expand_Error) {
	result := current^
	definition, found := current.terms[key]
	if !found || !definition.has_local_context do return result, .None
	updated, context_err := apply_term_scoped_context(state, &result, definition, true, true)
	if context_err.code != .None do return {}, expand_from_parse_error(context_err)
	return updated, .None
}

// expand_nested_identifier finds an @id supplied by a direct @nest member.
// Nesting is transparent for node properties, so that identifier belongs to
// the enclosing node rather than becoming an invalid nested keyword.
@(private) expand_nested_identifier :: proc(state: ^State, ctx: ^Context, object: json.Object) -> (json.Value, bool, Expand_Error) {
	for key, nested_value in object {
		if keyword_for(ctx, key) != "@nest" do continue
		nested_context, context_err := expand_context_for_nest(state, ctx, key)
		if context_err != .None do return {}, false, context_err
		values, array := array_from_value(nested_value)
		count := array ? len(values) : 1
		for index in 0..<count {
			nested := array ? values[index] : nested_value
			nested_object, valid := object_from_value(nested)
			if !valid do continue
			if id, found := has_keyword(nested_object, &nested_context, "@id"); found do return id, true, .None
		}
	}
	return {}, false, .None
}

@(private) expand_process_nest :: proc(state: ^State, ctx: ^Context, properties, reverse_properties: ^[dynamic]Expand_Property, value: json.Value) -> Expand_Error {
	if array, is_array := array_from_value(value); is_array {
		for item in array {
			if err := expand_process_nest(state, ctx, properties, reverse_properties, item); err != .None do return err
		}
		return .None
	}
	nested, valid := object_from_value(value)
	if !valid do return .Invalid_Value_Object
	keys := expand_sorted_keys(nested)
	defer delete(keys)
	for key in keys {
		keyword := keyword_for(ctx, key)
		if keyword == "@nest" do continue
		// The enclosing node has already consumed this transparent identifier.
		if keyword == "@id" do continue
		if keyword == "@type" {
			if err := expand_append_types(state, ctx, properties, nested[key]); err != .None do return err
			continue
		}
		if len(keyword) > 0 do return .Invalid_Value_Object
		definition := Term_Definition{}
		if found, ok := ctx.terms[key]; ok {
			if found.disabled do continue
			definition = found
		}
		if err := expand_append_node_property(state, ctx, properties, reverse_properties, key, definition, nested[key]); err != .None do return err
	}
	// Transparent nesting appends after ordinary sibling properties, regardless
	// of the lexical order of the nesting alias.
	for key in keys {
		if keyword_for(ctx, key) != "@nest" do continue
		nested_context, context_err := expand_context_for_nest(state, ctx, key)
		if context_err != .None do return context_err
		if err := expand_process_nest(state, &nested_context, properties, reverse_properties, nested[key]); err != .None do return err
	}
	return .None
}

@(private) expand_write_node_resolved :: proc(builder: ^strings.Builder, state: ^State, resolved: ^Context, object: json.Object, nested: bool, type_context: ^Context = nil) -> (bool, Expand_Error) {
	ctx := resolved^
	if _, has_value := has_keyword(object, &ctx, "@value"); has_value do return expand_write_value_object(builder, state, &ctx, object)
	if _, has_language := has_keyword(object, &ctx, "@language"); has_language do return false, .None
	if list_value, has_list := has_keyword(object, &ctx, "@list"); has_list {
		if err := expand_validate_list_object(&ctx, object); err != .None do return false, err
		if err := expand_write_list(builder, state, &ctx, {}, list_value); err != .None do return false, err
		return true, .None
	}
	strings.write_byte(builder, '{')
	first := true
	has_non_id := false
	keys := expand_sorted_keys(object)
	defer delete(keys)
	if state.retain_frame_controls {
		controls := [5]string{"@default", "@embed", "@explicit", "@omitDefault", "@requireAll"}
		for control in controls {
			if value, found := object_value(object, control); found {
				if control == "@default" {
					expand_write_member_prefix(builder, &first, control)
					if default_object, is_default_object := object_from_value(value); is_default_object {
						if _, has_value := has_keyword(default_object, &ctx, "@value"); has_value {
							written, default_error := expand_write_value_object(builder, state, &ctx, default_object)
							if default_error != .None || !written do return false, .Invalid_Value_Object
						} else if !compact_write_raw_json(builder, value) do return false, .Invalid_Value_Object
					} else if !compact_write_raw_json(builder, value) do return false, .Invalid_Value_Object
				} else if control == "@embed" {
					#partial switch _ in value {
					case json.Boolean, json.String:
						expand_write_member_prefix(builder, &first, control)
						if !compact_write_raw_json(builder, value) do return false, .Invalid_Value_Object
					case:
						return false, .Invalid_Value_Object
					}
				} else {
					#partial switch _ in value {
					case json.Boolean, json.String:
						expand_write_member_prefix(builder, &first, control)
						if !compact_write_raw_json(builder, value) do return false, .Invalid_Value_Object
					case:
						return false, .Invalid_Value_Object
					}
				}
			}
		}
	}
	properties := make([dynamic]Expand_Property)
	defer expand_destroy_properties(&properties)
	reverse_properties := make([dynamic]Expand_Property)
	defer expand_destroy_properties(&reverse_properties)
	identifier_members := 0
	for key in keys {
		if keyword_for(&ctx, key) != "@id" do continue
		identifier_members += 1
		if identifier_members > 1 do return false, .Invalid_IRI
	}
	id_value, has_id := has_keyword(object, &ctx, "@id")
	if !has_id {
		nested_id, nested_found, nested_error := expand_nested_identifier(state, &ctx, object)
		if nested_error != .None do return false, nested_error
		if nested_found {
			id_value = nested_id
			has_id = true
		}
	}
	if has_id {
		if ids, is_array := array_from_value(id_value); state.retain_frame_controls && is_array {
			expand_write_member_prefix(builder, &first, "@id")
			strings.write_byte(builder, '[')
			for item, index in ids {
				if index > 0 do strings.write_string(builder, ", ")
				id, valid := string_value(item)
				if !valid do return false, .Invalid_IRI
				expanded, err := expand_identifier_iri(state, &ctx, id)
				if err.code != .None do return false, expand_from_parse_error(err)
				write_json_string(builder, expanded)
			}
			strings.write_byte(builder, ']')
		} else if id_object, is_id_object := object_from_value(id_value); state.retain_frame_controls && is_id_object {
			expand_write_member_prefix(builder, &first, "@id")
			if !compact_write_raw_json(builder, id_object) do return false, .Invalid_Value_Object
		} else {
			id, valid := string_value(id_value)
			if !valid do return false, .Invalid_IRI
			expand_write_member_prefix(builder, &first, "@id")
			// With a null base, an explicit empty identifier remains an empty
			// identifier in expanded JSON-LD. It is distinct from a keyword-shaped
			// value that expansion intentionally omits (W3C flatten-0046).
			if len(id) == 0 && len(ctx.base_iri) == 0 {
				write_json_string(builder, id)
			} else {
				expanded, err := expand_identifier_iri(state, &ctx, id)
				if err.code != .None do return false, expand_from_parse_error(err)
				expand_write_identifier_value(builder, expanded)
			}
		}
	}
	for key in keys {
		if keyword_for(&ctx, key) != "@type" do continue
		type_value := object[key]
		// A type-scoped context governs the node's properties, but the type
		// identifiers themselves are expanded against the context from before
		// those scopes were applied (W3C c014/c018).
		type_expansion_context := ctx
		if type_context != nil {
			type_expansion_context = type_context^
		} else if ctx.has_previous {
			type_expansion_context = previous_context(&ctx)
		}
		if type_object, is_type_object := object_from_value(type_value); state.retain_frame_controls && is_type_object {
			expand_write_member_prefix(builder, &first, "@type")
			if err := expand_write_frame_type_map(builder, state, &type_expansion_context, type_object); err != .None do return false, err
		} else if err := expand_append_types(state, &type_expansion_context, &properties, type_value); err != .None do return false, err
		has_non_id = true
	}
	if index_value, has_index := has_keyword(object, &ctx, "@index"); has_index {
		index, valid := string_value(index_value)
		if !valid do return false, .Invalid_Value_Object
		expand_write_member_prefix(builder, &first, "@index")
		write_json_string(builder, index)
		has_non_id = true
	}
	keyword_aliases := [2]string{"@graph", "@included"}
	for keyword in keyword_aliases {
		found := false
		for key in keys {
			if keyword_for(&ctx, key) == keyword {
				found = true
				break
			}
		}
		if !found do continue
		expand_write_member_prefix(builder, &first, keyword)
		if err := expand_write_keyword_alias_values(builder, state, &ctx, object, keys[:], keyword); err != .None do return false, err
		has_non_id = true
	}
	for key in keys {
		if key == "@context" || keyword_for(&ctx, key) == "@id" || keyword_for(&ctx, key) == "@type" || keyword_for(&ctx, key) == "@index" do continue
		if state.retain_frame_controls && frame_is_control(key) do continue
		value := object[key]
		keyword := keyword_for(&ctx, key)
		if keyword == "@set" do continue
		if keyword == "@graph" || keyword == "@included" do continue
		if keyword == "@reverse" {
			reverse, valid := object_from_value(value)
			if !valid do return false, .Invalid_Reverse_Property
			reverse_keys := expand_sorted_keys(reverse)
			for reverse_key in reverse_keys {
				definition := Term_Definition{}
				if found, ok := ctx.terms[reverse_key]; ok {
					if found.disabled do continue
					definition = found
				}
				expanded_key, err := expand_iri(state, &ctx, reverse_key, true, false)
				if err.code != .None {
					delete(reverse_keys)
					return false, expand_from_parse_error(err)
				}
				if is_keyword(expanded_key) {
					delete(reverse_keys)
					return false, .Invalid_Reverse_Property
				}
				if !has_iri_scheme(expanded_key) do continue
				temporary := strings.builder_make()
				value_err := expand_write_values(&temporary, state, &ctx, definition, reverse[reverse_key])
				if value_err != .None {
					strings.builder_destroy(&temporary)
					delete(reverse_keys)
					return false, value_err
				}
				if reverse_err := expand_validate_reverse_values(strings.to_string(temporary)); reverse_err != .None {
					strings.builder_destroy(&temporary)
					delete(reverse_keys)
					return false, reverse_err
				}
				target := &reverse_properties
				if definition.reverse do target = &properties
				if append_err := expand_append_property(target, expanded_key, strings.to_string(temporary)); append_err != .None {
					strings.builder_destroy(&temporary)
					delete(reverse_keys)
					return false, append_err
				}
				strings.builder_destroy(&temporary)
			}
			delete(reverse_keys)
			has_non_id = true
			continue
		}
		if keyword == "@nest" do continue
		if len(keyword) > 0 do continue
		definition := Term_Definition{}
		if found, ok := ctx.terms[key]; ok {
			if found.disabled do continue
			definition = found
		}
		property_count := len(properties) + len(reverse_properties)
		if err := expand_append_node_property(state, &ctx, &properties, &reverse_properties, key, definition, value); err != .None do return false, err
		if len(properties) + len(reverse_properties) > property_count do has_non_id = true
	}
	for key in keys {
		if keyword_for(&ctx, key) != "@nest" do continue
		property_count := len(properties) + len(reverse_properties)
		nested_context, context_err := expand_context_for_nest(state, &ctx, key)
		if context_err != .None do return false, context_err
		if err := expand_process_nest(state, &nested_context, &properties, &reverse_properties, object[key]); err != .None do return false, err
		if len(properties) + len(reverse_properties) > property_count do has_non_id = true
	}
	expand_sort_properties(&properties)
	for property in properties {
		expand_write_member_prefix(builder, &first, property.key)
		strings.write_string(builder, property.value)
	}
	expand_sort_properties(&reverse_properties)
	if len(reverse_properties) > 0 {
		expand_write_member_prefix(builder, &first, "@reverse")
		strings.write_byte(builder, '{')
		reverse_first := true
		for property in reverse_properties {
			expand_write_member_prefix(builder, &reverse_first, property.key)
			strings.write_string(builder, property.value)
		}
		strings.write_byte(builder, '}')
	}
	strings.write_byte(builder, '}')
	if !nested && !has_non_id && !state.retain_id_only_nodes do return false, .None
	return true, .None
}

@(private) expand_write_single_resolved :: proc(builder: ^strings.Builder, state: ^State, ctx: ^Context, definition: Term_Definition, value: json.Value, nested: bool, type_context: ^Context = nil) -> (bool, Expand_Error) {
	if definition.type == "@json" {
		strings.write_string(builder, `{"@value": `)
		if !compact_write_raw_json(builder, value) do return false, .Invalid_Value_Object
		strings.write_string(builder, `, "@type": "@json"}`)
		return true, .None
	}
	object, is_object := object_from_value(value)
	if !is_object do return false, .Invalid_Value_Object
	if list_value, has_list := has_keyword(object, ctx, "@list"); has_list {
		if err := expand_validate_list_object(ctx, object); err != .None do return false, err
		if err := expand_write_list(builder, state, ctx, definition, list_value); err != .None do return false, err
		return true, .None
	}
	return expand_write_node_resolved(builder, state, ctx, object, nested, type_context)
}

@(private) expand_write_single :: proc(builder: ^strings.Builder, state: ^State, ctx: ^Context, definition: Term_Definition, value: json.Value, nested: bool, from_map := false) -> (bool, Expand_Error) {
	if definition.type == "@json" {
		strings.write_string(builder, `{"@value": `)
		if !compact_write_raw_json(builder, value) do return false, .Invalid_Value_Object
		strings.write_string(builder, `, "@type": "@json"}`)
		return true, .None
	}
	#partial switch _ in value { case json.Null: return false, .None }
	if object, is_object := object_from_value(value); is_object {
		type_context, context_err := expand_resolve_object_base_context(state, ctx, definition, object, from_map)
		if context_err != .None do return false, context_err
		active, type_err := expand_apply_type_scoped_contexts(state, &type_context, object)
		if type_err != .None do return false, type_err
		return expand_write_single_resolved(builder, state, &active, definition, value, nested, &type_context)
	}
	if _, is_array := array_from_value(value); is_array do return false, .Invalid_Value_Object
	if err := expand_write_primitive(builder, state, ctx, definition, value); err != .None do return false, err
	return true, .None
}

@(private) expand_write_top_item :: proc(builder: ^strings.Builder, state: ^State, ctx: ^Context, value: json.Value, first: ^bool) -> Expand_Error {
	if array, is_array := array_from_value(value); is_array {
		for item in array {
			if err := expand_write_top_item(builder, state, ctx, item, first); err != .None do return err
		}
		return .None
	}
	if object, is_object := object_from_value(value); is_object {
		type_context, context_err := expand_resolve_object_base_context(state, ctx, {}, object)
		if context_err != .None do return context_err
		active, type_err := expand_apply_type_scoped_contexts(state, &type_context, object)
		if type_err != .None do return type_err
		if set_value, has_set := has_keyword(object, &active, "@set"); has_set do return expand_write_top_item(builder, state, &active, set_value, first)
		// Value and list objects have no node identity at document scope, so
		// Expansion removes them rather than emitting free-floating values.
		if _, has_value := has_keyword(object, &active, "@value"); has_value do return .None
		if _, has_list := has_keyword(object, &active, "@list"); has_list do return .None
		if graph_value, has_graph := has_keyword(object, &active, "@graph"); has_graph && !state.preserve_top_level_graph {
			_, has_id := has_keyword(object, &active, "@id")
			has_other := false
			for key in object {
				keyword := keyword_for(&active, key)
				if keyword != "@context" && keyword != "@graph" && keyword != "@index" {
					has_other = true
					break
				}
			}
			if !has_id && !has_other do return expand_write_top_item(builder, state, &active, graph_value, first)
		}
		temporary := strings.builder_make()
		defer strings.builder_destroy(&temporary)
		written, err := expand_write_single_resolved(&temporary, state, &active, {}, value, false, &type_context)
		if err != .None || !written do return err
		if !first^ do strings.write_string(builder, ", ")
		strings.write_string(builder, strings.to_string(temporary))
		first^ = false
		return .None
	}
	// Primitive values are free-floating at document scope and are removed by
	// the Expansion algorithm. They remain valid when reached through a node
	// property, which uses expand_write_values instead.
	return .None
}

@(private) expand_write_top_values :: proc(builder: ^strings.Builder, state: ^State, ctx: ^Context, value: json.Value) -> Expand_Error {
	strings.write_byte(builder, '[')
	first := true
	if err := expand_write_top_item(builder, state, ctx, value, &first); err != .None do return err
	strings.write_byte(builder, ']')
	return .None
}

@(private) expand_document :: proc(builder: ^strings.Builder, input: string, options: Expand_Options, retain_id_only_nodes, retain_frame_controls: bool) -> Expand_Error {
	context_options := options.context_options
	if !utf8.valid_string(input) do return .Invalid_UTF8
	max_document_bytes := context_options.max_document_bytes
	if max_document_bytes == 0 do max_document_bytes = DEFAULT_MAX_DOCUMENT_BYTES
	max_depth := context_options.max_nesting_depth
	if max_depth == 0 do max_depth = DEFAULT_MAX_NESTING_DEPTH
	max_contexts := context_options.max_contexts
	if max_contexts == 0 do max_contexts = DEFAULT_MAX_CONTEXTS
	max_remote := context_options.max_remote_contexts
	if max_remote == 0 do max_remote = DEFAULT_MAX_REMOTE_CONTEXTS
	max_output := options.max_output_bytes
	if max_output == 0 do max_output = DEFAULT_MAX_EXPANDED_OUTPUT_BYTES
	if max_document_bytes < 0 || max_depth < 0 || max_contexts < 0 || max_remote < 0 || max_output < 0 || context_options.max_quads < 0 do return .Invalid_Option
	if len(input) > max_document_bytes do return .Document_Too_Large
	if depth_err := scan_depth(input, max_depth); depth_err.code != .None do return expand_from_parse_error(depth_err)
	prepared := strings.builder_make()
	defer strings.builder_destroy(&prepared)
	prepare_json_input(&prepared, strings.trim_space(input))
	parsed, json_err := json.parse_string(strings.to_string(prepared), .JSON, true)
	if json_err != .None do return .Invalid_JSON
	defer json.destroy_value(parsed)
	state := State{remote_urls = make(map[string]bool), named_bnodes = make(map[string]rdf.Term), max_contexts = max_contexts, max_remote = max_remote, loader = context_options.document_loader, loader_data = context_options.loader_data, allow_document_containers = context_options.processing_mode != .Json_LD_1_0, allow_direction = context_options.processing_mode != .Json_LD_1_0, legacy_prefixes = context_options.processing_mode == .Json_LD_1_0, retain_id_only_nodes = retain_id_only_nodes, retain_frame_controls = retain_frame_controls, preserve_top_level_graph = options.preserve_top_level_graph}
	defer destroy_state(&state)
	ctx, context_err := make_context(&state, nil)
	if context_err.code != .None do return expand_from_parse_error(context_err)
	retain_context(&state, ctx)
	if len(context_options.base_iri) > 0 {
		if !has_iri_scheme(context_options.base_iri) do return .Invalid_IRI
		base, base_err := resolve_iri(&state, context_options.base_iri, "")
		if base_err.code != .None do return expand_from_parse_error(base_err)
		ctx.base_iri = base
	}
	state.initial_base_iri = ctx.base_iri
	if len(context_options.initial_context) > 0 {
		initial_context, initial_context_error := apply_initial_context(&state, &ctx, context_options.initial_context)
		if initial_context_error.code != .None do return expand_from_parse_error(initial_context_error)
		ctx = initial_context
	}
	temporary := strings.builder_make()
	defer strings.builder_destroy(&temporary)
	if err := expand_write_top_values(&temporary, &state, &ctx, parsed); err != .None do return err
	strings.write_byte(&temporary, '\n')
	if len(strings.to_string(temporary)) > max_output do return .Output_Too_Large
	strings.write_string(builder, strings.to_string(temporary))
	return .None
}

// expand atomically appends deterministic expanded JSON-LD. It never uses the
// RDF conversion path, because RDF cannot retain ordinary @index annotations
// and other JSON-LD document metadata.
expand :: proc(builder: ^strings.Builder, input: string, options: Expand_Options = {}) -> Expand_Error {
	return expand_document(builder, input, options, false, false)
}

// Frames select nodes by @id alone, while ordinary document expansion omits a
// top-level ID-only object. Keep that framing-only distinction internal.
@(private) expand_frame :: proc(builder: ^strings.Builder, input: string, options: Expand_Options = {}) -> Expand_Error {
	return expand_document(builder, input, options, true, true)
}
