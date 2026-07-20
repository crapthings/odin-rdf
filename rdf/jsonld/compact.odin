// Context-directed compaction for deterministic expanded JSON-LD output.
package jsonld

import json "core:encoding/json"
import "core:sort"
import "core:strings"
import "core:unicode/utf8"
import rdf ".."

Compact_Array_Policy :: enum { Compact, Preserve }

// Compact_Native_Type_Policy controls whether xsd:boolean, xsd:integer, and
// finite xsd:double values become JSON scalars before value compaction.
Compact_Native_Type_Policy :: enum { Native, Lexical }

Compact_Options :: struct {
	context_options:    Options,
	serializer_options: Serialize_Options,
	array_policy:       Compact_Array_Policy,
	native_type_policy: Compact_Native_Type_Policy,
}

@(private) Compact_List_Term_Group :: struct {
	term:       string,
	definition: Term_Definition,
	values:     [dynamic]json.Value,
}

@(private) destroy_compact_list_term_groups :: proc(groups: ^[dynamic]Compact_List_Term_Group) {
	for &group in groups^ do delete(group.values)
	delete(groups^)
}

Compact_Error :: enum {
	None,
	Invalid_Option,
	Invalid_UTF8,
	Context_Too_Large,
	Context_Nesting_Limit,
	Context_Limit,
	Invalid_Context,
	Unsupported_Context,
	Invalid_Quad,
	Quad_Limit,
	Ambiguous_Blank_Node_Label,
	Invalid_Expanded_JSON,
	Out_Of_Memory,
}

compact_error_message :: proc(code: Compact_Error) -> string {
	switch code {
	case .None:                       return "no error"
	case .Invalid_Option:             return "compaction options are invalid"
	case .Invalid_UTF8:               return "JSON-LD context contains invalid UTF-8"
	case .Context_Too_Large:          return "JSON-LD context exceeds configured byte limit"
	case .Context_Nesting_Limit:      return "JSON-LD context nesting depth limit reached"
	case .Context_Limit:              return "context limit reached"
	case .Invalid_Context:            return "invalid JSON-LD context"
	case .Unsupported_Context:        return "unsupported JSON-LD context feature"
	case .Invalid_Quad:               return "invalid RDF quad"
	case .Quad_Limit:                 return "JSON-LD serializer quad limit reached"
	case .Ambiguous_Blank_Node_Label: return "blank-node labels from different source scopes cannot be serialized together"
	case .Invalid_Expanded_JSON:      return "internal expanded JSON-LD serialization is invalid"
	case .Out_Of_Memory:              return "memory allocation failed"
	}
	return "unknown error"
}

@(private) compact_context_error :: proc(err: Parse_Error) -> Compact_Error {
	#partial switch err.code {
	case .None:                       return .None
	case .Invalid_Option:             return .Invalid_Option
	case .Invalid_UTF8:               return .Invalid_UTF8
	case .Document_Too_Large:         return .Context_Too_Large
	case .Nesting_Limit:              return .Context_Nesting_Limit
	case .Context_Limit:              return .Context_Limit
	case .Out_Of_Memory:              return .Out_Of_Memory
	case .Unsupported_Feature:        return .Unsupported_Context
	case .Invalid_Context, .Invalid_Term_Definition, .Invalid_IRI, .Remote_Context_Disallowed, .Remote_Context_Limit, .Loading_Document_Failed:
		return .Invalid_Context
	}
	return .Invalid_Context
}

@(private) compact_serialize_error :: proc(err: Serialize_Error) -> Compact_Error {
	switch err {
	case .None:                       return .None
	case .Invalid_Option:             return .Invalid_Option
	case .Invalid_UTF8:               return .Invalid_UTF8
	case .Invalid_JSON_Literal:       return .Invalid_Expanded_JSON
	case .Invalid_Quad:               return .Invalid_Quad
	case .Quad_Limit:                 return .Quad_Limit
	case .Ambiguous_Blank_Node_Label: return .Ambiguous_Blank_Node_Label
	}
	return .Invalid_Quad
}

@(private) compact_sorted_keys :: proc(object: json.Object) -> [dynamic]string {
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

@(private) compact_prefer :: proc(candidate, current: string) -> bool {
	return len(current) == 0 || len(candidate) < len(current) || (len(candidate) == len(current) && strings.compare(candidate, current) < 0)
}

@(private) compact_keyword :: proc(ctx: ^Context, keyword: string) -> string {
	best := ""
	for term, definition in ctx.terms {
		if definition.id == keyword && compact_prefer(term, best) do best = term
	}
	return len(best) > 0 ? best : keyword
}

@(private) compact_iri :: proc(state: ^State, ctx: ^Context, value: string, vocab: bool) -> (string, Compact_Error) {
	if strings.has_prefix(value, "_:") {
		if !state.canonical_frame_blank_ids do return value, .None
		if alias, found := state.frame_blank_aliases[value]; found do return alias, .None
		builder := strings.builder_make()
		defer strings.builder_destroy(&builder)
		strings.write_string(&builder, "_:b")
		strings.write_u64(&builder, state.frame_blank_counter)
		state.frame_blank_counter += 1
		alias, own_error := own(state, strings.to_string(builder))
		if own_error.code != .None do return "", .Out_Of_Memory
		state.frame_blank_aliases[value] = alias
		return alias, .None
	}
	best := ""
	for term, definition in ctx.terms {
		if definition.reverse || len(definition.id) == 0 do continue
		if definition.id == value && compact_prefer(term, best) do best = term
	}
	if vocab && len(ctx.vocab) > 0 && strings.has_prefix(value, ctx.vocab) {
		candidate := value[len(ctx.vocab):]
		if len(candidate) > 0 && compact_prefer(candidate, best) do best = candidate
	}
	if !vocab && len(ctx.base_iri) > 0 && strings.has_prefix(value, ctx.base_iri) {
		candidate := value[len(ctx.base_iri):]
		if len(candidate) > 0 && compact_prefer(candidate, best) do best = candidate
	}
	for term, definition in ctx.terms {
		if definition.reverse || len(definition.id) == 0 || !strings.has_prefix(value, definition.id) do continue
		suffix := value[len(definition.id):]
		if len(suffix) == 0 do continue
		candidate_builder := strings.builder_make()
		strings.write_string(&candidate_builder, term)
		strings.write_byte(&candidate_builder, ':')
		strings.write_string(&candidate_builder, suffix)
		candidate, own_error := own(state, strings.to_string(candidate_builder))
		strings.builder_destroy(&candidate_builder)
		if own_error.code != .None do return "", .Out_Of_Memory
		if compact_prefer(candidate, best) do best = candidate
	}
	return len(best) > 0 ? best : value, .None
}

@(private) compact_value_matches_definition :: proc(value: json.Value, definition: Term_Definition) -> bool {
	object, valid := object_from_value(value)
	if !valid do return false
	direction_value, has_direction := object_value(object, "@direction")
	direction, direction_valid := string_value(direction_value)
	if definition.has_direction && (!has_direction || !direction_valid || direction != definition.direction) do return false
	if definition.direction_null && has_direction do return false
	if definition.type == "@id" || definition.type == "@vocab" {
		_, has_id := object_value(object, "@id")
		return has_id
	}
	// @type: @none deliberately disables value coercion. It matches each value
	// so the selected term can retain its original expanded value-object form.
	if definition.type == "@none" do return true
	if len(definition.type) > 0 {
		type_value, has_type := object_value(object, "@type")
		type_name, type_valid := string_value(type_value)
		if has_type do return type_valid && type_name == definition.type
		// serialize may intentionally use a native JSON scalar, whose datatype
		// is still unambiguous for these three RDF XSD types.
		raw_value, has_raw_value := object_value(object, "@value")
		if !has_raw_value do return false
		#partial switch _ in raw_value {
		case json.Boolean: return definition.type == XSD_BOOLEAN
		case json.Integer: return definition.type == XSD_INTEGER
		case json.Float:   return definition.type == XSD_DOUBLE
		}
		return false
	}
	if definition.has_language {
		language_value, has_language := object_value(object, "@language")
		language, language_valid := string_value(language_value)
		return has_language && language_valid && language == definition.language
	}
	if definition.language_null {
		_, has_value := object_value(object, "@value")
		_, has_language := object_value(object, "@language")
		_, has_type := object_value(object, "@type")
		return has_value && !has_language && !has_type
	}
	return true
}

@(private) compact_values_match_definition :: proc(values: json.Array, definition: Term_Definition) -> bool {
	items := values
	if definition.container_list {
		if len(values) != 1 do return false
		list_object, valid := object_from_value(values[0])
		if !valid do return false
		list_value, has_list := object_value(list_object, "@list")
		if !has_list do return false
		items_valid: bool
		items, items_valid = array_from_value(list_value)
		if !items_valid do return false
	}
	for item in items {
		if !compact_value_matches_definition(item, definition) do return false
	}
	return true
}

// compact_property_term selects a term by its value semantics before length.
// A shortest-name-only selection changes language, type, or list meaning when
// one IRI has several context aliases.
@(private) compact_property_term :: proc(state: ^State, ctx: ^Context, iri: string, values: json.Array) -> (string, Term_Definition, bool, Compact_Error) {
	best := ""
	best_definition: Term_Definition
	best_score := -1
	for term, definition in ctx.terms {
		if definition.id != iri || definition.reverse || !compact_values_match_definition(values, definition) do continue
		score := 0
		if definition.container_list do score += 4
		if definition.container_language do score += 3
		if definition.container_index do score += 1
		if definition.container_set do score += 1
		if len(definition.type) > 0 do score += 2
		if definition.has_language || definition.language_null do score += 2
		if definition.has_direction || definition.direction_null do score += 2
		if score > best_score || (score == best_score && compact_prefer(term, best)) {
			best = term
			best_definition = definition
			best_score = score
		}
	}
	if len(best) > 0 do return best, best_definition, true, .None
	// No single term can represent this mixed value set. A plain compact IRI
	// preserves those value semantics while still using an applicable prefix.
	// (Choosing a term definition here could add language, type, or container
	// semantics that the expanded values did not have.)
	compacted, err := compact_iri(state, ctx, iri, true)
	if err != .None do return "", {}, false, err
	return compacted, {}, false, .None
}

@(private) compact_write_raw_json :: proc(builder: ^strings.Builder, value: json.Value) -> bool {
	#partial switch actual in value {
	case json.String:
		write_json_string(builder, string(actual))
	case json.Integer:
		strings.write_i64(builder, i64(actual))
	case json.Float:
		write_json_float(builder, f64(actual))
	case json.Boolean:
		strings.write_string(builder, bool(actual) ? "true" : "false")
	case json.Null:
		strings.write_string(builder, "null")
	case json.Array:
		strings.write_byte(builder, '[')
		for item, index in actual {
			if index > 0 do strings.write_string(builder, ", ")
			if !compact_write_raw_json(builder, item) do return false
		}
		strings.write_byte(builder, ']')
	case json.Object:
		keys := compact_sorted_keys(actual)
		defer delete(keys)
		strings.write_byte(builder, '{')
		for key, index in keys {
			if index > 0 do strings.write_string(builder, ", ")
			write_json_string(builder, key)
			strings.write_string(builder, ": ")
			if !compact_write_raw_json(builder, actual[key]) do return false
		}
		strings.write_byte(builder, '}')
	}
	return true
}

@(private) compact_write_identifier :: proc(builder: ^strings.Builder, state: ^State, ctx: ^Context, value: json.Value, vocab: bool) -> Compact_Error {
	id, valid := string_value(value)
	if !valid do return .Invalid_Expanded_JSON
	compacted, compact_error := compact_iri(state, ctx, id, vocab)
	if compact_error != .None do return compact_error
	write_json_string(builder, compacted)
	return .None
}

@(private) compact_write_list :: proc(builder: ^strings.Builder, state: ^State, ctx: ^Context, value: json.Value, definition: Term_Definition, has_definition: bool, policy: Compact_Array_Policy) -> Compact_Error {
	array, valid := array_from_value(value)
	if !valid do return .Invalid_Expanded_JSON
	strings.write_byte(builder, '[')
	for item, index in array {
		if index > 0 do strings.write_string(builder, ", ")
		if err := compact_write_value(builder, state, ctx, item, definition, has_definition, policy); err != .None do return err
	}
	strings.write_byte(builder, ']')
	return .None
}

@(private) compact_write_value_object :: proc(builder: ^strings.Builder, state: ^State, ctx: ^Context, object: json.Object, definition: Term_Definition, has_definition: bool) -> Compact_Error {
	value, has_value := object_value(object, "@value")
	if !has_value do return .Invalid_Expanded_JSON
	type_value, has_type := object_value(object, "@type")
	language_value, has_language := object_value(object, "@language")
	direction_value, has_direction := object_value(object, "@direction")
	type_name, type_is_string := string_value(type_value)
	language, language_is_string := string_value(language_value)
	direction, direction_is_string := string_value(direction_value)
	if has_direction && (!direction_is_string || (direction != "ltr" && direction != "rtl")) do return .Invalid_Expanded_JSON
	// With a default language, an untagged RDF literal must remain a value
	// object; emitting a scalar would silently acquire that default language on
	// the next JSON-LD-to-RDF pass. A term with @language: null is the explicit
	// exception and may safely use a scalar.
	can_scalar := !has_type && !has_language && (!ctx.has_language || (has_definition && definition.language_null))
	if has_type && type_is_string && has_definition && definition.type == type_name do can_scalar = true
	if has_definition && definition.type == "@none" do can_scalar = false
	if has_language && language_is_string {
		if has_definition && definition.has_language && definition.language == language do can_scalar = true
		if !has_definition && ctx.has_language && ctx.language == language do can_scalar = true
	}
	if has_type && type_is_string && type_name == "@json" && has_definition && definition.type == "@json" do can_scalar = true
	expected_direction := ""
	has_expected_direction := false
	if has_definition && definition.has_direction {
		expected_direction = definition.direction
		has_expected_direction = true
	} else if !(has_definition && definition.direction_null) && ctx.has_direction {
		expected_direction = ctx.direction
		has_expected_direction = true
	}
	if has_direction {
		if !has_expected_direction || direction != expected_direction do can_scalar = false
	} else if has_expected_direction {
		can_scalar = false
	}
	if can_scalar {
		if !compact_write_raw_json(builder, value) do return .Invalid_Expanded_JSON
		return .None
	}
	strings.write_byte(builder, '{')
	write_json_string(builder, compact_keyword(ctx, "@value"))
	strings.write_string(builder, ": ")
	if !compact_write_raw_json(builder, value) do return .Invalid_Expanded_JSON
	if has_language {
		if !language_is_string do return .Invalid_Expanded_JSON
		strings.write_string(builder, ", ")
		write_json_string(builder, compact_keyword(ctx, "@language"))
		strings.write_string(builder, ": ")
		write_json_string(builder, language)
	}
	if has_direction {
		strings.write_string(builder, ", ")
		write_json_string(builder, compact_keyword(ctx, "@direction"))
		strings.write_string(builder, ": ")
		write_json_string(builder, direction)
	}
	if has_type {
		if !type_is_string do return .Invalid_Expanded_JSON
		strings.write_string(builder, ", ")
		write_json_string(builder, compact_keyword(ctx, "@type"))
		strings.write_string(builder, ": ")
		if type_name == "@json" {
			write_json_string(builder, compact_keyword(ctx, "@json"))
		} else {
			compacted, err := compact_iri(state, ctx, type_name, true)
			if err != .None do return err
			write_json_string(builder, compacted)
		}
	}
	strings.write_byte(builder, '}')
	return .None
}

@(private) compact_language_map_key :: proc(value: json.Value) -> string {
	object, valid := object_from_value(value)
	if !valid do return "@none"
	language_value, has_language := object_value(object, "@language")
	language, language_valid := string_value(language_value)
	if has_language && language_valid do return language
	return "@none"
}

// compact_write_language_map groups RDF language literals by their language.
// @index annotations intentionally cannot appear here: they do not survive an
// RDF dataset conversion and are therefore not fabricated on output.
@(private) compact_write_language_map :: proc(builder: ^strings.Builder, state: ^State, ctx: ^Context, values: json.Array, policy: Compact_Array_Policy) -> Compact_Error {
	keys := make([dynamic]string)
	defer delete(keys)
	for value in values {
		key := compact_language_map_key(value)
		found := false
		for existing in keys {
			if existing == key {
				found = true
				break
			}
		}
		if !found do append(&keys, key)
	}
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
	strings.write_byte(builder, '{')
	for key, key_index in keys {
		if key_index > 0 do strings.write_string(builder, ", ")
		compacted_key := key == "@none" ? compact_keyword(ctx, "@none") : key
		write_json_string(builder, compacted_key)
		strings.write_string(builder, ": ")
		count := 0
		for value in values {
			if compact_language_map_key(value) == key do count += 1
		}
		if policy == .Compact && count == 1 {
			for value in values {
				if compact_language_map_key(value) != key do continue
				object, object_valid := object_from_value(value)
				if !object_valid do return .Invalid_Expanded_JSON
				literal, has_literal := object_value(object, "@value")
				_, has_type := object_value(object, "@type")
				if key != "@none" && has_literal && !has_type {
					if !compact_write_raw_json(builder, literal) do return .Invalid_Expanded_JSON
				} else if err := compact_write_value(builder, state, ctx, value, {}, false, policy); err != .None {
					return err
				}
				break
			}
		} else {
			strings.write_byte(builder, '[')
			written := 0
			for value in values {
				if compact_language_map_key(value) != key do continue
				if written > 0 do strings.write_string(builder, ", ")
				object, object_valid := object_from_value(value)
				if !object_valid do return .Invalid_Expanded_JSON
				literal, has_literal := object_value(object, "@value")
				_, has_type := object_value(object, "@type")
				if key != "@none" && has_literal && !has_type {
					if !compact_write_raw_json(builder, literal) do return .Invalid_Expanded_JSON
				} else if err := compact_write_value(builder, state, ctx, value, {}, false, policy); err != .None {
					return err
				}
				written += 1
			}
			strings.write_byte(builder, ']')
		}
	}
	strings.write_byte(builder, '}')
	return .None
}

@(private) compact_write_node :: proc(builder: ^strings.Builder, state: ^State, ctx: ^Context, object: json.Object, policy: Compact_Array_Policy) -> Compact_Error {
	keys := compact_sorted_keys(object)
	defer delete(keys)
	strings.write_byte(builder, '{')
	first := true
	for key in keys {
		value := object[key]
		compacted_key := ""
		definition: Term_Definition
		has_definition := false
		if is_keyword(key) {
			compacted_key = compact_keyword(ctx, key)
		} else {
			array, valid := array_from_value(value)
			if !valid do return .Invalid_Expanded_JSON
			err: Compact_Error
			compacted_key, definition, has_definition, err = compact_property_term(state, ctx, key, array)
			if err != .None do return err
			// A list container term applies to one expanded list. If values for the
			// same predicate require different directional list terms, emit one
			// compact property per term rather than selecting a shortest fallback
			// that changes the list's direction semantics.
			if !has_definition && len(array) > 1 {
				groups := make([dynamic]Compact_List_Term_Group)
				split_lists := true
				for item in array {
					single := make(json.Array)
					append(&single, item)
					term, candidate, candidate_found, candidate_error := compact_property_term(state, ctx, key, single)
					delete(single)
					if candidate_error != .None {
						destroy_compact_list_term_groups(&groups)
						return candidate_error
					}
					item_object, item_valid := object_from_value(item)
					_, has_list := object_value(item_object, "@list")
					if !candidate_found || !candidate.container_list || !item_valid || !has_list {
						split_lists = false
						break
					}
					group_index := -1
					for group, index in groups do if group.term == term { group_index = index; break }
					if group_index < 0 {
						append(&groups, Compact_List_Term_Group{term = term, definition = candidate, values = make([dynamic]json.Value)})
						group_index = len(groups) - 1
					}
					append(&groups[group_index].values, item)
				}
				if split_lists && len(groups) > 1 {
					for group in groups do if len(group.values) != 1 { split_lists = false; break }
				}
				if split_lists && len(groups) > 1 {
					for group in groups {
						if !first do strings.write_string(builder, ", ")
						write_json_string(builder, group.term)
						strings.write_string(builder, ": ")
						item, item_valid := object_from_value(group.values[0])
						list, has_list := object_value(item, "@list")
						if !item_valid || !has_list {
							destroy_compact_list_term_groups(&groups)
							return .Invalid_Expanded_JSON
						}
						if write_error := compact_write_list(builder, state, ctx, list, group.definition, true, policy); write_error != .None {
							destroy_compact_list_term_groups(&groups)
							return write_error
						}
						first = false
					}
					destroy_compact_list_term_groups(&groups)
					continue
				}
				destroy_compact_list_term_groups(&groups)
			}
		}
		if !first do strings.write_string(builder, ", ")
		write_json_string(builder, compacted_key)
		strings.write_string(builder, ": ")
		if key == "@id" {
			if err := compact_write_identifier(builder, state, ctx, value, false); err != .None do return err
		} else if key == "@type" {
			array, valid := array_from_value(value)
			if !valid do return .Invalid_Expanded_JSON
			if policy == .Compact && len(array) == 1 {
				if err := compact_write_identifier(builder, state, ctx, array[0], true); err != .None do return err
			} else {
				strings.write_byte(builder, '[')
				for item, index in array {
					if index > 0 do strings.write_string(builder, ", ")
					if err := compact_write_identifier(builder, state, ctx, item, true); err != .None do return err
				}
				strings.write_byte(builder, ']')
			}
		} else if key == "@graph" {
			array, valid := array_from_value(value)
			if !valid do return .Invalid_Expanded_JSON
			strings.write_byte(builder, '[')
			for item, index in array {
				if index > 0 do strings.write_string(builder, ", ")
				node, node_valid := object_from_value(item)
				if !node_valid do return .Invalid_Expanded_JSON
				if err := compact_write_node(builder, state, ctx, node, policy); err != .None do return err
			}
			strings.write_byte(builder, ']')
		} else {
			array, valid := array_from_value(value)
			if !valid do return .Invalid_Expanded_JSON
			if has_definition && definition.container_language {
				if err := compact_write_language_map(builder, state, ctx, array, policy); err != .None do return err
			} else if has_definition && definition.container_list && len(array) == 1 {
				item, item_valid := object_from_value(array[0])
				list, has_list := object_value(item, "@list")
				if !item_valid || !has_list do return .Invalid_Expanded_JSON
				if err := compact_write_list(builder, state, ctx, list, definition, has_definition, policy); err != .None do return err
			} else if policy == .Compact && len(array) == 1 && (!has_definition || !definition.container_set) {
				if err := compact_write_value(builder, state, ctx, array[0], definition, has_definition, policy); err != .None do return err
			} else {
				strings.write_byte(builder, '[')
				for item, index in array {
					if index > 0 do strings.write_string(builder, ", ")
					if err := compact_write_value(builder, state, ctx, item, definition, has_definition, policy); err != .None do return err
				}
				strings.write_byte(builder, ']')
			}
		}
		first = false
	}
	strings.write_byte(builder, '}')
	return .None
}

@(private) compact_write_value :: proc(builder: ^strings.Builder, state: ^State, ctx: ^Context, value: json.Value, definition: Term_Definition, has_definition: bool, policy: Compact_Array_Policy) -> Compact_Error {
	object, is_object := object_from_value(value)
	if !is_object do return .Invalid_Expanded_JSON
	if id, has_id := object_value(object, "@id"); has_id {
		if has_definition && (definition.type == "@id" || definition.type == "@vocab") do return compact_write_identifier(builder, state, ctx, id, definition.type == "@vocab")
		strings.write_byte(builder, '{')
		write_json_string(builder, compact_keyword(ctx, "@id"))
		strings.write_string(builder, ": ")
		if err := compact_write_identifier(builder, state, ctx, id, false); err != .None do return err
		strings.write_byte(builder, '}')
		return .None
	}
	if list, has_list := object_value(object, "@list"); has_list {
		strings.write_byte(builder, '{')
		write_json_string(builder, compact_keyword(ctx, "@list"))
		strings.write_string(builder, ": ")
		if err := compact_write_list(builder, state, ctx, list, definition, has_definition, policy); err != .None do return err
		strings.write_byte(builder, '}')
		return .None
	}
	if _, has_value := object_value(object, "@value"); has_value do return compact_write_value_object(builder, state, ctx, object, definition, has_definition)
	return compact_write_node(builder, state, ctx, object, policy)
}

// compact atomically writes a context-directed JSON-LD dataset document.
// context is a JSON-encoded context definition, context array, or a remote
// context URL when context_options.document_loader is supplied. A top-level
// @graph is retained so default and named RDF graphs remain representable.
compact :: proc(builder: ^strings.Builder, quads: []rdf.Quad, context_text: string, options: Compact_Options = {}) -> Compact_Error {
	if !utf8.valid_string(context_text) do return .Invalid_UTF8
	context_options := options.context_options
	max_document_bytes := context_options.max_document_bytes
	if max_document_bytes == 0 do max_document_bytes = DEFAULT_MAX_DOCUMENT_BYTES
	if max_document_bytes < 0 || context_options.max_nesting_depth < 0 || context_options.max_contexts < 0 || context_options.max_remote_contexts < 0 do return .Invalid_Option
	if len(context_text) > max_document_bytes do return .Context_Too_Large
	max_depth := context_options.max_nesting_depth
	if max_depth == 0 do max_depth = DEFAULT_MAX_NESTING_DEPTH
	if depth_error := scan_depth(context_text, max_depth); depth_error.code != .None do return .Context_Nesting_Limit
	parsed_context, json_error := json.parse_string(strings.trim_space(context_text), .JSON, true)
	if json_error != .None do return .Invalid_Context
	defer json.destroy_value(parsed_context)
	active_context := parsed_context
	if context_document, is_document := object_from_value(parsed_context); is_document {
		if nested_context, has_nested_context := object_value(context_document, "@context"); has_nested_context do active_context = nested_context
	}
	max_contexts := context_options.max_contexts
	if max_contexts == 0 do max_contexts = DEFAULT_MAX_CONTEXTS
	max_remote := context_options.max_remote_contexts
	if max_remote == 0 do max_remote = DEFAULT_MAX_REMOTE_CONTEXTS
	state := State{
		remote_urls = make(map[string]bool),
		named_bnodes = make(map[string]rdf.Term),
		max_contexts = max_contexts,
		max_remote = max_remote,
		loader = context_options.document_loader,
		loader_data = context_options.loader_data,
		allow_document_containers = true,
		allow_direction = true,
	}
	defer destroy_state(&state)
	ctx, context_error := make_context(&state, nil)
	if context_error.code != .None do return compact_context_error(context_error)
	retain_context(&state, ctx)
	if len(context_options.base_iri) > 0 {
		if !has_iri_scheme(context_options.base_iri) do return .Invalid_Context
		base, base_error := resolve_iri(&state, context_options.base_iri, "")
		if base_error.code != .None do return compact_context_error(base_error)
		ctx.base_iri = base
	}
	ctx, context_error = apply_context(&state, &ctx, active_context)
	if context_error.code != .None do return compact_context_error(context_error)
	expanded := strings.builder_make()
	defer strings.builder_destroy(&expanded)
	serializer_options := options.serializer_options
	if options.native_type_policy == .Native do serializer_options.use_native_types = true
	if serialize_error := serialize(&expanded, quads, serializer_options); serialize_error != .None do return compact_serialize_error(serialize_error)
	expanded_document, expanded_error := json.parse_string(strings.to_string(expanded), .JSON, true)
	if expanded_error != .None do return .Invalid_Expanded_JSON
	defer json.destroy_value(expanded_document)
	nodes, valid_nodes := array_from_value(expanded_document)
	if !valid_nodes do return .Invalid_Expanded_JSON
	temporary := strings.builder_make()
	defer strings.builder_destroy(&temporary)
	single_default_node := false
	if len(nodes) == 1 {
		node, node_valid := object_from_value(nodes[0])
		if !node_valid do return .Invalid_Expanded_JSON
		_, has_graph := object_value(node, "@graph")
		single_default_node = !has_graph
	}
	if single_default_node {
		node_builder := strings.builder_make()
		defer strings.builder_destroy(&node_builder)
		node, _ := object_from_value(nodes[0])
		if compact_error := compact_write_node(&node_builder, &state, &ctx, node, options.array_policy); compact_error != .None do return compact_error
		compacted_node := strings.to_string(node_builder)
		strings.write_string(&temporary, "{\n  \"@context\": ")
		if !compact_write_raw_json(&temporary, active_context) do return .Invalid_Context
		if len(compacted_node) > 2 {
			strings.write_string(&temporary, ",\n  ")
			strings.write_string(&temporary, compacted_node[1:len(compacted_node) - 1])
		}
		strings.write_string(&temporary, "\n}\n")
		strings.write_string(builder, strings.to_string(temporary))
		return .None
	}
	strings.write_string(&temporary, "{\n  \"@context\": ")
	if !compact_write_raw_json(&temporary, active_context) do return .Invalid_Context
	strings.write_string(&temporary, ",\n  \"@graph\": [")
	for node_value, index in nodes {
		if index > 0 do strings.write_string(&temporary, ",\n")
		node, node_valid := object_from_value(node_value)
		if !node_valid do return .Invalid_Expanded_JSON
		strings.write_string(&temporary, "\n    ")
		if compact_error := compact_write_node(&temporary, &state, &ctx, node, options.array_policy); compact_error != .None do return compact_error
	}
	if len(nodes) > 0 do strings.write_byte(&temporary, '\n')
	strings.write_string(&temporary, "  ]\n}\n")
	strings.write_string(builder, strings.to_string(temporary))
	return .None
}
