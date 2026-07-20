// Deterministic RDF dataset to expanded JSON-LD serialization.
package jsonld

import json "core:encoding/json"
import "core:sort"
import "core:math"
import "core:strconv"
import "core:strings"
import "core:unicode/utf8"
import rdf ".."

// Serialize_Error reports structural and resource-policy failures while
// producing expanded JSON-LD. The serializer has no network behavior and
// builds the complete document before modifying the destination builder.
Serialize_Error :: enum {
	None,
	Invalid_Option,
	Invalid_Quad,
	Invalid_UTF8,
	Invalid_JSON_Literal,
	Quad_Limit,
	Ambiguous_Blank_Node_Label,
}

serialize_error_message :: proc(code: Serialize_Error) -> string {
	switch code {
	case .None:                       return "no error"
	case .Invalid_Option:             return "serializer limits must not be negative"
	case .Invalid_Quad:               return "invalid RDF quad"
	case .Invalid_UTF8:               return "RDF term contains invalid UTF-8"
	case .Invalid_JSON_Literal:       return "invalid rdf:JSON literal"
	case .Quad_Limit:                 return "JSON-LD serializer quad limit reached"
	case .Ambiguous_Blank_Node_Label: return "blank-node labels from different source scopes cannot be serialized together"
	}
	return "unknown error"
}

// Serialize_Options bounds a complete dataset serialization. Zero selects the
// safe default, because expanded JSON-LD output necessarily retains and sorts
// the whole dataset. A positive max_quads overrides it.
Serialize_Options :: struct {
	max_quads:        int,
	use_rdf_type:     bool,
	use_native_types: bool,
	rdf_direction:    RDF_Direction_Mode,
}

DEFAULT_MAX_SERIALIZE_QUADS :: 100_000

@(private) Serialization_State :: struct {
	quads:  []rdf.Quad,
	order:  [dynamic]int,
	groups: [dynamic]Node_Group,
	lists:  [dynamic]List_Info,
	compound_literals: [dynamic]Compound_Literal_Info,
	named_graphs:    [dynamic]rdf.Term,
	use_rdf_type:    bool,
	use_native_types: bool,
	rdf_direction:    RDF_Direction_Mode,
}

@(private) Node_Group :: struct {
	start: int,
	end:   int,
}

@(private) List_Info :: struct {
	valid:                bool,
	first:                rdf.Term,
	rest:                 rdf.Term,
	references:           int,
	local_non_rest_refs:  int,
	local_rest_refs:      int,
	next_same_node:       int,
	collapsed:            bool,
	head:                 bool,
}

@(private) Compound_Literal_Info :: struct {
	valid:     bool,
	value:     rdf.Term,
	language:  string,
	direction: string,
}

@(private) List_Node_Key :: struct {
	value: string,
	scope: rdf.Blank_Node_Scope,
}

@(private) serialization_term_equal :: proc(left, right: rdf.Term) -> bool {
	return left.kind == right.kind && left.value == right.value && left.language == right.language && left.datatype == right.datatype && left.scope == right.scope
}

@(private) serialization_term_compare :: proc(left, right: rdf.Term) -> int {
	if left.kind < right.kind do return -1
	if left.kind > right.kind do return 1
	if result := strings.compare(left.value, right.value); result != 0 do return result
	if result := strings.compare(left.language, right.language); result != 0 do return result
	if result := strings.compare(left.datatype, right.datatype); result != 0 do return result
	if left.scope < right.scope do return -1
	if left.scope > right.scope do return 1
	return 0
}

@(private) serialization_same_graph :: proc(left, right: rdf.Quad) -> bool {
	return left.has_graph == right.has_graph && (!left.has_graph || serialization_term_equal(left.graph, right.graph))
}

@(private) serialization_same_node :: proc(left, right: rdf.Quad) -> bool {
	return serialization_same_graph(left, right) && serialization_term_equal(left.subject, right.subject)
}

@(private) serialization_quad_equal :: proc(left, right: rdf.Quad) -> bool {
	return serialization_same_node(left, right) && serialization_term_equal(left.predicate, right.predicate) && serialization_term_equal(left.object, right.object)
}

@(private) serialization_sort_interface :: proc(state: ^Serialization_State) -> sort.Interface {
	return sort.Interface{
		collection = rawptr(state),
		len = proc(it: sort.Interface) -> int {
			state := cast(^Serialization_State)it.collection
			return len(state.order)
		},
		less = proc(it: sort.Interface, i, j: int) -> bool {
			state := cast(^Serialization_State)it.collection
			left, right := state.quads[state.order[i]], state.quads[state.order[j]]
			if left.has_graph != right.has_graph do return !left.has_graph
			if left.has_graph {
				if result := serialization_term_compare(left.graph, right.graph); result != 0 do return result < 0
			}
			if result := serialization_term_compare(left.subject, right.subject); result != 0 do return result < 0
			if result := serialization_term_compare(left.predicate, right.predicate); result != 0 do return result < 0
			return serialization_term_compare(left.object, right.object) < 0
		},
		swap = proc(it: sort.Interface, i, j: int) {
			state := cast(^Serialization_State)it.collection
			state.order[i], state.order[j] = state.order[j], state.order[i]
		},
	}
}

@(private) compare_group_key :: proc(left, right: rdf.Quad) -> int {
	if left.has_graph != right.has_graph do return left.has_graph ? 1 : -1
	if left.has_graph {
		if result := serialization_term_compare(left.graph, right.graph); result != 0 do return result
	}
	return serialization_term_compare(left.subject, right.subject)
}

@(private) build_node_groups :: proc(state: ^Serialization_State) {
	start := 0
	for start < len(state.order) {
		first := state.quads[state.order[start]]
		end := start + 1
		for end < len(state.order) && serialization_same_node(state.quads[state.order[end]], first) do end += 1
		append(&state.groups, Node_Group{start = start, end = end})
		start = end
	}
	for group in state.groups {
		quad := state.quads[state.order[group.start]]
		if !quad.has_graph do continue
		if len(state.named_graphs) == 0 || !serialization_term_equal(state.named_graphs[len(state.named_graphs) - 1], quad.graph) {
			append(&state.named_graphs, quad.graph)
		}
	}
}

@(private) is_named_graph :: proc(state: ^Serialization_State, term: rdf.Term) -> bool {
	left, right := 0, len(state.named_graphs)
	for left < right {
		middle := left + (right - left) / 2
		comparison := serialization_term_compare(state.named_graphs[middle], term)
		if comparison < 0 {
			left = middle + 1
		} else {
			right = middle
		}
	}
	return left < len(state.named_graphs) && serialization_term_equal(state.named_graphs[left], term)
}

// find_node_group performs a binary search over graph/subject groups. The
// sorted quad order keeps RDF list recognition bounded for large datasets.
@(private) find_node_group :: proc(state: ^Serialization_State, quad: rdf.Quad) -> int {
	left, right := 0, len(state.groups)
	for left < right {
		middle := left + (right - left) / 2
		candidate := state.quads[state.order[state.groups[middle].start]]
		comparison := compare_group_key(candidate, quad)
		if comparison < 0 {
			left = middle + 1
		} else {
			right = middle
		}
	}
	if left >= len(state.groups) do return -1
	candidate := state.quads[state.order[state.groups[left].start]]
	if compare_group_key(candidate, quad) != 0 do return -1
	return left
}

@(private) list_node_quad :: proc(node: rdf.Term, graph: rdf.Quad) -> rdf.Quad {
	return rdf.Quad{subject = node, graph = graph.graph, has_graph = graph.has_graph}
}

@(private) build_list_info :: proc(state: ^Serialization_State) {
	resize(&state.lists, len(state.groups))
	list_nodes := make(map[List_Node_Key]int)
	defer delete(list_nodes)
	for group, group_index in state.groups {
		first_quad := state.quads[state.order[group.start]]
		if first_quad.subject.kind != .Blank_Node do continue
		info := List_Info{valid = true, next_same_node = -1}
		first_count, rest_count := 0, 0
		previous: rdf.Quad
		has_previous := false
		for order_index in group.start..<group.end {
			quad := state.quads[state.order[order_index]]
			if has_previous && serialization_quad_equal(previous, quad) do continue
			previous = quad
			has_previous = true
			if quad.predicate.value == RDF_FIRST {
				first_count += 1
				info.first = quad.object
			} else if quad.predicate.value == RDF_REST {
				rest_count += 1
				info.rest = quad.object
			} else if quad.predicate.value == RDF_TYPE && quad.object.kind == .IRI && quad.object.value == RDF_LIST {
				// rdf:type rdf:List is permitted by the JSON-LD RDF algorithm.
			} else {
				info.valid = false
			}
		}
		if first_count != 1 || rest_count != 1 do info.valid = false
		state.lists[group_index] = info
		if info.valid {
			key := List_Node_Key{value = first_quad.subject.value, scope = first_quad.subject.scope}
			if previous_head, exists := list_nodes[key]; exists do state.lists[group_index].next_same_node = previous_head - 1
			list_nodes[key] = group_index + 1
		}
	}

	previous: rdf.Quad
	has_previous := false
	for order_index in state.order {
		quad := state.quads[order_index]
		if has_previous && serialization_quad_equal(previous, quad) do continue
		previous = quad
		has_previous = true
		if quad.object.kind != .Blank_Node do continue
		key := List_Node_Key{value = quad.object.value, scope = quad.object.scope}
		list_head, exists := list_nodes[key]
		if !exists do continue
		local_group := find_node_group(state, list_node_quad(quad.object, quad))
		for group_index := list_head - 1; group_index >= 0; group_index = state.lists[group_index].next_same_node {
			if group_index == local_group && quad.predicate.value == RDF_REST {
				state.lists[group_index].local_rest_refs += 1
				continue
			}
			state.lists[group_index].references += 1
			if group_index == local_group do state.lists[group_index].local_non_rest_refs += 1
		}
	}

	for group_index in 0..<len(state.groups) {
		info := state.lists[group_index]
		// A complete chain may start at a regular inbound reference, or at a
		// local rdf:rest when an earlier list node cannot be collapsed. The
		// latter preserves the standard algorithm's partial-list behavior.
		regular_head := info.references == 1 && info.local_non_rest_refs == 1
		partial_head := info.references == 0 && info.local_rest_refs == 1
		if !info.valid || !(regular_head || partial_head) do continue
		seen := make([dynamic]int)
		current := group_index
		collapsible := true
		for {
			if current < 0 || current >= len(state.groups) || !state.lists[current].valid {
				collapsible = false
				break
			}
			already_seen := false
			for node in seen do if node == current { already_seen = true; break }
			if already_seen {
				collapsible = false
				break
			}
			append(&seen, current)
			if current != group_index && state.lists[current].references != 0 {
				collapsible = false
				break
			}
			rest := state.lists[current].rest
			if rest.kind == .IRI && rest.value == RDF_NIL do break
			if rest.kind != .Blank_Node {
				collapsible = false
				break
			}
			graph := state.quads[state.order[state.groups[current].start]]
			current = find_node_group(state, list_node_quad(rest, graph))
		}
		if collapsible {
			state.lists[group_index].head = true
			for node in seen do state.lists[node].collapsed = true
		}
		delete(seen)
	}
}

@(private) is_plain_string_literal :: proc(term: rdf.Term) -> bool {
	return term.kind == .Literal && len(term.language) == 0 && term.datatype == rdf.XSD_STRING
}

@(private) build_compound_literal_info :: proc(state: ^Serialization_State) {
	resize(&state.compound_literals, len(state.groups))
	graph_names := make(map[List_Node_Key]bool)
	defer delete(graph_names)
	for quad in state.quads {
		if quad.has_graph && quad.graph.kind == .Blank_Node do graph_names[List_Node_Key{value = quad.graph.value, scope = quad.graph.scope}] = true
	}
	for group, group_index in state.groups {
		first := state.quads[state.order[group.start]]
		if first.subject.kind != .Blank_Node || graph_names[List_Node_Key{value = first.subject.value, scope = first.subject.scope}] do continue
		value_count, language_count, direction_count := 0, 0, 0
		candidate := true
		info: Compound_Literal_Info
		previous: rdf.Quad
		has_previous := false
		for order_index in group.start..<group.end {
			quad := state.quads[state.order[order_index]]
			if has_previous && serialization_quad_equal(previous, quad) do continue
			previous = quad
			has_previous = true
			if !is_plain_string_literal(quad.object) {
				candidate = false
				break
			}
			switch quad.predicate.value {
			case RDF_VALUE:
				value_count += 1
				info.value = quad.object
			case RDF_LANGUAGE:
				language_count += 1
				info.language = quad.object.value
			case RDF_DIRECTION:
				direction_count += 1
				info.direction = quad.object.value
			case:
				candidate = false
				break
			}
		}
		if candidate && value_count == 1 && language_count <= 1 && direction_count == 1 && (info.direction == "ltr" || info.direction == "rtl") {
			info.valid = true
		}
		state.compound_literals[group_index] = info
	}
}

@(private) compound_literal_group :: proc(state: ^Serialization_State, graph: rdf.Quad, term: rdf.Term) -> int {
	if state.rdf_direction != .Compound_Literal || term.kind != .Blank_Node do return -1
	group_index := find_node_group(state, list_node_quad(term, graph))
	if group_index < 0 || !state.compound_literals[group_index].valid do return -1
	return group_index
}

@(private) serialization_term_is_utf8 :: proc(term: rdf.Term) -> bool {
	return utf8.valid_string(term.value) && utf8.valid_string(term.language) && utf8.valid_string(term.datatype)
}

@(private) validate_serialization_input :: proc(quads: []rdf.Quad, max_quads: int) -> Serialize_Error {
	if len(quads) > max_quads do return .Quad_Limit
	labels := make(map[string]rdf.Blank_Node_Scope)
	defer delete(labels)
	for quad in quads {
		if rdf.validate_quad_structure(quad) != .None do return .Invalid_Quad
		terms := [4]rdf.Term{quad.subject, quad.predicate, quad.object, quad.graph}
		term_count := quad.has_graph ? 4 : 3
		for term in terms[:term_count] {
			if !serialization_term_is_utf8(term) do return .Invalid_UTF8
			if term.kind != .Blank_Node do continue
			if scope, exists := labels[term.value]; exists && scope != term.scope do return .Ambiguous_Blank_Node_Label
			labels[term.value] = term.scope
		}
	}
	return .None
}

@(private) write_json_string_content :: proc(builder: ^strings.Builder, value: string) {
	hex := "0123456789abcdef"
	for index in 0..<len(value) {
		byte := value[index]
		switch byte {
		case '"': strings.write_string(builder, `\"`)
		case '\\': strings.write_string(builder, `\\`)
		case '\b': strings.write_string(builder, `\b`)
		case '\f': strings.write_string(builder, `\f`)
		case '\n': strings.write_string(builder, `\n`)
		case '\r': strings.write_string(builder, `\r`)
		case '\t': strings.write_string(builder, `\t`)
		case:
			if byte < 0x20 {
				strings.write_string(builder, `\u00`)
				strings.write_byte(builder, hex[byte >> 4])
				strings.write_byte(builder, hex[byte & 0x0f])
			} else {
				strings.write_byte(builder, byte)
			}
		}
	}
}

@(private) write_json_string :: proc(builder: ^strings.Builder, value: string) {
	strings.write_byte(builder, '"')
	write_json_string_content(builder, value)
	strings.write_byte(builder, '"')
}

@(private) write_indent :: proc(builder: ^strings.Builder, count: int) {
	for _ in 0..<count do strings.write_byte(builder, ' ')
}

@(private) write_identifier :: proc(builder: ^strings.Builder, term: rdf.Term) {
	if term.kind == .Blank_Node {
		strings.write_byte(builder, '"')
		strings.write_string(builder, "_:")
		write_json_string_content(builder, term.value)
		strings.write_byte(builder, '"')
		return
	}
	write_json_string(builder, term.value)
}

@(private) write_list_value :: proc(builder: ^strings.Builder, state: ^Serialization_State, graph: rdf.Quad, term: rdf.Term) -> bool {
	if term.kind == .IRI && term.value == RDF_NIL {
		strings.write_string(builder, `{"@list": []}`)
		return true
	}
	if term.kind != .Blank_Node do return false
	group_index := find_node_group(state, list_node_quad(term, graph))
	if group_index < 0 || !state.lists[group_index].head do return false
	strings.write_string(builder, `{"@list": [`)
	current := group_index
	first_value := true
	for {
		if !first_value do strings.write_string(builder, ", ")
		current_quad := state.quads[state.order[state.groups[current].start]]
		write_value(builder, state, current_quad, state.lists[current].first)
		first_value = false
		rest := state.lists[current].rest
		if rest.kind == .IRI && rest.value == RDF_NIL do break
		current = find_node_group(state, list_node_quad(rest, current_quad))
		if current < 0 do break // Defensive: head classification proves this cannot occur.
	}
	strings.write_string(builder, `]}`)
	return true
}

@(private) write_compound_literal_value :: proc(builder: ^strings.Builder, state: ^Serialization_State, graph: rdf.Quad, term: rdf.Term) -> bool {
	group_index := compound_literal_group(state, graph, term)
	if group_index < 0 do return false
	info := state.compound_literals[group_index]
	strings.write_string(builder, `{"@value": `)
	write_json_string(builder, info.value.value)
	if len(info.language) > 0 {
		strings.write_string(builder, `, "@language": `)
		write_json_string(builder, info.language)
	}
	strings.write_string(builder, `, "@direction": `)
	write_json_string(builder, info.direction)
	strings.write_byte(builder, '}')
	return true
}

@(private) write_native_integer :: proc(builder: ^strings.Builder, lexical: string) -> bool {
	if len(lexical) == 0 do return false
	index := 0
	negative := false
	if lexical[index] == '+' || lexical[index] == '-' {
		negative = lexical[index] == '-'
		index += 1
	}
	if index == len(lexical) do return false
	first_digit := index
	for index < len(lexical) {
		if lexical[index] < '0' || lexical[index] > '9' do return false
		index += 1
	}
	for first_digit + 1 < len(lexical) && lexical[first_digit] == '0' do first_digit += 1
	if negative && !(len(lexical) - first_digit == 1 && lexical[first_digit] == '0') do strings.write_byte(builder, '-')
	strings.write_string(builder, lexical[first_digit:])
	return true
}

@(private) write_native_scalar :: proc(builder: ^strings.Builder, term: rdf.Term) -> bool {
	if term.datatype == XSD_BOOLEAN {
		switch term.value {
		case "true", "1":
			strings.write_string(builder, "true")
			return true
		case "false", "0":
			strings.write_string(builder, "false")
			return true
		}
		return false
	}
	if term.datatype == XSD_INTEGER do return write_native_integer(builder, term.value)
	if term.datatype != XSD_DOUBLE do return false
	value, valid := strconv.parse_f64(term.value)
	if !valid || math.is_nan(value) || math.is_inf(value, 0) do return false
	write_json_float(builder, value)
	return true
}

// JSON distinguishes integer and floating-point values in the in-memory
// representation. Keep an explicit decimal point for finite doubles whose
// shortest spelling would otherwise be reparsed as an integer.
@(private) write_json_float :: proc(builder: ^strings.Builder, value: f64) {
	temporary := strings.builder_make()
	defer strings.builder_destroy(&temporary)
	strings.write_float(&temporary, value, 'g', -1, 64)
	formatted := strings.to_string(temporary)
	strings.write_string(builder, formatted)
	if strings.index_byte(formatted, '.') < 0 && strings.index_byte(formatted, 'e') < 0 && strings.index_byte(formatted, 'E') < 0 do strings.write_string(builder, ".0")
}

@(private) i18n_datatype_parts :: proc(datatype: string) -> (language, direction: string, ok: bool) {
	if !strings.has_prefix(datatype, I18N) do return "", "", false
	fragment := datatype[len(I18N):]
	separator := strings.last_index_byte(fragment, '_')
	if separator < 0 do return "", "", false
	language = fragment[:separator]
	direction = fragment[separator + 1:]
	if direction != "ltr" && direction != "rtl" do return "", "", false
	return language, direction, true
}

@(private) write_json_literal :: proc(builder: ^strings.Builder, lexical: string) -> bool {
	value, parse_error := json.parse_string(lexical, .JSON, true)
	if parse_error != .None do return false
	defer json.destroy_value(value)
	strings.write_string(builder, lexical)
	return true
}

@(private) write_value :: proc(builder: ^strings.Builder, state: ^Serialization_State, graph: rdf.Quad, term: rdf.Term) {
	if write_list_value(builder, state, graph, term) do return
	if write_compound_literal_value(builder, state, graph, term) do return
	if term.kind != .Literal {
		strings.write_string(builder, `{"@id": `)
		write_identifier(builder, term)
		strings.write_byte(builder, '}')
		return
	}
	strings.write_string(builder, `{"@value": `)
	json_literal := len(term.language) == 0 && term.datatype == RDF_JSON && write_json_literal(builder, term.value)
	native := !json_literal && state.use_native_types && len(term.language) == 0 && write_native_scalar(builder, term)
	i18n_language, i18n_direction, i18n_directional := i18n_datatype_parts(term.datatype)
	i18n_directional = i18n_directional && state.rdf_direction == .I18n_Datatype
	if !json_literal && !native do write_json_string(builder, term.value)
	if i18n_directional {
		if len(i18n_language) > 0 {
			strings.write_string(builder, `, "@language": `)
			write_json_string(builder, i18n_language)
		}
		strings.write_string(builder, `, "@direction": `)
		write_json_string(builder, i18n_direction)
	} else if len(term.language) > 0 {
		strings.write_string(builder, `, "@language": `)
		write_json_string(builder, term.language)
	} else if json_literal {
		strings.write_string(builder, `, "@type": "@json"`)
	} else if term.datatype != rdf.XSD_STRING && !native {
		strings.write_string(builder, `, "@type": `)
		write_json_string(builder, term.datatype)
	}
	strings.write_byte(builder, '}')
}

@(private) write_node_properties :: proc(builder: ^strings.Builder, state: ^Serialization_State, index: ^int, first: rdf.Quad, indent: int) {
	for index^ < len(state.order) && serialization_same_node(state.quads[state.order[index^]], first) {
		quad := state.quads[state.order[index^]]
		predicate := quad.predicate
		type_as_keyword := predicate.value == RDF_TYPE && !state.use_rdf_type
		if type_as_keyword {
			for lookahead := index^; lookahead < len(state.order); lookahead += 1 {
				candidate := state.quads[state.order[lookahead]]
				if !serialization_same_node(candidate, first) || !serialization_term_equal(candidate.predicate, predicate) do break
				if candidate.object.kind != .IRI {
					type_as_keyword = false
					break
				}
			}
		}
		strings.write_string(builder, ",\n")
		write_indent(builder, indent + 2)
		if type_as_keyword {
			strings.write_string(builder, `"@type": [`)
		} else {
			write_json_string(builder, predicate.value)
			strings.write_string(builder, ": [")
		}
		first_value := true
		previous: rdf.Quad
		has_previous := false
		for index^ < len(state.order) {
			value_quad := state.quads[state.order[index^]]
			if !serialization_same_node(value_quad, first) || !serialization_term_equal(value_quad.predicate, predicate) do break
			index^ += 1
			if has_previous && serialization_quad_equal(previous, value_quad) do continue
			if !first_value do strings.write_string(builder, ", ")
			if type_as_keyword {
				write_identifier(builder, value_quad.object)
			} else {
				write_value(builder, state, value_quad, value_quad.object)
			}
			previous = value_quad
			has_previous = true
			first_value = false
		}
		strings.write_byte(builder, ']')
	}
}

@(private) valid_rdf_json_literals :: proc(quads: []rdf.Quad) -> bool {
	for quad in quads {
		if quad.object.kind != .Literal || quad.object.datatype != RDF_JSON do continue
		parsed, json_error := json.parse_string(quad.object.value, .JSON, true)
		if json_error != .None do return false
		json.destroy_value(parsed)
	}
	return true
}

@(private) write_node :: proc(builder: ^strings.Builder, state: ^Serialization_State, index: ^int, indent: int) {
	first := state.quads[state.order[index^]]
	write_indent(builder, indent)
	strings.write_string(builder, "{\n")
	write_indent(builder, indent + 2)
	strings.write_string(builder, `"@id": `)
	write_identifier(builder, first.subject)
	write_node_properties(builder, state, index, first, indent)
	strings.write_byte(builder, '\n')
	write_indent(builder, indent)
	strings.write_byte(builder, '}')
}

@(private) write_graph_nodes :: proc(builder: ^strings.Builder, state: ^Serialization_State, index: ^int, graph: rdf.Quad, indent: int) {
	first_node := true
	for index^ < len(state.order) && serialization_same_graph(state.quads[state.order[index^]], graph) {
		group_index := find_node_group(state, state.quads[state.order[index^]])
		if group_index >= 0 && (state.lists[group_index].collapsed || state.compound_literals[group_index].valid && state.rdf_direction == .Compound_Literal) {
			index^ = state.groups[group_index].end
			continue
		}
		if !first_node do strings.write_string(builder, ",\n")
		write_node(builder, state, index, indent)
		first_node = false
	}
}

// serialize atomically appends a deterministic expanded JSON-LD document for
// a complete RDF dataset. It retains graph names as top-level @graph objects,
// preserves RDF term identity, and removes exact duplicate quads. It does not
// compact IRIs or infer a context; compaction is a separate JSON-LD operation.
serialize :: proc(builder: ^strings.Builder, quads: []rdf.Quad, options: Serialize_Options = {}) -> Serialize_Error {
	if options.max_quads < 0 do return .Invalid_Option
	max_quads := options.max_quads > 0 ? options.max_quads : DEFAULT_MAX_SERIALIZE_QUADS
	if validation := validate_serialization_input(quads, max_quads); validation != .None do return validation
	if !valid_rdf_json_literals(quads) do return .Invalid_JSON_Literal

	state := Serialization_State{
		quads = quads,
		order = make([dynamic]int),
		groups = make([dynamic]Node_Group),
		lists = make([dynamic]List_Info),
		compound_literals = make([dynamic]Compound_Literal_Info),
		named_graphs = make([dynamic]rdf.Term),
		use_rdf_type = options.use_rdf_type,
		use_native_types = options.use_native_types,
		rdf_direction = options.rdf_direction,
	}
	defer {
		delete(state.order)
		delete(state.groups)
		delete(state.lists)
		delete(state.compound_literals)
		delete(state.named_graphs)
	}
	for index in 0..<len(quads) do append(&state.order, index)
	sort.sort(serialization_sort_interface(&state))
	build_node_groups(&state)
	build_list_info(&state)
	build_compound_literal_info(&state)

	temporary := strings.builder_make()
	defer strings.builder_destroy(&temporary)
	strings.write_string(&temporary, "[\n")
	first_entry := true
	index := 0
	for index < len(state.order) {
		quad := state.quads[state.order[index]]
		group_index := find_node_group(&state, quad)
		if group_index >= 0 && (state.lists[group_index].collapsed || state.compound_literals[group_index].valid && state.rdf_direction == .Compound_Literal) {
			index = state.groups[group_index].end
			continue
		}
		if !quad.has_graph && is_named_graph(&state, quad.subject) {
			index = state.groups[group_index].end
			continue
		}
		if !first_entry do strings.write_string(&temporary, ",\n")
		if !quad.has_graph {
			write_node(&temporary, &state, &index, 2)
		} else {
			write_indent(&temporary, 2)
			strings.write_string(&temporary, "{\n")
			write_indent(&temporary, 4)
			strings.write_string(&temporary, `"@id": `)
			write_identifier(&temporary, quad.graph)
			strings.write_string(&temporary, ",\n")
			write_indent(&temporary, 4)
			strings.write_string(&temporary, "\"@graph\": [\n")
			write_graph_nodes(&temporary, &state, &index, quad, 6)
			strings.write_byte(&temporary, '\n')
			write_indent(&temporary, 4)
			strings.write_byte(&temporary, ']')
			default_group := find_node_group(&state, rdf.Quad{subject = quad.graph})
			if default_group >= 0 {
				default_index := state.groups[default_group].start
				default_quad := state.quads[state.order[default_index]]
				write_node_properties(&temporary, &state, &default_index, default_quad, 2)
			}
			strings.write_byte(&temporary, '\n')
			write_indent(&temporary, 2)
			strings.write_byte(&temporary, '}')
		}
		first_entry = false
	}
	strings.write_string(&temporary, "\n]\n")
	strings.write_string(builder, strings.to_string(temporary))
	return .None
}
