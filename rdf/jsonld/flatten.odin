// Document-level JSON-LD flattening over the package's bounded Expansion
// result. It intentionally does not route through RDF: @index and list
// objects are JSON-LD document data and would otherwise be lost.
package jsonld

import json "core:encoding/json"
import "core:sort"
import "core:strings"
import rdf ".."

Flatten_Error :: enum {
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
	Unsupported_Feature,
	Node_Limit,
	Output_Too_Large,
	Out_Of_Memory,
}

flatten_error_message :: proc(code: Flatten_Error) -> string {
	switch code {
	case .None:                       return "no error"
	case .Invalid_Option:             return "flattening options are invalid"
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
	case .Unsupported_Feature:        return "unsupported JSON-LD flattening feature"
	case .Node_Limit:                 return "flattened node limit reached"
	case .Output_Too_Large:           return "flattened JSON-LD exceeds configured byte limit"
	case .Out_Of_Memory:              return "memory allocation failed"
	}
	return "unknown error"
}

// Flatten_Options reuses Expansion's input and local-context limits. The
// node cap bounds the retained default-graph node-map; the output cap bounds
// the atomic result appended to the caller's builder. When output_context is
// supplied, Flatten compacts the resulting expanded node map using that
// context; array_policy controls JSON-LD's compactArrays behavior there.
Flatten_Options :: struct {
	context_options:  Options,
	max_nodes:        int,
	max_output_bytes: int,
	output_context:   string,
	array_policy:     Compact_Array_Policy,
	retain_reference_nodes: bool,
}

DEFAULT_MAX_FLATTEN_NODES :: 100_000

@(private) Flatten_Node :: struct {
	id:          string,
	id_owned:    bool,
	properties:  [dynamic]Expand_Property,
	has_content: bool,
	processing:  bool,
}

@(private) Flatten_State :: struct {
	nodes:           [dynamic]Flatten_Node,
	by_id:           map[string]int,
	blank_ids:       map[string]string,
	blank_id_values: [dynamic]string,
	generated:       u64,
	max_nodes:       int,
	retain_reference_nodes: bool,
	outer:           ^Flatten_State,
}

@(private) flatten_destroy_state :: proc(state: ^Flatten_State) {
	for &node in state.nodes {
		if node.id_owned do delete(node.id)
		expand_destroy_properties(&node.properties)
	}
	delete(state.nodes)
	delete(state.by_id)
	for value in state.blank_id_values do delete(value)
	delete(state.blank_id_values)
	delete(state.blank_ids)
}

@(private) flatten_from_expand_error :: proc(code: Expand_Error) -> Flatten_Error {
	#partial switch code {
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

@(private) flatten_from_compact_error :: proc(code: Compact_Error) -> Flatten_Error {
	#partial switch code {
	case .None:                 return .None
	case .Invalid_Option:       return .Invalid_Option
	case .Invalid_UTF8:         return .Invalid_UTF8
	case .Context_Too_Large:    return .Document_Too_Large
	case .Context_Nesting_Limit:return .Nesting_Limit
	case .Context_Limit:        return .Context_Limit
	case .Invalid_Context:      return .Invalid_Context
	case .Unsupported_Context:  return .Unsupported_Feature
	case .Invalid_Expanded_JSON:return .Invalid_JSON
	case .Out_Of_Memory:        return .Out_Of_Memory
	case:                       return .Unsupported_Feature
	}
}

@(private) flatten_clone_builder :: proc(builder: ^strings.Builder) -> (string, Flatten_Error) {
	copy, clone_error := strings.clone(strings.to_string(builder^))
	if clone_error != nil do return "", .Out_Of_Memory
	return copy, .None
}

@(private) flatten_raw_json :: proc(value: json.Value) -> (string, Flatten_Error) {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	if !compact_write_raw_json(&builder, value) do return "", .Invalid_Value_Object
	return flatten_clone_builder(&builder)
}

@(private) flatten_generated_id :: proc(state: ^Flatten_State) -> (string, Flatten_Error) {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	strings.write_string(&builder, "_:b")
	strings.write_u64(&builder, state.generated)
	state.generated += 1
	return flatten_clone_builder(&builder)
}

// flatten_blank_identifier maps source blank-node labels to the issued
// identifiers used by the node-map algorithm. Source labels are document
// syntax, not output identifiers: explicit labels and anonymous nodes share a
// single sequential issuer (W3C 0038/0045).
@(private) flatten_blank_identifier :: proc(state: ^Flatten_State, id: string) -> (string, Flatten_Error) {
	if !strings.has_prefix(id, "_:") do return id, .None
	if issued, found := state.blank_ids[id]; found do return issued, .None
	issued, err := flatten_generated_id(state)
	if err != .None do return "", err
	append(&state.blank_id_values, issued)
	state.blank_ids[id] = issued
	return issued, .None
}

@(private) flatten_get_or_create_node :: proc(state: ^Flatten_State, id: string, owned: bool) -> (int, Flatten_Error) {
	if index, found := state.by_id[id]; found {
		if owned do delete(id)
		return index, .None
	}
	if len(state.nodes) >= state.max_nodes {
		if owned do delete(id)
		return -1, .Node_Limit
	}
	index := len(state.nodes)
	append(&state.nodes, Flatten_Node{id = id, id_owned = owned, properties = make([dynamic]Expand_Property)})
	state.by_id[id] = index
	return index, .None
}

@(private) flatten_merge_values :: proc(left, right: string) -> (string, Flatten_Error) {
	left_value, left_error := json.parse_string(left, .JSON, true)
	if left_error != .None do return "", .Invalid_Value_Object
	defer json.destroy_value(left_value)
	right_value, right_error := json.parse_string(right, .JSON, true)
	if right_error != .None do return "", .Invalid_Value_Object
	defer json.destroy_value(right_value)
	left_items, left_valid := array_from_value(left_value)
	right_items, right_valid := array_from_value(right_value)
	if !left_valid || !right_valid do return "", .Invalid_Value_Object
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	seen := make([dynamic]string)
	defer {
		for item in seen do delete(item)
		delete(seen)
	}
	strings.write_byte(&builder, '[')
	written := 0
	for source_index in 0..<2 {
		source := source_index == 0 ? left_items : right_items
		for item in source {
			temporary := strings.builder_make()
			if !compact_write_raw_json(&temporary, item) {
				strings.builder_destroy(&temporary)
				return "", .Invalid_Value_Object
			}
			text, clone_error := strings.clone(strings.to_string(temporary))
			strings.builder_destroy(&temporary)
			if clone_error != nil do return "", .Out_Of_Memory
			duplicate := false
			for prior in seen {
				if prior == text { duplicate = true; break }
			}
			if duplicate {
				delete(text)
				continue
			}
			if written > 0 do strings.write_string(&builder, ", ")
			strings.write_string(&builder, text)
			append(&seen, text)
			written += 1
		}
	}
	strings.write_byte(&builder, ']')
	return flatten_clone_builder(&builder)
}

@(private) flatten_add_property :: proc(state: ^Flatten_State, node_index: int, key, value: string, content := true) -> Flatten_Error {
	node := &state.nodes[node_index]
	for &property in node.properties {
		if property.key != key do continue
		merged, merge_error := flatten_merge_values(property.value, value)
		if merge_error != .None do return merge_error
		delete(property.value)
		property.value = merged
		if content do node.has_content = true
		return .None
	}
	if err := expand_append_property(&node.properties, key, value); err != .None do return .Out_Of_Memory
	if content do node.has_content = true
	return .None
}

@(private) flatten_set_scalar :: proc(state: ^Flatten_State, node_index: int, key, value: string) -> Flatten_Error {
	node := &state.nodes[node_index]
	for &property in node.properties {
		if property.key != key do continue
		// Node-map merging permits one @index for an identifier. A second,
		// different index is an expansion error rather than a last-write-wins
		// update (W3C flatten-e001).
		if property.value != value do return .Invalid_Value_Object
		return .None
	}
	key_copy, key_error := strings.clone(key)
	if key_error != nil do return .Out_Of_Memory
	value_copy, value_error := strings.clone(value)
	if value_error != nil {
		delete(key_copy)
		return .Out_Of_Memory
	}
	append(&node.properties, Expand_Property{key = key_copy, value = value_copy})
	node.has_content = true
	return .None
}

@(private) flatten_node_id :: proc(state: ^Flatten_State, object: json.Object) -> (int, Flatten_Error) {
	if id_value, has_id := object_value(object, "@id"); has_id {
		id, valid := string_value(id_value)
		if !valid do return -1, .Invalid_IRI
		if strings.has_prefix(id, "_:") {
			issued, issued_err := flatten_blank_identifier(state, id)
			if issued_err != .None do return -1, issued_err
			return flatten_get_or_create_node(state, issued, false)
		}
		return flatten_get_or_create_node(state, id, false)
	}
	id, err := flatten_generated_id(state)
	if err != .None do return -1, err
	return flatten_get_or_create_node(state, id, true)
}

@(private) flatten_visit_types :: proc(builder: ^strings.Builder, state: ^Flatten_State, value: json.Value) -> Flatten_Error {
	strings.write_byte(builder, '[')
	values, array := array_from_value(value)
	count := array ? len(values) : 1
	for index in 0..<count {
		if index > 0 do strings.write_string(builder, ", ")
		item := array ? values[index] : value
		if type_id, is_string := string_value(item); is_string && strings.has_prefix(type_id, "_:") {
			issued, issued_err := flatten_blank_identifier(state, type_id)
			if issued_err != .None do return issued_err
			write_json_string(builder, issued)
		} else if !compact_write_raw_json(builder, item) do return .Invalid_Value_Object
	}
	strings.write_byte(builder, ']')
	return .None
}

@(private) flatten_write_reference :: proc(builder: ^strings.Builder, id: string) {
	strings.write_string(builder, `{"@id": `)
	write_json_string(builder, id)
	strings.write_byte(builder, '}')
}

@(private) flatten_visit_value :: proc(builder: ^strings.Builder, state: ^Flatten_State, value: json.Value) -> Flatten_Error {
	if object, is_object := object_from_value(value); is_object {
		if _, is_value := object_value(object, "@value"); is_value {
			if !compact_write_raw_json(builder, value) do return .Invalid_Value_Object
			return .None
		}
		if _, is_list := object_value(object, "@list"); is_list do return flatten_visit_list(builder, state, object)
		if set, is_set := object_value(object, "@set"); is_set do return flatten_visit_values(builder, state, set)
		target_state := state
		// A graph object encountered while building a named graph names a graph
		// in the enclosing graph, so its holder node belongs to that outer map.
		if _, has_graph := object_value(object, "@graph"); has_graph && state.outer != nil do target_state = state.outer
		node_index, node_err := flatten_node_id(target_state, object)
		if node_err != .None do return node_err
		if target_state.retain_reference_nodes do target_state.nodes[node_index].has_content = true
		if process_err := flatten_process_node(target_state, node_index, object); process_err != .None do return process_err
		flatten_write_reference(builder, target_state.nodes[node_index].id)
		return .None
	}
	if !compact_write_raw_json(builder, value) do return .Invalid_Value_Object
	return .None
}

@(private) flatten_visit_values :: proc(builder: ^strings.Builder, state: ^Flatten_State, value: json.Value, deduplicate := true) -> Flatten_Error {
	strings.write_byte(builder, '[')
	first := true
	seen := make([dynamic]string)
	defer {
		for item in seen do delete(item)
		delete(seen)
	}
	if array, is_array := array_from_value(value); is_array {
		for item in array {
			temporary := strings.builder_make()
			err := flatten_visit_value(&temporary, state, item)
			if err != .None {
				strings.builder_destroy(&temporary)
				return err
			}
			text, clone_err := strings.clone(strings.to_string(temporary))
			strings.builder_destroy(&temporary)
			if clone_err != nil do return .Out_Of_Memory
			item_is_list := false
			if object, is_object := object_from_value(item); is_object {
				_, item_is_list = object_value(object, "@list")
			}
			duplicate := false
			if deduplicate && !item_is_list {
				for prior in seen {
					if prior == text { duplicate = true; break }
				}
			}
			if duplicate {
				delete(text)
				continue
			}
			if !first do strings.write_string(builder, ", ")
			strings.write_string(builder, text)
			if deduplicate && !item_is_list {
				append(&seen, text)
			} else {
				delete(text)
			}
			first = false
		}
	} else {
		if err := flatten_visit_value(builder, state, value); err != .None do return err
	}
	strings.write_byte(builder, ']')
	return .None
}

@(private) flatten_visit_list :: proc(builder: ^strings.Builder, state: ^Flatten_State, object: json.Object) -> Flatten_Error {
	list, found := object_value(object, "@list")
	if !found do return .Invalid_List_Object
	strings.write_string(builder, `{"@list": `)
	if err := flatten_visit_values(builder, state, list, false); err != .None do return err
	if index, has_index := object_value(object, "@index"); has_index {
		strings.write_string(builder, `, "@index": `)
		if !compact_write_raw_json(builder, index) do return .Invalid_List_Object
	}
	strings.write_byte(builder, '}')
	return .None
}

@(private) flatten_process_reverse :: proc(state: ^Flatten_State, node_index: int, value: json.Value) -> Flatten_Error {
	reverse, valid := object_from_value(value)
	if !valid do return .Invalid_Reverse_Property
	keys := expand_sorted_keys(reverse)
	defer delete(keys)
	for key in keys {
		output_key := key
		if strings.has_prefix(key, "_:") {
			issued, issued_err := flatten_blank_identifier(state, key)
			if issued_err != .None do return issued_err
			output_key = issued
		}
		values, is_array := array_from_value(reverse[key])
		count := is_array ? len(values) : 1
		for index in 0..<count {
			item := is_array ? values[index] : reverse[key]
			item_object, is_node := object_from_value(item)
			if !is_node do return .Invalid_Reverse_Property
			target, node_err := flatten_node_id(state, item_object)
			if node_err != .None do return node_err
			if process_err := flatten_process_node(state, target, item_object); process_err != .None do return process_err
			reference := strings.builder_make()
			strings.write_byte(&reference, '[')
			flatten_write_reference(&reference, state.nodes[node_index].id)
			strings.write_byte(&reference, ']')
			add_err := flatten_add_property(state, target, output_key, strings.to_string(reference))
			strings.builder_destroy(&reference)
			if add_err != .None do return add_err
		}
	}
	return .None
}

@(private) flatten_write_graph :: proc(builder: ^strings.Builder, parent: ^Flatten_State, value: json.Value) -> Flatten_Error {
	graph := Flatten_State{nodes = make([dynamic]Flatten_Node), by_id = make(map[string]int), blank_ids = make(map[string]string), generated = parent.generated, max_nodes = parent.max_nodes, outer = parent}
	defer flatten_destroy_state(&graph)
	values, is_array := array_from_value(value)
	count := is_array ? len(values) : 1
	for index in 0..<count {
		item := is_array ? values[index] : value
		object, is_node := object_from_value(item)
		if !is_node do continue
		if _, is_value := object_value(object, "@value"); is_value do continue
		if _, is_list := object_value(object, "@list"); is_list do continue
		node_index, node_err := flatten_node_id(&graph, object)
		if node_err != .None do return node_err
		if process_err := flatten_process_node(&graph, node_index, object); process_err != .None do return process_err
	}
	indexes := make([dynamic]int)
	defer delete(indexes)
	for node, index in graph.nodes {
		if node.has_content do append(&indexes, index)
	}
	flatten_sort_node_indexes(&indexes, &graph)
	strings.write_byte(builder, '[')
	for index, output_index in indexes {
		if output_index > 0 do strings.write_string(builder, ", ")
		flatten_write_node(builder, &graph.nodes[index])
	}
	strings.write_byte(builder, ']')
	parent.generated = graph.generated
	return .None
}

@(private) flatten_process_node :: proc(state: ^Flatten_State, node_index: int, object: json.Object) -> Flatten_Error {
	// A node may reference itself, directly or through a cycle. The node-map
	// already owns its identity, so recursive encounters only need a reference.
	if state.nodes[node_index].processing do return .None
	state.nodes[node_index].processing = true
	defer state.nodes[node_index].processing = false
	keys := expand_sorted_keys(object)
	defer delete(keys)
	for key in keys {
		if key == "@id" do continue
		value := object[key]
		output_key := key
		if strings.has_prefix(key, "_:") {
			issued, issued_err := flatten_blank_identifier(state, key)
			if issued_err != .None do return issued_err
			output_key = issued
		}
		if key == "@reverse" {
			if err := flatten_process_reverse(state, node_index, value); err != .None do return err
			continue
		}
		if key == "@index" {
			raw, err := flatten_raw_json(value)
			if err != .None do return err
			err = flatten_set_scalar(state, node_index, key, raw)
			delete(raw)
			if err != .None do return err
			continue
		}
		if key == "@graph" {
			temporary := strings.builder_make()
			err := flatten_write_graph(&temporary, state, value)
			if err == .None do err = flatten_add_property(state, node_index, output_key, strings.to_string(temporary))
			strings.builder_destroy(&temporary)
			if err != .None do return err
			continue
		}
		if key == "@included" {
			// Included nodes are merged into the active node map but @included is
			// not retained as a property in flattened JSON-LD. Visiting the values
			// recursively also handles included blocks inside included nodes.
			temporary := strings.builder_make()
			err := flatten_visit_values(&temporary, state, value)
			strings.builder_destroy(&temporary)
			if err != .None do return err
			continue
		}
		if key == "@type" {
			temporary := strings.builder_make()
			err := flatten_visit_types(&temporary, state, value)
			if err == .None do err = flatten_add_property(state, node_index, output_key, strings.to_string(temporary))
			strings.builder_destroy(&temporary)
			if err != .None do return err
			continue
		}
		temporary := strings.builder_make()
		err := flatten_visit_values(&temporary, state, value)
		if err == .None do err = flatten_add_property(state, node_index, output_key, strings.to_string(temporary), key != "@index")
		strings.builder_destroy(&temporary)
		if err != .None do return err
	}
	return .None
}

@(private) Flatten_Sort_Context :: struct {
	indexes: ^[dynamic]int,
	state:   ^Flatten_State,
}

@(private) flatten_sort_node_indexes :: proc(indexes: ^[dynamic]int, state: ^Flatten_State) {
	sort_context := Flatten_Sort_Context{indexes = indexes, state = state}
	sort.sort(sort.Interface{
		collection = rawptr(&sort_context),
		len = proc(it: sort.Interface) -> int {
			ctx := cast(^Flatten_Sort_Context)it.collection
			return len(ctx.indexes^)
		},
		less = proc(it: sort.Interface, i, j: int) -> bool {
			ctx := cast(^Flatten_Sort_Context)it.collection
			return strings.compare(ctx.state.nodes[ctx.indexes[i]].id, ctx.state.nodes[ctx.indexes[j]].id) < 0
		},
		swap = proc(it: sort.Interface, i, j: int) {
			ctx := cast(^Flatten_Sort_Context)it.collection
			ctx.indexes[i], ctx.indexes[j] = ctx.indexes[j], ctx.indexes[i]
		},
	})
}

@(private) flatten_write_node :: proc(builder: ^strings.Builder, node: ^Flatten_Node) {
	strings.write_byte(builder, '{')
	first := true
	expand_write_member_prefix(builder, &first, "@id")
	write_json_string(builder, node.id)
	expand_sort_properties(&node.properties)
	for property in node.properties {
		expand_write_member_prefix(builder, &first, property.key)
		strings.write_string(builder, property.value)
	}
	strings.write_byte(builder, '}')
}

// flatten_write_compacted_result applies Flatten's optional output context to
// the already-expanded node map. It deliberately reuses Compaction's
// expanded-node writer instead of round-tripping through RDF, because Flatten
// must retain JSON-LD-only data such as @index and list objects.
@(private) flatten_write_compacted_result :: proc(builder: ^strings.Builder, nodes: json.Array, context_text: string, options: Flatten_Options, max_output: int) -> Flatten_Error {
	if len(context_text) > max_output do return .Document_Too_Large
	parsed_context, json_error := json.parse_string(strings.trim_space(context_text), .JSON, true)
	if json_error != .None do return .Invalid_Context
	defer json.destroy_value(parsed_context)
	active_context := parsed_context
	if context_document, is_document := object_from_value(parsed_context); is_document {
		if nested_context, has_nested_context := object_value(context_document, "@context"); has_nested_context do active_context = nested_context
	}
	context_options := options.context_options
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
		allow_document_containers = context_options.processing_mode != .Json_LD_1_0,
		allow_direction = context_options.processing_mode != .Json_LD_1_0,
		legacy_prefixes = context_options.processing_mode == .Json_LD_1_0,
		compact_source_graph_predicates = make(map[string]bool),
		compact_source_graph_boundary_predicates = make(map[string]bool),
		compact_source_inline_named_nodes = make(map[string]bool),
		compact_source_top_level_named_nodes = make(map[string]bool),
		compact_nodes = make(map[string]json.Object),
		compacting_nodes = make(map[string]bool),
		compacted_graph_nodes = make(map[string]bool),
		compacted_index_nodes = make(map[string]bool),
	}
	defer destroy_state(&state)
	ctx, context_error := make_context(&state, nil)
	if context_error.code != .None do return flatten_from_compact_error(compact_context_error(context_error))
	retain_context(&state, ctx)
	if len(context_options.base_iri) > 0 {
		if !has_iri_scheme(context_options.base_iri) do return .Invalid_Context
		base, base_error := resolve_iri(&state, context_options.base_iri, "")
		if base_error.code != .None do return flatten_from_compact_error(compact_context_error(base_error))
		ctx.base_iri = base
	}
	ctx, context_error = apply_context(&state, &ctx, active_context)
	if context_error.code != .None do return flatten_from_compact_error(compact_context_error(context_error))
	for value in nodes {
		node, node_valid := object_from_value(value)
		if !node_valid do return .Invalid_JSON
		identifier_value, has_identifier := object_value(node, "@id")
		identifier, identifier_valid := string_value(identifier_value)
		if has_identifier && identifier_valid do state.compact_nodes[identifier] = node
	}
	temporary := strings.builder_make()
	defer strings.builder_destroy(&temporary)
	if len(nodes) == 1 && options.array_policy == .Compact {
		node, node_valid := object_from_value(nodes[0])
		if !node_valid do return .Invalid_JSON
		node_builder := strings.builder_make()
		defer strings.builder_destroy(&node_builder)
		if compact_error := compact_write_node(&node_builder, &state, &ctx, node, options.array_policy); compact_error != .None do return flatten_from_compact_error(compact_error)
		strings.write_string(&temporary, "{\n  \"@context\": ")
		if !compact_write_raw_json(&temporary, active_context) do return .Invalid_Context
		compacted := strings.to_string(node_builder)
		if len(compacted) > 2 {
			strings.write_string(&temporary, ",\n  ")
			strings.write_string(&temporary, compacted[1:len(compacted) - 1])
		}
		strings.write_string(&temporary, "\n}\n")
	} else {
		strings.write_string(&temporary, "{\n  \"@context\": ")
		if !compact_write_raw_json(&temporary, active_context) do return .Invalid_Context
		strings.write_string(&temporary, ",\n  ")
		write_json_string(&temporary, compact_keyword(&ctx, "@graph"))
		strings.write_string(&temporary, ": [")
		for value, index in nodes {
			node, node_valid := object_from_value(value)
			if !node_valid do return .Invalid_JSON
			if index > 0 do strings.write_string(&temporary, ",\n")
			strings.write_string(&temporary, "\n    ")
			if compact_error := compact_write_node(&temporary, &state, &ctx, node, options.array_policy); compact_error != .None do return flatten_from_compact_error(compact_error)
		}
		if len(nodes) > 0 do strings.write_byte(&temporary, '\n')
		strings.write_string(&temporary, "  ]\n}\n")
	}
	if len(strings.to_string(temporary)) > max_output do return .Output_Too_Large
	strings.write_string(builder, strings.to_string(temporary))
	return .None
}

// flatten atomically appends deterministic default-graph flattened JSON-LD.
// It currently rejects named-graph node-map construction rather than emitting
// an RDF-shaped approximation; that profile is added after the default graph
// has its own conformance gate.
flatten :: proc(builder: ^strings.Builder, input: string, options: Flatten_Options = {}) -> Flatten_Error {
	max_nodes := options.max_nodes
	if max_nodes == 0 do max_nodes = DEFAULT_MAX_FLATTEN_NODES
	max_output := options.max_output_bytes
	if max_output == 0 do max_output = DEFAULT_MAX_EXPANDED_OUTPUT_BYTES
	if max_nodes < 0 || max_output < 0 do return .Invalid_Option
	expanded := strings.builder_make()
	defer strings.builder_destroy(&expanded)
	// Framing and flattening need referenced ID-only nodes in the node map.
	// Ordinary public expansion still omits those otherwise-empty objects.
	if err := expand_document(&expanded, input, Expand_Options{context_options = options.context_options, max_output_bytes = max_output}, true, false); err != .None do return flatten_from_expand_error(err)
	parsed, json_err := json.parse_string(strings.to_string(expanded), .JSON, true)
	if json_err != .None do return .Invalid_JSON
	defer json.destroy_value(parsed)
	root, valid := array_from_value(parsed)
	if !valid do return .Invalid_JSON
	state := Flatten_State{nodes = make([dynamic]Flatten_Node), by_id = make(map[string]int), blank_ids = make(map[string]string), max_nodes = max_nodes, retain_reference_nodes = options.retain_reference_nodes}
	defer flatten_destroy_state(&state)
	for item in root {
		object, is_node := object_from_value(item)
		if !is_node do continue
		if _, is_value := object_value(object, "@value"); is_value do continue
		if _, is_list := object_value(object, "@list"); is_list do continue
		node_index, node_err := flatten_node_id(&state, object)
		if node_err != .None do return node_err
		if options.retain_reference_nodes do state.nodes[node_index].has_content = true
		if process_err := flatten_process_node(&state, node_index, object); process_err != .None do return process_err
	}
	temporary := strings.builder_make()
	defer strings.builder_destroy(&temporary)
	indexes := make([dynamic]int)
	defer delete(indexes)
	for node, index in state.nodes {
		if node.has_content do append(&indexes, index)
	}
	flatten_sort_node_indexes(&indexes, &state)
	strings.write_byte(&temporary, '[')
	for index, output_index in indexes {
		if output_index > 0 do strings.write_string(&temporary, ", ")
		flatten_write_node(&temporary, &state.nodes[index])
	}
	strings.write_string(&temporary, "]\n")
	if len(options.output_context) > 0 {
		flattened_document, flattened_error := json.parse_string(strings.to_string(temporary), .JSON, true)
		if flattened_error != .None do return .Invalid_JSON
		defer json.destroy_value(flattened_document)
		flattened_nodes, flattened_valid := array_from_value(flattened_document)
		if !flattened_valid do return .Invalid_JSON
		compacted := strings.builder_make()
		defer strings.builder_destroy(&compacted)
		if compact_error := flatten_write_compacted_result(&compacted, flattened_nodes, options.output_context, options, max_output); compact_error != .None do return compact_error
		strings.write_string(builder, strings.to_string(compacted))
		return .None
	}
	if len(strings.to_string(temporary)) > max_output do return .Output_Too_Large
	strings.write_string(builder, strings.to_string(temporary))
	return .None
}
