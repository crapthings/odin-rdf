// Internal framing primitives. Public framing is added only together with
// recursive embedding and compacted output; an expanded-only result would not
// satisfy the JSON-LD Framing API contract.
package jsonld

import json "core:encoding/json"
import "core:strings"
import "core:unicode/utf8"
import rdf ".."

Frame_Error :: enum {
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
	Invalid_IRI,
	Invalid_Value_Object,
	Invalid_List_Object,
	Invalid_Reverse_Property,
	Invalid_Frame,
	Unsupported_Feature,
	Node_Limit,
	Embedding_Limit,
	Output_Too_Large,
	Out_Of_Memory,
}

frame_error_message :: proc(code: Frame_Error) -> string {
	switch code {
	case .None:                       return "no error"
	case .Invalid_Option:             return "framing options are invalid"
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
	case .Invalid_IRI:                return "invalid JSON-LD IRI"
	case .Invalid_Value_Object:       return "invalid JSON-LD value object"
	case .Invalid_List_Object:        return "invalid JSON-LD list object"
	case .Invalid_Reverse_Property:   return "invalid JSON-LD reverse property"
	case .Invalid_Frame:              return "invalid JSON-LD frame"
	case .Unsupported_Feature:        return "unsupported JSON-LD framing feature"
	case .Node_Limit:                 return "framed node limit reached"
	case .Embedding_Limit:            return "framing embedding depth limit reached"
	case .Output_Too_Large:           return "framed JSON-LD exceeds configured byte limit"
	case .Out_Of_Memory:              return "memory allocation failed"
	}
	return "unknown error"
}

Frame_Processing_Mode :: enum {
	Json_LD_1_1,
	Json_LD_1_0,
}

// Frame_Options applies one bounded context policy to the source and frame.
// JSON-LD 1.1 is the default. Set omit_graph_set to preserve an explicit
// boolean choice instead of the processing mode's default graph shape.
Frame_Options :: struct {
	context_options:     Options,
	max_nodes:           int,
	max_embedding_depth: int,
	max_output_bytes:    int,
	array_policy:        Compact_Array_Policy,
	processing_mode:     Frame_Processing_Mode,
	omit_graph:          bool,
	omit_graph_set:      bool,
}

DEFAULT_MAX_FRAME_EMBEDDING_DEPTH :: 128

@(private) frame_array_has_string :: proc(value: json.Value, expected: string) -> bool {
	items, is_array := array_from_value(value)
	if !is_array do return false
	for item in items {
		actual, valid := string_value(item)
		if valid && actual == expected do return true
	}
	return false
}

// The initial framing profile must fail closed for policy controls it does not
// implement. Context definitions are excluded because their keywords are
// validated by normal context processing rather than framing policy handling.
@(private) frame_has_unsupported_policy :: proc(value: json.Value) -> bool {
	if object, is_object := object_from_value(value); is_object {
		for key, item in object {
			if key == "@context" do continue
			switch key {
			case "@embed":
				if !frame_embed_is_valid(item) do return true
			case "@explicit", "@omitDefault", "@requireAll":
				if !frame_boolean_is_valid(item) do return true
			}
			if frame_has_unsupported_policy(item) do return true
		}
		return false
	}
	if array, is_array := array_from_value(value); is_array {
		for item in array {
			if frame_has_unsupported_policy(item) do return true
		}
	}
	return false
}

@(private) frame_boolean_is_valid :: proc(value: json.Value) -> bool {
	#partial switch text in value {
	case json.Boolean:
		return true
	case json.String:
		return string(text) == "true" || string(text) == "false"
	}
	return false
}

@(private) frame_boolean_value :: proc(value: json.Value, fallback: bool) -> bool {
	#partial switch actual in value {
	case json.Boolean:
		return bool(actual)
	case json.String:
		if string(actual) == "true" do return true
		if string(actual) == "false" do return false
	}
	return fallback
}

@(private) frame_embed_is_valid :: proc(value: json.Value) -> bool {
	#partial switch embed in value {
	case json.Boolean:
		return true
	case json.String:
		mode := string(embed)
		return mode == "@always" || mode == "@never" || mode == "@first" || mode == "@last" || mode == "@once"
	}
	return false
}

@(private) frame_is_control :: proc(key: string) -> bool {
	return key == "@default" || key == "@embed" || key == "@explicit" || key == "@omitDefault" || key == "@requireAll"
}

@(private) frame_is_blank_identifier :: proc(value: json.Value) -> bool {
	text, valid := string_value(value)
	return valid && len(text) >= 2 && text[0:2] == "_:"
}

@(private) frame_has_blank_match :: proc(value: json.Value) -> bool {
	object, is_object := object_from_value(value)
	if is_object {
		for key, member in object {
			if key == "@id" || key == "@type" {
				if frame_is_blank_identifier(member) do return true
				if items, is_array := array_from_value(member); is_array {
					for item in items {
						if frame_is_blank_identifier(item) do return true
					}
				}
			}
			if frame_has_blank_match(member) do return true
		}
		return false
	}
	if array, is_array := array_from_value(value); is_array {
		for item in array {
			if frame_has_blank_match(item) do return true
		}
	}
	return false
}

// frame_matches_node implements the first selection stage over an expanded
// node-map. It is deliberately side-effect free so embedding can reuse it for
// both top-level and nested property frames.
@(private) frame_matches_node :: proc(node, frame: json.Object) -> bool {
	matched_keyword := false
	if frame_id, has_id := object_value(frame, "@id"); has_id {
		ids, is_array := array_from_value(frame_id)
		node_id, has_node_id := object_value(node, "@id")
		node_text, valid_node_id := string_value(node_id)
		if !has_node_id || !valid_node_id do return false
		matched := false
		if id_pattern, is_id_pattern := object_from_value(frame_id); is_id_pattern {
			matched = len(id_pattern) == 0
		} else if is_array {
			if len(ids) == 0 do return false
			for id in ids {
				candidate, valid := string_value(id)
				if valid && candidate == node_text { matched = true; break }
			}
		} else if candidate, valid := string_value(frame_id); valid {
			matched = candidate == node_text
		}
		if !matched do return false
		matched_keyword = true
	}
	if frame_types, has_types := object_value(frame, "@type"); has_types {
		if type_frame, is_type_frame := object_from_value(frame_types); is_type_frame {
			if _, has_default := object_value(type_frame, "@default"); !has_default {
				if _, has_node_types := object_value(node, "@type"); !has_node_types do return false
				matched_keyword = true
			}
		} else {
		types, is_array := array_from_value(frame_types)
		if !is_array do return false
		if len(types) == 0 {
			if _, has_node_types := object_value(node, "@type"); has_node_types do return false
		} else {
			node_types, has_node_types := object_value(node, "@type")
			if !has_node_types do return false
			matched := false
			for expected in types {
				text, valid := string_value(expected)
				if valid && frame_array_has_string(node_types, text) { matched = true; break }
			}
			if !matched do return false
			matched_keyword = true
		}
		}
	}
	require_all := frame_is_require_all(frame)
	ordinary_count := 0
	matched_count := 0
	for key, candidate in frame {
		if is_keyword(key) || frame_is_control(key) do continue
		ordinary_count += 1
		if _, has_property := object_value(node, key); has_property {
			matched_count += 1
			continue
		}
		if !require_all do continue
		child_frame, child_valid := object_from_value(candidate)
		if !child_valid {
			candidates, candidates_valid := array_from_value(candidate)
			if !candidates_valid || len(candidates) == 0 do return false
			child_frame, child_valid = object_from_value(candidates[0])
			if !child_valid do return false
		}
		if _, has_default := object_value(child_frame, "@default"); !has_default do return false
	}
	if !require_all && ordinary_count > 0 && matched_count == 0 && !matched_keyword do return false
	return true
}

@(private) frame_empty_object :: proc(value: json.Value) -> bool {
	object, valid := object_from_value(value)
	return valid && len(object) == 0
}

@(private) frame_control_only_object :: proc(object: json.Object) -> bool {
	for key in object {
		if !frame_is_control(key) do return false
	}
	return true
}

@(private) frame_json_equal :: proc(left, right: json.Value) -> bool {
	left_builder := strings.builder_make()
	defer strings.builder_destroy(&left_builder)
	right_builder := strings.builder_make()
	defer strings.builder_destroy(&right_builder)
	if !compact_write_raw_json(&left_builder, left) || !compact_write_raw_json(&right_builder, right) do return false
	return strings.to_string(left_builder) == strings.to_string(right_builder)
}

@(private) frame_pattern_member_matches :: proc(actual, pattern: json.Value) -> bool {
	if frame_empty_object(pattern) do return true
	if candidates, is_array := array_from_value(pattern); is_array {
		for candidate in candidates {
			if frame_json_equal(actual, candidate) do return true
		}
		return false
	}
	return frame_json_equal(actual, pattern)
}

@(private) frame_value_pattern_matches :: proc(value: json.Value, pattern: json.Object) -> bool {
	pattern_value, has_pattern_value := object_value(pattern, "@value")
	if !has_pattern_value do return false
	value_object, value_valid := object_from_value(value)
	if !value_valid do return false
	actual_value, has_actual_value := object_value(value_object, "@value")
	if !has_actual_value do return false
	if !frame_pattern_member_matches(actual_value, pattern_value) do return false
	keywords := [2]string{"@type", "@language"}
	for keyword in keywords {
		pattern_member, has_pattern_member := object_value(pattern, keyword)
		actual_member, has_actual_member := object_value(value_object, keyword)
		if !has_pattern_member {
			if has_actual_member do return false
			continue
		}
		if pattern_items, is_pattern_array := array_from_value(pattern_member); is_pattern_array && len(pattern_items) == 0 {
			if has_actual_member do return false
			continue
		}
		if !has_actual_member do return false
		if !frame_pattern_member_matches(actual_member, pattern_member) do return false
	}
	return true
}

@(private) frame_value_matches_node :: proc(node_map: ^Frame_Node_Map, value, candidate: json.Value, visiting: ^[dynamic]string) -> bool {
	if frame_empty_object(candidate) do return true
	if candidate_object, candidate_valid := object_from_value(candidate); candidate_valid {
		if frame_control_only_object(candidate_object) do return true
		if pattern_list, has_pattern_list := object_value(candidate_object, "@list"); has_pattern_list {
			value_object, value_valid := object_from_value(value)
			if !value_valid do return false
			actual_list, has_actual_list := object_value(value_object, "@list")
			if !has_actual_list do return false
			pattern_items, pattern_valid := array_from_value(pattern_list)
			actual_items, actual_valid := array_from_value(actual_list)
			if !pattern_valid || !actual_valid do return false
			for actual in actual_items {
				for pattern in pattern_items {
					if frame_value_matches_node(node_map, actual, pattern, visiting) do return true
				}
			}
			return false
		}
		if _, is_value_pattern := object_value(candidate_object, "@value"); is_value_pattern do return frame_value_pattern_matches(value, candidate_object)
		value_object, value_valid := object_from_value(value)
		if !value_valid do return false
		if id_value, has_id := value_object["@id"]; has_id {
			id, id_valid := string_value(id_value)
			if !id_valid do return false
			if index, found := node_map.ids[id]; found {
				for active in visiting^ {
					if active == id do return true
				}
				append(visiting, id)
				matched := frame_matches_node_map(node_map, node_map.nodes[index], candidate_object, visiting)
				pop(visiting)
				return matched
			}
			if frame_id, has_frame_id := object_value(candidate_object, "@id"); has_frame_id {
				ids, is_array := array_from_value(frame_id)
				if is_array {
					for expected in ids {
						text, valid := string_value(expected)
						if valid && text == id do return true
					}
				} else if expected, valid := string_value(frame_id); valid {
					return expected == id
				}
			}
		}
	}
	return false
}

@(private) frame_value_matches_candidates :: proc(node_map: ^Frame_Node_Map, value, candidate: json.Value, visiting: ^[dynamic]string) -> bool {
	candidates, is_array := array_from_value(candidate)
	if !is_array do return frame_value_matches_node(node_map, value, candidate, visiting)
	if len(candidates) == 0 do return false
	for item in candidates {
		if frame_value_matches_node(node_map, value, item, visiting) do return true
	}
	return false
}

@(private) frame_property_matches :: proc(node_map: ^Frame_Node_Map, values: json.Array, candidate: json.Value, visiting: ^[dynamic]string) -> bool {
	for value in values {
		if frame_value_matches_candidates(node_map, value, candidate, visiting) do return true
	}
	return false
}

@(private) frame_matches_node_map :: proc(node_map: ^Frame_Node_Map, node, frame: json.Object, visiting: ^[dynamic]string) -> bool {
	if !frame_matches_node(node, frame) do return false
	for key, candidate in frame {
		if is_keyword(key) || frame_is_control(key) do continue
		value, has_property := object_value(node, key)
		if !has_property do continue
		values, valid := array_from_value(value)
		if !valid do return false
		if !frame_property_matches(node_map, values, candidate, visiting) do return false
	}
	return true
}

@(private) frame_matches_node_in_map :: proc(node_map: ^Frame_Node_Map, node, frame: json.Object) -> bool {
	visiting := make([dynamic]string)
	defer delete(visiting)
	return frame_matches_node_map(node_map, node, frame, &visiting)
}

@(private) frame_omits_default :: proc(frame: json.Object) -> bool {
	value, has_omit := object_value(frame, "@omitDefault")
	if !has_omit do return false
	return frame_boolean_value(value, false)
}

@(private) frame_is_require_all :: proc(frame: json.Object) -> bool {
	value, has_require_all := object_value(frame, "@requireAll")
	if !has_require_all do return false
	return frame_boolean_value(value, false)
}

@(private) frame_has_set_container :: proc(ctx: ^Context, iri: string) -> bool {
	for _, definition in ctx.terms {
		if definition.id == iri && definition.container_set do return true
	}
	return false
}

@(private) frame_write_missing_value :: proc(builder: ^strings.Builder, frame: json.Object, set_container: bool) -> bool {
	if frame_omits_default(frame) do return false
	if set_container {
		strings.write_string(builder, "[]")
		return true
	}
	if default_value, has_default := object_value(frame, "@default"); has_default {
		if default_object, is_default_object := object_from_value(default_value); is_default_object {
			if _, has_value := object_value(default_object, "@value"); has_value {
				strings.write_byte(builder, '[')
				if !compact_write_raw_json(builder, default_value) do return false
				strings.write_byte(builder, ']')
				return true
			}
		}
		strings.write_string(builder, `[{"@value": `)
		if text, is_text := string_value(default_value); is_text && text == "@null" {
			strings.write_string(builder, "null")
		} else if !compact_write_raw_json(builder, default_value) do return false
	} else {
		strings.write_string(builder, `[{"@value": `)
		strings.write_string(builder, "null")
	}
	strings.write_string(builder, "}]")
	return true
}

@(private) Frame_Embed_Mode :: enum {
	Always,
	Never,
	First,
	Last,
	Once,
}

@(private) frame_embed_mode :: proc(frame: json.Object, inherited: Frame_Embed_Mode = .Always) -> Frame_Embed_Mode {
	value, has_embed := object_value(frame, "@embed")
	if !has_embed do return inherited
	#partial switch embed in value {
	case json.Boolean:
		return bool(embed) ? .Always : .Never
	case json.String:
		switch string(embed) {
		case "@always": return .Always
		case "@never":  return .Never
		case "@first":  return .First
		case "@last":   return .Last
		case "@once":   return .Once
		}
	}
	return inherited
}

@(private) frame_is_id_reference :: proc(frame: json.Object) -> bool {
	if len(frame) != 1 do return false
	_, has_id := object_value(frame, "@id")
	return has_id
}

@(private) frame_is_explicit :: proc(frame: json.Object) -> bool {
	value, has_explicit := object_value(frame, "@explicit")
	if !has_explicit do return false
	return frame_boolean_value(value, false)
}

@(private) Frame_Node_Map :: struct {
	nodes:        [dynamic]json.Object,
	ids:          map[string]int,
	owned:        [dynamic]json.Value,
	graph_values: map[string]json.Array,
	legacy_prefixes: bool,
}

@(private) frame_destroy_node_map :: proc(node_map: ^Frame_Node_Map) {
	for value in node_map.owned do json.destroy_value(value)
	delete(node_map.nodes)
	delete(node_map.ids)
	delete(node_map.owned)
	delete(node_map.graph_values)
}

@(private) frame_write_merged_arrays :: proc(builder: ^strings.Builder, left, right: json.Value) -> bool {
	left_items, left_valid := array_from_value(left)
	right_items, right_valid := array_from_value(right)
	if !left_valid || !right_valid do return false
	strings.write_byte(builder, '[')
	seen := make([dynamic]string)
	defer {
		for item in seen do delete(item)
		delete(seen)
	}
	written := 0
	for source_index in 0..<2 {
		source := source_index == 0 ? left_items : right_items
		for item in source {
			temporary := strings.builder_make()
			if !compact_write_raw_json(&temporary, item) {
				strings.builder_destroy(&temporary)
				return false
			}
			text, clone_error := strings.clone(strings.to_string(temporary))
			strings.builder_destroy(&temporary)
			if clone_error != nil do return false
			duplicate := false
			for prior in seen {
				if prior == text { duplicate = true; break }
			}
			if duplicate {
				delete(text)
				continue
			}
			if written > 0 do strings.write_string(builder, ", ")
			strings.write_string(builder, text)
			append(&seen, text)
			written += 1
		}
	}
	strings.write_byte(builder, ']')
	return true
}

@(private) frame_merge_nodes :: proc(left, right: json.Object) -> (json.Value, json.Object, bool) {
	keys := compact_sorted_keys(left)
	defer delete(keys)
	right_keys := compact_sorted_keys(right)
	defer delete(right_keys)
	for key in right_keys {
		found := false
		for existing in keys {
			if existing == key { found = true; break }
		}
		if !found do append(&keys, key)
	}
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	strings.write_byte(&builder, '{')
	for key, index in keys {
		if index > 0 do strings.write_string(&builder, ", ")
		write_json_string(&builder, key)
		strings.write_string(&builder, ": ")
		left_value, has_left := object_value(left, key)
		right_value, has_right := object_value(right, key)
		if has_left && has_right && key != "@id" {
			if !frame_write_merged_arrays(&builder, left_value, right_value) do return {}, {}, false
		} else if has_left {
			if !compact_write_raw_json(&builder, left_value) do return {}, {}, false
		} else if has_right {
			if !compact_write_raw_json(&builder, right_value) do return {}, {}, false
		}
	}
	strings.write_byte(&builder, '}')
	merged, parse_error := json.parse_string(strings.to_string(builder), .JSON, true)
	if parse_error != .None do return {}, {}, false
	object, valid := object_from_value(merged)
	if !valid {
		json.destroy_value(merged)
		return {}, {}, false
	}
	return merged, object, true
}

@(private) frame_add_map_node :: proc(node_map: ^Frame_Node_Map, node: json.Object) {
	id_value, has_id := object_value(node, "@id")
	id, id_valid := string_value(id_value)
	if !has_id || !id_valid do return
	if index, found := node_map.ids[id]; found {
		merged, object, valid := frame_merge_nodes(node_map.nodes[index], node)
		if valid {
			append(&node_map.owned, merged)
			node_map.nodes[index] = object
		}
		return
	}
	node_map.ids[id] = len(node_map.nodes)
	append(&node_map.nodes, node)
}

// Add graph-scoped nodes to the fallback merged view unless a direct
// flattened node already owns that identifier. This preserves historical
// cross-named-graph merging for identifiers absent from the default graph,
// while keeping a default-graph node insulated from same-ID graph members.
@(private) frame_collect_graph_fallback_node :: proc(node_map: ^Frame_Node_Map, direct_ids: ^map[string]bool, node: json.Object) {
	id_value, has_id := object_value(node, "@id")
	id, id_valid := string_value(id_value)
	if !has_id || !id_valid do return
	if !direct_ids^[id] do frame_add_map_node(node_map, node)
	graph, has_graph := object_value(node, "@graph")
	if !has_graph do return
	graph_nodes, graph_valid := array_from_value(graph)
	if !graph_valid do return
	node_map.graph_values[id] = graph_nodes
	for value in graph_nodes {
		child, child_valid := object_from_value(value)
		if child_valid do frame_collect_graph_fallback_node(node_map, direct_ids, child)
	}
}

@(private) frame_make_node_map :: proc(values: json.Array) -> Frame_Node_Map {
	result := Frame_Node_Map{nodes = make([dynamic]json.Object), ids = make(map[string]int), owned = make([dynamic]json.Value), graph_values = make(map[string]json.Array)}
	direct_ids := make(map[string]bool)
	defer delete(direct_ids)
	for value in values {
		node, valid := object_from_value(value)
		if !valid do continue
		// The default graph is made only from the flattened document's direct
		// nodes. Named-graph members are available through graph_values and are
		// intentionally not folded into this map: identical identifiers in two
		// graph scopes describe different node-map entries while framing.
		frame_add_map_node(&result, node)
		id_value, has_id := object_value(node, "@id")
		id, id_valid := string_value(id_value)
		if has_id && id_valid do direct_ids[id] = true
		graph, has_graph := object_value(node, "@graph")
		if !has_graph do continue
		graph_nodes, graph_valid := array_from_value(graph)
		if !graph_valid do continue
		if has_id && id_valid {
			result.graph_values[id] = graph_nodes
		}
	}
	for value in values {
		node, valid := object_from_value(value)
		if !valid do continue
		graph, has_graph := object_value(node, "@graph")
		if !has_graph do continue
		graph_nodes, graph_valid := array_from_value(graph)
		if !graph_valid do continue
		for graph_value in graph_nodes {
			graph_node, graph_node_valid := object_from_value(graph_value)
			if graph_node_valid do frame_collect_graph_fallback_node(&result, &direct_ids, graph_node)
		}
	}
	return result
}

// A named graph has its own node map.  In particular, an identifier in a
// named graph must not inherit properties from the default graph (or another
// named graph) merely because the identifiers happen to be equal.  Keep the
// top-level map's merged view for ordinary framing, but build this direct
// local view whenever a frame explicitly enters @graph.
@(private) frame_make_graph_node_map :: proc(values: json.Array) -> Frame_Node_Map {
	result := Frame_Node_Map{nodes = make([dynamic]json.Object), ids = make(map[string]int), owned = make([dynamic]json.Value), graph_values = make(map[string]json.Array)}
	for value in values {
		node, valid := object_from_value(value)
		if !valid do continue
		frame_add_map_node(&result, node)
		graph, has_graph := object_value(node, "@graph")
		if !has_graph do continue
		graph_nodes, graph_valid := array_from_value(graph)
		if !graph_valid do continue
		id_value, has_id := object_value(node, "@id")
		id, id_valid := string_value(id_value)
		if has_id && id_valid do result.graph_values[id] = graph_nodes
	}
	return result
}

@(private) Frame_Embedding_State :: struct {
	seen:      map[string]bool,
	remaining: map[string]int,
	included:  map[string]bool,
}

@(private) frame_destroy_embedding_state :: proc(state: ^Frame_Embedding_State) {
	delete(state.seen)
	delete(state.remaining)
	delete(state.included)
}

@(private) frame_count_references_in_value :: proc(state: ^Frame_Embedding_State, value: json.Value) {
	object, valid := object_from_value(value)
	if !valid do return
	if id_value, has_id := object_value(object, "@id"); has_id {
		if id, id_valid := string_value(id_value); id_valid do state.remaining[id] += 1
		return
	}
	if list, has_list := object_value(object, "@list"); has_list {
		items, items_valid := array_from_value(list)
		if !items_valid do return
		for item in items do frame_count_references_in_value(state, item)
	}
}

@(private) frame_make_embedding_state :: proc(node_map: ^Frame_Node_Map) -> Frame_Embedding_State {
	state := Frame_Embedding_State{seen = make(map[string]bool), remaining = make(map[string]int), included = make(map[string]bool)}
	for node in node_map.nodes {
		for key, value in node {
			if is_keyword(key) do continue
			items, valid := array_from_value(value)
			if !valid do continue
			for item in items do frame_count_references_in_value(&state, item)
		}
	}
	return state
}

@(private) frame_mark_blank_references_in_value :: proc(state: ^State, value: json.Value) {
	object, valid := object_from_value(value)
	if !valid do return
	if id_value, has_id := object_value(object, "@id"); has_id {
		if id, id_valid := string_value(id_value); id_valid && len(id) >= 2 && id[0:2] == "_:" do state.referenced_frame_blank_ids[id] = true
		return
	}
	if list, has_list := object_value(object, "@list"); has_list {
		items, items_valid := array_from_value(list)
		if !items_valid do return
		for item in items do frame_mark_blank_references_in_value(state, item)
	}
}

@(private) frame_mark_blank_references :: proc(state: ^State, node_map: ^Frame_Node_Map) {
	for node in node_map.nodes {
		for key, value in node {
			if key == "@type" {
				items, valid := array_from_value(value)
				if !valid do continue
				for item in items {
					id, id_valid := string_value(item)
					if id_valid && len(id) >= 2 && id[0:2] == "_:" do state.referenced_frame_blank_ids[id] = true
				}
				continue
			}
			if is_keyword(key) do continue
			items, valid := array_from_value(value)
			if !valid do continue
			for item in items do frame_mark_blank_references_in_value(state, item)
		}
	}
}

// Framing may allocate identifiers for anonymous input nodes while flattening.
// Those identifiers only belong in the compact result when the framed result
// needs them to preserve identity: a node occurs more than once, or a blank
// identifier is used as a type. Looking at the source node map is too broad,
// because every embedded anonymous node is referenced there exactly once.
@(private) frame_mark_embedded_blank_references :: proc(state: ^State, value: json.Value, seen: ^map[string]bool) {
	object, object_valid := object_from_value(value)
	if object_valid {
		if id_value, has_id := object_value(object, "@id"); has_id {
			if id, id_valid := string_value(id_value); id_valid && len(id) >= 2 && id[0:2] == "_:" {
				if seen^[id] {
					state.referenced_frame_blank_ids[id] = true
				} else {
					seen^[id] = true
				}
			}
		}
		if types, has_types := object_value(object, "@type"); has_types {
			if items, items_valid := array_from_value(types); items_valid {
				for item in items {
					if id, id_valid := string_value(item); id_valid && len(id) >= 2 && id[0:2] == "_:" do state.referenced_frame_blank_ids[id] = true
				}
			}
		}
		for _, child in object do frame_mark_embedded_blank_references(state, child, seen)
		return
	}
	if items, items_valid := array_from_value(value); items_valid {
		for item in items do frame_mark_embedded_blank_references(state, item, seen)
	}
}

@(private) frame_write_reference :: proc(builder: ^strings.Builder, id: string) {
	strings.write_string(builder, `{"@id": `)
	write_json_string(builder, id)
	strings.write_byte(builder, '}')
}

@(private) frame_graph_frame :: proc(frame: json.Object) -> (json.Object, bool) {
	value, has_graph := object_value(frame, "@graph")
	if !has_graph do return {}, false
	frames, frames_valid := array_from_value(value)
	if !frames_valid || len(frames) == 0 do return {}, false
	graph_frame, graph_frame_valid := object_from_value(frames[0])
	return graph_frame, graph_frame_valid
}

@(private) frame_value_references_id :: proc(value: json.Value, id: string) -> bool {
	object, object_valid := object_from_value(value)
	if !object_valid do return false
	if referenced, has_reference := object_value(object, "@id"); has_reference {
		referenced_id, referenced_valid := string_value(referenced)
		return referenced_valid && referenced_id == id
	}
	if list, has_list := object_value(object, "@list"); has_list {
		items, items_valid := array_from_value(list)
		if !items_valid do return false
		for item in items {
			if frame_value_references_id(item, id) do return true
		}
	}
	return false
}

@(private) frame_node_references_id :: proc(node: json.Object, id: string) -> bool {
	for key, value in node {
		if is_keyword(key) do continue
		values, values_valid := array_from_value(value)
		if !values_valid do continue
		for item in values {
			if frame_value_references_id(item, id) do return true
		}
	}
	return false
}

// Writes the framed contents of a named graph rather than its flattened raw
// members.  The graph-local map is deliberately used for both matching and
// recursive embedding so graph-scoped nodes cannot be contaminated by the
// global merged node map.
@(private) frame_write_graph :: proc(builder: ^strings.Builder, graph: json.Value, graph_frame: json.Object, output_ctx: ^Context, embed_mode: Frame_Embed_Mode, embedding_state: ^Frame_Embedding_State, embeds: ^[dynamic]string, max_depth: int) -> Frame_Error {
	values, values_valid := array_from_value(graph)
	if !values_valid do return .Invalid_Frame
	graph_map := frame_make_graph_node_map(values)
	defer frame_destroy_node_map(&graph_map)
	strings.write_byte(builder, '[')
	written := 0
	for candidate in graph_map.nodes {
		if !frame_matches_node_in_map(&graph_map, candidate, graph_frame) do continue
		id_value, has_id := object_value(candidate, "@id")
		id, id_valid := string_value(id_value)
		if !has_id || !id_valid do return .Invalid_Frame
		// Graph results are roots. A selected node that is already reached from
		// another selected graph node is embedded at that reference instead of
		// emitted a second time at the graph root.
		referenced := false
		for other in graph_map.nodes {
			other_id_value, other_has_id := object_value(other, "@id")
			other_id, other_id_valid := string_value(other_id_value)
			if !other_has_id || !other_id_valid || other_id == id do continue
			if !frame_matches_node_in_map(&graph_map, other, graph_frame) do continue
			if frame_node_references_id(other, id) { referenced = true; break }
		}
		if referenced do continue
		if written > 0 do strings.write_string(builder, ", ")
		if len(embeds^) >= max_depth do return .Embedding_Limit
		append(embeds, id)
		candidate_mode := frame_embed_mode(graph_frame, embed_mode)
		if err := frame_write_node(builder, &graph_map, output_ctx, candidate, graph_frame, candidate_mode, embedding_state, embeds, max_depth, {}, false); err != .None do return err
		pop(embeds)
		written += 1
	}
	strings.write_byte(builder, ']')
	return .None
}

// Lists preserve their ordering and scalar members. Node members, however,
// are framed through the same embedding path as ordinary property values so a
// list can select or embed a referenced node without bypassing the frame.
@(private) frame_write_list :: proc(builder: ^strings.Builder, node_map: ^Frame_Node_Map, output_ctx: ^Context, list: json.Value, child_frame: json.Object, embed_mode: Frame_Embed_Mode, embedding_state: ^Frame_Embedding_State, embeds: ^[dynamic]string, max_depth: int, inherited_graph_frame: json.Object, has_inherited_graph_frame: bool) -> Frame_Error {
	items, valid := array_from_value(list)
	if !valid do return .Invalid_List_Object
	patterns_value, has_patterns := object_value(child_frame, "@list")
	patterns: json.Array
	patterns_valid := false
	if has_patterns {
		patterns, patterns_valid = array_from_value(patterns_value)
		if !patterns_valid do return .Invalid_Frame
	}
	filter_node_references := patterns_valid
	strings.write_string(builder, `{"@list": [`)
	written := 0
	for item in items {
		item_frame := json.Object{}
		matched := false
		if patterns_valid {
			matching := make([dynamic]string)
			for pattern in patterns {
				if !frame_value_matches_node(node_map, item, pattern, &matching) do continue
				candidate, candidate_valid := object_from_value(pattern)
				if candidate_valid do item_frame = candidate
				matched = true
				break
			}
			delete(matching)
		}
		item_object, item_is_object := object_from_value(item)
		_, item_is_reference := object_value(item_object, "@id")
		if item_is_object && item_is_reference && filter_node_references && !matched do continue
		if written > 0 do strings.write_string(builder, ", ")
		item_mode := frame_embed_mode(item_frame, embed_mode)
		if err := frame_write_value(builder, node_map, output_ctx, item, item_frame, item_mode, embedding_state, embeds, max_depth, inherited_graph_frame, has_inherited_graph_frame); err != .None do return err
		written += 1
	}
	strings.write_string(builder, `]}`)
	return .None
}

@(private) frame_write_value :: proc(builder: ^strings.Builder, node_map: ^Frame_Node_Map, output_ctx: ^Context, value: json.Value, child_frame: json.Object, embed_mode: Frame_Embed_Mode, embedding_state: ^Frame_Embedding_State, embeds: ^[dynamic]string, max_depth: int, inherited_graph_frame: json.Object, has_inherited_graph_frame: bool) -> Frame_Error {
	object, valid := object_from_value(value)
	if !valid do return compact_write_raw_json(builder, value) ? .None : .Invalid_Frame
	if list, has_list := object_value(object, "@list"); has_list do return frame_write_list(builder, node_map, output_ctx, list, child_frame, embed_mode, embedding_state, embeds, max_depth, inherited_graph_frame, has_inherited_graph_frame)
	id_value, has_id := object_value(object, "@id")
	id, id_valid := string_value(id_value)
	if !has_id || !id_valid do return compact_write_raw_json(builder, value) ? .None : .Invalid_Frame
	if embedding_state.included[id] {
		frame_write_reference(builder, id)
		return .None
	}
	if embed_mode == .Never || frame_is_id_reference(child_frame) {
		frame_write_reference(builder, id)
		return .None
	}
	if embed_mode == .Last {
		if remaining, found := embedding_state.remaining[id]; found && remaining > 0 {
			remaining -= 1
			embedding_state.remaining[id] = remaining
			if remaining > 0 {
				frame_write_reference(builder, id)
				return .None
			}
		}
	} else if embed_mode == .First || embed_mode == .Once {
		if embedding_state.seen[id] {
			frame_write_reference(builder, id)
			return .None
		}
		embedding_state.seen[id] = true
	}
	index, found := node_map.ids[id]
	if !found {
		frame_write_reference(builder, id)
		return .None
	}
	resolved_map := node_map
	resolved_node := node_map.nodes[index]
	_, child_has_graph_frame := frame_graph_frame(child_frame)
	if !child_has_graph_frame && !has_inherited_graph_frame {
		if graph_values, has_graph_values := node_map.graph_values[id]; has_graph_values {
			graph_map := frame_make_graph_node_map(graph_values)
			defer frame_destroy_node_map(&graph_map)
			if graph_index, graph_found := graph_map.ids[id]; graph_found {
				if !frame_matches_node_in_map(&graph_map, graph_map.nodes[graph_index], child_frame) {
					frame_write_reference(builder, id)
					return .None
				}
				for embedded in embeds^ {
					if embedded == id {
						frame_write_reference(builder, id)
						return .None
					}
				}
				if len(embeds^) >= max_depth do return .Embedding_Limit
				append(embeds, id)
				err := frame_write_node(builder, &graph_map, output_ctx, graph_map.nodes[graph_index], child_frame, embed_mode, embedding_state, embeds, max_depth, inherited_graph_frame, has_inherited_graph_frame)
				pop(embeds)
				return err
			}
		}
	}
	if !frame_matches_node_in_map(resolved_map, resolved_node, child_frame) {
		frame_write_reference(builder, id)
		return .None
	}
	for embedded in embeds^ {
		if embedded == id {
			frame_write_reference(builder, id)
			return .None
		}
	}
	if len(embeds^) >= max_depth do return .Embedding_Limit
	append(embeds, id)
	err := frame_write_node(builder, resolved_map, output_ctx, resolved_node, child_frame, embed_mode, embedding_state, embeds, max_depth, inherited_graph_frame, has_inherited_graph_frame)
	pop(embeds)
	return err
}

@(private) frame_write_reverse :: proc(builder: ^strings.Builder, node_map: ^Frame_Node_Map, output_ctx: ^Context, node, reverse: json.Object, embed_mode: Frame_Embed_Mode, embedding_state: ^Frame_Embedding_State, embeds: ^[dynamic]string, max_depth: int, inherited_graph_frame: json.Object, has_inherited_graph_frame: bool) -> Frame_Error {
	id_value, has_id := object_value(node, "@id")
	id, id_valid := string_value(id_value)
	if !has_id || !id_valid do return .Invalid_Frame
	keys := compact_sorted_keys(reverse)
	defer delete(keys)
	strings.write_byte(builder, '{')
	for predicate, predicate_index in keys {
		if predicate_index > 0 do strings.write_string(builder, ", ")
		write_json_string(builder, predicate)
		strings.write_string(builder, ": [")
		written := 0
		for candidate in node_map.nodes {
			values_value, has_values := object_value(candidate, predicate)
			if !has_values do continue
			values, values_valid := array_from_value(values_value)
			if !values_valid do return .Invalid_Frame
			references := false
			for value in values {
				value_object, value_valid := object_from_value(value)
				if !value_valid do continue
				reference, has_reference := object_value(value_object, "@id")
				reference_id, reference_valid := string_value(reference)
				if has_reference && reference_valid && reference_id == id { references = true; break }
			}
			if !references do continue
			candidate_id_value, candidate_has_id := object_value(candidate, "@id")
			candidate_id, candidate_id_valid := string_value(candidate_id_value)
			if !candidate_has_id || !candidate_id_valid do return .Invalid_Frame
			if written > 0 do strings.write_string(builder, ", ")
			append(embeds, candidate_id)
			if err := frame_write_node(builder, node_map, output_ctx, candidate, json.Object{}, embed_mode, embedding_state, embeds, max_depth, inherited_graph_frame, has_inherited_graph_frame); err != .None do return err
			pop(embeds)
			written += 1
		}
		strings.write_byte(builder, ']')
	}
	strings.write_byte(builder, '}')
	return .None
}

// @included is evaluated before ordinary properties. Included nodes are
// recorded so later references to the same node do not duplicate an implicit
// embedding.
@(private) frame_write_included :: proc(builder: ^strings.Builder, node_map: ^Frame_Node_Map, output_ctx: ^Context, value: json.Value, embed_mode: Frame_Embed_Mode, embedding_state: ^Frame_Embedding_State, embeds: ^[dynamic]string, max_depth: int, first: ^bool, inherited_graph_frame: json.Object, has_inherited_graph_frame: bool) -> Frame_Error {
	frames, frames_valid := array_from_value(value)
	if !frames_valid do return .Invalid_Frame
	if !first^ do strings.write_string(builder, ", ")
	write_json_string(builder, "@included")
	strings.write_string(builder, ": [")
	written := 0
	for frame_value in frames {
		included_frame, frame_valid := object_from_value(frame_value)
		if !frame_valid do return .Invalid_Frame
		included_mode := frame_embed_mode(included_frame, embed_mode)
		for candidate in node_map.nodes {
			if !frame_matches_node_in_map(node_map, candidate, included_frame) do continue
			id_value, has_id := object_value(candidate, "@id")
			id, id_valid := string_value(id_value)
			if !has_id || !id_valid do return .Invalid_Frame
			if embedding_state.included[id] do continue
			embedding_state.included[id] = true
			if written > 0 do strings.write_string(builder, ", ")
			append(embeds, id)
			if err := frame_write_node(builder, node_map, output_ctx, candidate, included_frame, included_mode, embedding_state, embeds, max_depth, inherited_graph_frame, has_inherited_graph_frame); err != .None do return err
			pop(embeds)
			written += 1
		}
	}
	strings.write_byte(builder, ']')
	first^ = false
	return .None
}

@(private) frame_write_node :: proc(builder: ^strings.Builder, node_map: ^Frame_Node_Map, output_ctx: ^Context, node, frame: json.Object, embed_mode: Frame_Embed_Mode, embedding_state: ^Frame_Embedding_State, embeds: ^[dynamic]string, max_depth: int, inherited_graph_frame: json.Object, has_inherited_graph_frame: bool) -> Frame_Error {
	keys := compact_sorted_keys(node)
	defer delete(keys)
	explicit := frame_is_explicit(frame)
	graph_frame, has_graph_frame := frame_graph_frame(frame)
	if !has_graph_frame && has_inherited_graph_frame {
		graph_frame = inherited_graph_frame
		has_graph_frame = true
	}
	strings.write_byte(builder, '{')
	first := true
	if included_value, has_included := object_value(frame, "@included"); has_included {
		if included_error := frame_write_included(builder, node_map, output_ctx, included_value, embed_mode, embedding_state, embeds, max_depth, &first, graph_frame, has_graph_frame); included_error != .None do return included_error
	}
	for key in keys {
		if key == "@index" do continue
		if key == "@graph" {
			if !has_graph_frame do continue
			if !first do strings.write_string(builder, ", ")
			write_json_string(builder, key)
			strings.write_string(builder, ": ")
			if graph_error := frame_write_graph(builder, node[key], graph_frame, output_ctx, embed_mode, embedding_state, embeds, max_depth); graph_error != .None do return graph_error
			first = false
			continue
		}
		if explicit && !is_keyword(key) && key != "@reverse" {
			if _, has_candidate := object_value(frame, key); !has_candidate do continue
		}
		if !first do strings.write_string(builder, ", ")
		write_json_string(builder, key)
		strings.write_string(builder, ": ")
		value := node[key]
		if is_keyword(key) || key == "@reverse" {
			if !compact_write_raw_json(builder, value) do return .Invalid_Frame
			first = false
			continue
		}
		values, is_array := array_from_value(value)
		if !is_array do return .Invalid_Frame
		child_frame: json.Object
		candidate, has_candidate := object_value(frame, key)
		if has_candidate {
			candidates, is_candidates := array_from_value(candidate)
			if is_candidates && len(candidates) > 0 {
				child_frame, _ = object_from_value(candidates[0])
			} else {
				child_frame, _ = object_from_value(candidate)
			}
		}
		strings.write_byte(builder, '[')
		written_values := 0
		for item in values {
			if has_candidate {
				matching := make([dynamic]string)
				matches := frame_value_matches_candidates(node_map, item, candidate, &matching)
				delete(matching)
				if !matches do continue
			}
			if written_values > 0 do strings.write_string(builder, ", ")
			child_mode := frame_embed_mode(child_frame, embed_mode)
			if err := frame_write_value(builder, node_map, output_ctx, item, child_frame, child_mode, embedding_state, embeds, max_depth, graph_frame, has_graph_frame); err != .None do return err
			written_values += 1
		}
		strings.write_byte(builder, ']')
		first = false
	}
	if _, has_type := object_value(node, "@type"); !has_type {
		if type_frame_value, has_type_frame := object_value(frame, "@type"); has_type_frame {
			type_frame, type_frame_valid := object_from_value(type_frame_value)
			if type_frame_valid {
				if default_type, has_default := object_value(type_frame, "@default"); has_default {
					if !first do strings.write_string(builder, ", ")
					write_json_string(builder, "@type")
					strings.write_string(builder, ": [")
					default_types, default_is_array := array_from_value(default_type)
					default_count := default_is_array ? len(default_types) : 1
					for index in 0..<default_count {
						if index > 0 do strings.write_string(builder, ", ")
						if !compact_write_raw_json(builder, default_is_array ? default_types[index] : default_type) do return .Invalid_Frame
					}
					strings.write_byte(builder, ']')
					first = false
				}
			}
		}
	}
	frame_keys := compact_sorted_keys(frame)
	defer delete(frame_keys)
	for key in frame_keys {
		if is_keyword(key) || frame_is_control(key) do continue
		if _, present := object_value(node, key); present do continue
		if node_map.legacy_prefixes {
			// JSON-LD 1.0 permits a source property that looks like a compact
			// IRI. A framing context can define that spelling as a term, so
			// recognise it as already present before inserting a frame default
			// (W3C framing-0010).
			legacy_property_present := false
			for term, definition in output_ctx.terms {
				if definition.id != key do continue
				if _, present := object_value(node, term); present {
					legacy_property_present = true
					break
				}
			}
			if legacy_property_present do continue
		}
		candidate, has_candidate := object_value(frame, key)
		if !has_candidate do continue
		child_frame, child_valid := object_from_value(candidate)
		if !child_valid {
			candidates, candidates_valid := array_from_value(candidate)
			if !candidates_valid do return .Invalid_Frame
			if len(candidates) == 0 {
				if !first do strings.write_string(builder, ", ")
				write_json_string(builder, key)
				strings.write_string(builder, `: [{"@value": null}]`)
				first = false
				continue
			}
			child_frame, child_valid = object_from_value(candidates[0])
			if !child_valid do return .Invalid_Frame
		}
		missing := strings.builder_make()
		written := frame_write_missing_value(&missing, child_frame, frame_has_set_container(output_ctx, key))
		if !written {
			strings.builder_destroy(&missing)
			continue
		}
		if !first do strings.write_string(builder, ", ")
		write_json_string(builder, key)
		strings.write_string(builder, ": ")
		strings.write_string(builder, strings.to_string(missing))
		strings.builder_destroy(&missing)
		first = false
	}
	if reverse_value, has_reverse := object_value(frame, "@reverse"); has_reverse {
		reverse, reverse_valid := object_from_value(reverse_value)
		if !reverse_valid do return .Invalid_Frame
		if !first do strings.write_string(builder, ", ")
		write_json_string(builder, "@reverse")
		strings.write_string(builder, ": ")
		reverse_error := frame_write_reverse(builder, node_map, output_ctx, node, reverse, embed_mode, embedding_state, embeds, max_depth, graph_frame, has_graph_frame)
		if reverse_error != .None do return .Invalid_Reverse_Property
		first = false
	}
	strings.write_byte(builder, '}')
	return .None
}

@(private) frame_from_expand_error :: proc(err: Expand_Error) -> Frame_Error {
	#partial switch err {
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
	case .Protected_Term_Redefinition:return .Invalid_Context
	case .Invalid_IRI:                return .Invalid_IRI
	case .Invalid_Value_Object:       return .Invalid_Value_Object
	case .Invalid_List_Object:        return .Invalid_List_Object
	case .Invalid_Reverse_Property:   return .Invalid_Reverse_Property
	case .Unsupported_Feature:        return .Unsupported_Feature
	case .Output_Too_Large:           return .Output_Too_Large
	case .Out_Of_Memory:              return .Out_Of_Memory
	}
	return .Unsupported_Feature
}

@(private) frame_from_flatten_error :: proc(err: Flatten_Error) -> Frame_Error {
	#partial switch err {
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
	case .Invalid_IRI:                return .Invalid_IRI
	case .Invalid_Value_Object:       return .Invalid_Value_Object
	case .Invalid_List_Object:        return .Invalid_List_Object
	case .Invalid_Reverse_Property:   return .Invalid_Reverse_Property
	case .Unsupported_Feature:        return .Unsupported_Feature
	case .Node_Limit:                 return .Node_Limit
	case .Output_Too_Large:           return .Output_Too_Large
	case .Out_Of_Memory:              return .Out_Of_Memory
	}
	return .Unsupported_Feature
}

@(private) frame_from_context_error :: proc(err: Parse_Error) -> Frame_Error {
	#partial switch err.code {
	case .None:                       return .None
	case .Invalid_Option:             return .Invalid_Option
	case .Invalid_UTF8:               return .Invalid_UTF8
	case .Document_Too_Large:         return .Document_Too_Large
	case .Nesting_Limit:              return .Nesting_Limit
	case .Context_Limit:              return .Context_Limit
	case .Remote_Context_Limit:       return .Remote_Context_Limit
	case .Remote_Context_Disallowed:  return .Remote_Context_Disallowed
	case .Loading_Document_Failed:    return .Loading_Document_Failed
	case .Invalid_Context:            return .Invalid_Context
	case .Invalid_Term_Definition:    return .Invalid_Term_Definition
	case .Invalid_IRI:                return .Invalid_IRI
	case .Invalid_Value_Object:       return .Invalid_Value_Object
	case .Invalid_List_Object:        return .Invalid_List_Object
	case .Invalid_Reverse_Property:   return .Invalid_Reverse_Property
	case .Unsupported_Feature:        return .Unsupported_Feature
	case .Out_Of_Memory:              return .Out_Of_Memory
	case:                             return .Invalid_Context
	}
}

// Framed output may contain an embedded node beneath a term coerced to @id.
// Normal compaction must reduce that value to an identifier, whereas framing
// must retain the complete object. This writer changes only that distinction.
@(private) frame_compact_write_list :: proc(builder: ^strings.Builder, state: ^State, ctx: ^Context, value: json.Value, definition: Term_Definition, has_definition: bool, policy: Compact_Array_Policy) -> Compact_Error {
	items, valid := array_from_value(value)
	if !valid do return .Invalid_Expanded_JSON
	strings.write_byte(builder, '[')
	for item, index in items {
		if index > 0 do strings.write_string(builder, ", ")
		if err := frame_compact_write_value(builder, state, ctx, item, definition, has_definition, policy); err != .None do return err
	}
	strings.write_byte(builder, ']')
	return .None
}

@(private) frame_compact_write_value :: proc(builder: ^strings.Builder, state: ^State, ctx: ^Context, value: json.Value, definition: Term_Definition, has_definition: bool, policy: Compact_Array_Policy) -> Compact_Error {
	if object, is_object := object_from_value(value); is_object {
		if state.prune_frame_blank_ids && len(object) == 1 {
			id_value, has_id := object_value(object, "@id")
			id, valid_id := string_value(id_value)
			if has_id && valid_id && len(id) >= 2 && id[0:2] == "_:" {
				// Framing discards an anonymous reference that has no selected
				// node content. Keep the alias allocation deterministic for a later
				// reference, but do not expose the implementation-only identifier
				// (W3C framing-p046).
				if _, err := compact_iri(state, ctx, id, false); err != .None do return err
				strings.write_string(builder, "{}")
				return .None
			}
		}
		// A graph container compacts the framed graph members as the value of
		// its term. The synthetic graph-node identifier is an implementation
		// detail and must not force an @graph wrapper into the compact result.
		if has_definition && definition.container_graph {
			if graph, has_graph := object_value(object, "@graph"); has_graph {
				items, items_valid := array_from_value(graph)
				if !items_valid do return .Invalid_Expanded_JSON
				if policy == .Compact && len(items) == 1 {
					node, node_valid := object_from_value(items[0])
					if !node_valid do return .Invalid_Expanded_JSON
					return frame_compact_write_node(builder, state, ctx, node, policy)
				}
				strings.write_byte(builder, '[')
				for item, index in items {
					if index > 0 do strings.write_string(builder, ", ")
					node, node_valid := object_from_value(item)
					if !node_valid do return .Invalid_Expanded_JSON
					if err := frame_compact_write_node(builder, state, ctx, node, policy); err != .None do return err
				}
				strings.write_byte(builder, ']')
				return .None
			}
		}
		if _, has_id := object_value(object, "@id"); has_id && len(object) > 1 do return frame_compact_write_node(builder, state, ctx, object, policy)
		if list, has_list := object_value(object, "@list"); has_list {
			strings.write_byte(builder, '{')
			write_json_string(builder, compact_keyword(ctx, "@list"))
			strings.write_string(builder, ": ")
			if err := frame_compact_write_list(builder, state, ctx, list, definition, has_definition, policy); err != .None do return err
			strings.write_byte(builder, '}')
			return .None
		}
	}
	return compact_write_value(builder, state, ctx, value, definition, has_definition, policy)
}

@(private) frame_compact_write_reverse :: proc(builder: ^strings.Builder, state: ^State, ctx: ^Context, reverse: json.Object, policy: Compact_Array_Policy) -> Compact_Error {
	keys := compact_sorted_keys(reverse)
	defer delete(keys)
	strings.write_byte(builder, '{')
	for predicate, predicate_index in keys {
		if predicate_index > 0 do strings.write_string(builder, ", ")
		compacted_predicate, predicate_error := compact_iri(state, ctx, predicate, true)
		if predicate_error != .None do return predicate_error
		write_json_string(builder, compacted_predicate)
		strings.write_string(builder, ": ")
		values, values_valid := array_from_value(reverse[predicate])
		if !values_valid do return .Invalid_Expanded_JSON
		if policy == .Compact && len(values) == 1 {
			node, node_valid := object_from_value(values[0])
			if !node_valid do return .Invalid_Expanded_JSON
			if err := frame_compact_write_node(builder, state, ctx, node, policy); err != .None do return err
		} else {
			strings.write_byte(builder, '[')
			for value, value_index in values {
				if value_index > 0 do strings.write_string(builder, ", ")
				node, node_valid := object_from_value(value)
				if !node_valid do return .Invalid_Expanded_JSON
				if err := frame_compact_write_node(builder, state, ctx, node, policy); err != .None do return err
			}
			strings.write_byte(builder, ']')
		}
	}
	strings.write_byte(builder, '}')
	return .None
}

@(private) frame_context_for_node :: proc(state: ^State, ctx: ^Context, object: json.Object) -> (Context, Compact_Error) {
	types, has_types := object_value(object, "@type")
	if !has_types do return ctx^, .None
	items, items_valid := array_from_value(types)
	if !items_valid do return {}, .Invalid_Expanded_JSON
	for item in items {
		type_id, type_valid := string_value(item)
		if !type_valid do return {}, .Invalid_Expanded_JSON
		for _, definition in ctx.terms {
			if definition.id != type_id || !definition.has_local_context do continue
			updated, context_error := apply_term_scoped_context(state, ctx, definition)
			if context_error.code != .None do return {}, .Invalid_Context
			return updated, .None
		}
	}
	return ctx^, .None
}

@(private) frame_compact_write_node :: proc(builder: ^strings.Builder, state: ^State, inherited: ^Context, object: json.Object, policy: Compact_Array_Policy) -> Compact_Error {
	active_context, context_error := frame_context_for_node(state, inherited, object)
	if context_error != .None do return context_error
	ctx := &active_context
	keys := compact_sorted_keys(object)
	defer delete(keys)
	strings.write_byte(builder, '{')
	first := true
	for key in keys {
		value := object[key]
		if key == "@reverse" {
			reverse, reverse_valid := object_from_value(value)
			if !reverse_valid do return .Invalid_Expanded_JSON
			reverse_keys := compact_sorted_keys(reverse)
			all_aliases := len(reverse_keys) > 0
			for predicate in reverse_keys {
				found_alias := false
				for _, definition in ctx.terms {
					if definition.id == predicate && definition.reverse { found_alias = true; break }
				}
				if !found_alias { all_aliases = false; break }
			}
			if all_aliases {
				for predicate in reverse_keys {
					term := ""
					definition: Term_Definition
					for candidate, candidate_definition in ctx.terms {
						if candidate_definition.id == predicate && candidate_definition.reverse {
							term = candidate
							definition = candidate_definition
							break
						}
					}
					if len(term) == 0 do return .Invalid_Expanded_JSON
					values, values_valid := array_from_value(reverse[predicate])
					if !values_valid do return .Invalid_Expanded_JSON
					if !first do strings.write_string(builder, ", ")
					write_json_string(builder, term)
					strings.write_string(builder, ": ")
					if policy == .Compact && len(values) == 1 && !definition.container_set {
						node, node_valid := object_from_value(values[0])
						if !node_valid do return .Invalid_Expanded_JSON
						if err := frame_compact_write_node(builder, state, ctx, node, policy); err != .None do return err
					} else {
						strings.write_byte(builder, '[')
						for item, item_index in values {
							if item_index > 0 do strings.write_string(builder, ", ")
							node, node_valid := object_from_value(item)
							if !node_valid do return .Invalid_Expanded_JSON
							if err := frame_compact_write_node(builder, state, ctx, node, policy); err != .None do return err
						}
						strings.write_byte(builder, ']')
					}
					first = false
				}
				delete(reverse_keys)
				continue
			}
			delete(reverse_keys)
		}
		if state.prune_frame_blank_ids && key == "@id" {
			id, valid := string_value(value)
			if valid && len(id) >= 2 && id[0:2] == "_:" && !state.referenced_frame_blank_ids[id] {
				// Allocate the canonical label even when the ID is pruned: later
				// references must retain the node-map's relative blank-node order.
				if _, err := compact_iri(state, ctx, id, false); err != .None do return err
				continue
			}
		}
		compacted_key := ""
		definition: Term_Definition
		has_definition := false
		if is_keyword(key) {
			compacted_key = compact_keyword(ctx, key)
			for _, candidate_definition in ctx.terms {
				if candidate_definition.id != key do continue
				definition = candidate_definition
				has_definition = true
				break
			}
		} else {
			array, valid := array_from_value(value)
			if !valid do return .Invalid_Expanded_JSON
			err: Compact_Error
			compacted_key, definition, has_definition, err = compact_property_term(state, ctx, key, array)
			if err != .None {
				// JSON-LD 1.0 framing retains an input property that looks like a
				// compact IRI, even when the output context would reinterpret that
				// spelling as a different IRI. This is the legacy CURIE-conflict
				// compaction rule (W3C framing-0010).
				if state.legacy_prefixes && err == .Invalid_Context && has_iri_scheme(key) {
					compacted_key = key
					definition = {}
					has_definition = false
				} else {
					return err
				}
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
			if policy == .Compact && len(array) == 1 {
				node, node_valid := object_from_value(array[0])
				if !node_valid do return .Invalid_Expanded_JSON
				if err := frame_compact_write_node(builder, state, ctx, node, policy); err != .None do return err
			} else {
				strings.write_byte(builder, '[')
				for item, index in array {
					if index > 0 do strings.write_string(builder, ", ")
					node, node_valid := object_from_value(item)
					if !node_valid do return .Invalid_Expanded_JSON
					if err := frame_compact_write_node(builder, state, ctx, node, policy); err != .None do return err
				}
				strings.write_byte(builder, ']')
			}
		} else if key == "@reverse" {
			reverse, reverse_valid := object_from_value(value)
			if !reverse_valid do return .Invalid_Expanded_JSON
			if err := frame_compact_write_reverse(builder, state, ctx, reverse, policy); err != .None do return err
		} else {
			array, valid := array_from_value(value)
			if !valid do return .Invalid_Expanded_JSON
			if has_definition && definition.container_language {
				if err := compact_write_language_map(builder, state, ctx, object, key, array, policy); err != .None do return err
			} else if has_definition && definition.container_list && len(array) == 1 {
				item, item_valid := object_from_value(array[0])
				list, has_list := object_value(item, "@list")
				if !item_valid || !has_list do return .Invalid_Expanded_JSON
				if err := frame_compact_write_list(builder, state, ctx, list, definition, has_definition, policy); err != .None do return err
			} else if policy == .Compact && len(array) == 1 && (!has_definition || !definition.container_set) {
				if err := frame_compact_write_value(builder, state, ctx, array[0], definition, has_definition, policy); err != .None do return err
			} else {
				strings.write_byte(builder, '[')
				for item, index in array {
					if index > 0 do strings.write_string(builder, ", ")
					if err := frame_compact_write_value(builder, state, ctx, item, definition, has_definition, policy); err != .None do return err
				}
				strings.write_byte(builder, ']')
			}
		}
		first = false
	}
	strings.write_byte(builder, '}')
	return .None
}

// frame atomically writes the initial bounded JSON-LD Framing profile. It
// supports @id/@type/property matching and recursive property embedding; the
// complete policy matrix is intentionally rejected until it is implemented.
frame :: proc(builder: ^strings.Builder, input, frame_text: string, options: Frame_Options = {}) -> Frame_Error {
	if !utf8.valid_string(input) || !utf8.valid_string(frame_text) do return .Invalid_UTF8
	max_nodes := options.max_nodes
	if max_nodes == 0 do max_nodes = DEFAULT_MAX_FLATTEN_NODES
	max_depth := options.max_embedding_depth
	if max_depth == 0 do max_depth = DEFAULT_MAX_FRAME_EMBEDDING_DEPTH
	max_output := options.max_output_bytes
	if max_output == 0 do max_output = DEFAULT_MAX_EXPANDED_OUTPUT_BYTES
	if max_nodes < 0 || max_depth <= 0 || max_output < 0 do return .Invalid_Option
	intermediate_max := max_output
	if intermediate_max < DEFAULT_MAX_EXPANDED_OUTPUT_BYTES do intermediate_max = DEFAULT_MAX_EXPANDED_OUTPUT_BYTES
	raw_frame_document, raw_frame_json_error := json.parse_string(strings.trim_space(frame_text), .JSON, true)
	if raw_frame_json_error != .None do return .Invalid_JSON
	defer json.destroy_value(raw_frame_document)
	raw_frame, raw_frame_valid := object_from_value(raw_frame_document)
	if !raw_frame_valid do return .Invalid_Frame
	if frame_has_blank_match(raw_frame_document) do return .Invalid_Frame
	if frame_has_unsupported_policy(raw_frame_document) do return .Unsupported_Feature
	active_context, has_context := object_value(raw_frame, "@context")
	context_options := options.context_options
	// Framing exposes its processing mode separately from the shared context
	// limits. Keep every internal Expansion, Flattening, and compaction-context
	// pass in that same mode; otherwise a JSON-LD 1.0 frame is expanded as 1.1
	// and can be rejected before matching begins.
	if options.processing_mode == .Json_LD_1_0 do context_options.processing_mode = .Json_LD_1_0
	max_contexts := context_options.max_contexts
	if max_contexts == 0 do max_contexts = DEFAULT_MAX_CONTEXTS
	max_remote := context_options.max_remote_contexts
	if max_remote == 0 do max_remote = DEFAULT_MAX_REMOTE_CONTEXTS
	state := State{remote_urls = make(map[string]bool), named_bnodes = make(map[string]rdf.Term), referenced_frame_blank_ids = make(map[string]bool), frame_blank_aliases = make(map[string]string), max_contexts = max_contexts, max_remote = max_remote, loader = context_options.document_loader, loader_data = context_options.loader_data, allow_document_containers = context_options.processing_mode != .Json_LD_1_0, allow_direction = context_options.processing_mode != .Json_LD_1_0, legacy_prefixes = context_options.processing_mode == .Json_LD_1_0, prune_frame_blank_ids = options.processing_mode == .Json_LD_1_1, canonical_frame_blank_ids = options.processing_mode == .Json_LD_1_1}
	defer destroy_state(&state)
	ctx, context_error := make_context(&state, nil)
	if context_error.code != .None do return frame_from_context_error(context_error)
	retain_context(&state, ctx)
	if len(context_options.base_iri) > 0 {
		if !has_iri_scheme(context_options.base_iri) do return .Invalid_Context
		base, base_error := resolve_iri(&state, context_options.base_iri, "")
		if base_error.code != .None do return frame_from_context_error(base_error)
		ctx.base_iri = base
	}
	if has_context {
		ctx, context_error = apply_context(&state, &ctx, active_context)
		if context_error.code != .None do return frame_from_context_error(context_error)
	}

	flattened := strings.builder_make()
	defer strings.builder_destroy(&flattened)
	if err := flatten(&flattened, input, Flatten_Options{context_options = context_options, max_nodes = max_nodes, max_output_bytes = intermediate_max, retain_reference_nodes = true}); err != .None do return frame_from_flatten_error(err)
	flat_document, flat_json_error := json.parse_string(strings.to_string(flattened), .JSON, true)
	if flat_json_error != .None do return .Invalid_JSON
	defer json.destroy_value(flat_document)
	flat_nodes, flat_valid := array_from_value(flat_document)
	if !flat_valid do return .Invalid_JSON
	node_map := frame_make_node_map(flat_nodes)
	node_map.legacy_prefixes = context_options.processing_mode == .Json_LD_1_0
	defer frame_destroy_node_map(&node_map)

	expanded_frame := strings.builder_make()
	defer strings.builder_destroy(&expanded_frame)
	if err := expand_frame(&expanded_frame, frame_text, Expand_Options{context_options = context_options, max_output_bytes = intermediate_max}); err != .None do return frame_from_expand_error(err)
	expanded_frame_document, expanded_frame_json_error := json.parse_string(strings.to_string(expanded_frame), .JSON, true)
	if expanded_frame_json_error != .None do return .Invalid_Frame
	defer json.destroy_value(expanded_frame_document)
	expanded_frame_items, expanded_frame_valid := array_from_value(expanded_frame_document)
	if !expanded_frame_valid || len(expanded_frame_items) != 1 do return .Invalid_Frame
	expanded_root_frame, root_frame_valid := object_from_value(expanded_frame_items[0])
	if !root_frame_valid do return .Invalid_Frame

	embedded := strings.builder_make()
	defer strings.builder_destroy(&embedded)
	strings.write_byte(&embedded, '[')
	first := true
	embeds := make([dynamic]string)
	defer delete(embeds)
	embedding_state := frame_make_embedding_state(&node_map)
	defer frame_destroy_embedding_state(&embedding_state)
	root_embed_mode := frame_embed_mode(expanded_root_frame)
	for node in node_map.nodes {
		if !frame_matches_node_in_map(&node_map, node, expanded_root_frame) do continue
		id_value, has_id := object_value(node, "@id")
		id, id_valid := string_value(id_value)
		if !has_id || !id_valid do return .Invalid_Frame
		if !first do strings.write_string(&embedded, ", ")
		if len(embeds) >= max_depth do return .Embedding_Limit
		append(&embeds, id)
		if err := frame_write_node(&embedded, &node_map, &ctx, node, expanded_root_frame, root_embed_mode, &embedding_state, &embeds, max_depth, {}, false); err != .None do return err
		pop(&embeds)
		first = false
	}
	strings.write_byte(&embedded, ']')
	embedded_document, embedded_json_error := json.parse_string(strings.to_string(embedded), .JSON, true)
	if embedded_json_error != .None do return .Invalid_Frame
	defer json.destroy_value(embedded_document)
	embedded_nodes, embedded_valid := array_from_value(embedded_document)
	if !embedded_valid do return .Invalid_Frame
	seen_frame_blank_ids := make(map[string]bool)
	defer delete(seen_frame_blank_ids)
	frame_mark_embedded_blank_references(&state, embedded_document, &seen_frame_blank_ids)

	temporary := strings.builder_make()
	defer strings.builder_destroy(&temporary)
	strings.write_string(&temporary, "{\n")
	if has_context {
		strings.write_string(&temporary, "  \"@context\": ")
		if !compact_write_raw_json(&temporary, active_context) do return .Invalid_Context
		strings.write_string(&temporary, ",\n")
	}
	omit_graph := options.omit_graph
	if !options.omit_graph_set do omit_graph = options.processing_mode == .Json_LD_1_1
	if omit_graph && len(embedded_nodes) == 1 {
		node, node_valid := object_from_value(embedded_nodes[0])
		if !node_valid do return .Invalid_Frame
		compacted := strings.builder_make()
		defer strings.builder_destroy(&compacted)
		if err := frame_compact_write_node(&compacted, &state, &ctx, node, options.array_policy); err != .None do return .Invalid_Frame
		compacted_node := strings.to_string(compacted)
		if len(compacted_node) > 2 {
			strings.write_string(&temporary, "  ")
			strings.write_string(&temporary, compacted_node[1:len(compacted_node) - 1])
			strings.write_byte(&temporary, '\n')
		}
		strings.write_string(&temporary, "}\n")
		if len(strings.to_string(temporary)) > max_output do return .Output_Too_Large
		strings.write_string(builder, strings.to_string(temporary))
		return .None
	}
	strings.write_string(&temporary, "  \"@graph\": [")
	for value, index in embedded_nodes {
		if index > 0 do strings.write_string(&temporary, ",\n")
		node, node_valid := object_from_value(value)
		if !node_valid do return .Invalid_Frame
		strings.write_string(&temporary, "\n    ")
		if err := frame_compact_write_node(&temporary, &state, &ctx, node, options.array_policy); err != .None do return .Invalid_Frame
	}
	if len(embedded_nodes) == 0 {
		strings.write_string(&temporary, "]\n}\n")
	} else {
		strings.write_byte(&temporary, '\n')
		strings.write_string(&temporary, "  ]\n}\n")
	}
	if len(strings.to_string(temporary)) > max_output do return .Output_Too_Large
	strings.write_string(builder, strings.to_string(temporary))
	return .None
}
