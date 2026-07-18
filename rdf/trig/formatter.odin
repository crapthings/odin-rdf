// Batch TriG formatting for complete RDF datasets.
package trig

import "core:sort"
import "core:strings"
import "core:unicode/utf8"
import rdf ".."
import termlex "../internal/termlex"
import turtle "../turtle"

@(private) FORMAT_RDF_TYPE :: "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
@(private) FORMAT_RDF_NAMESPACE :: "http://www.w3.org/1999/02/22-rdf-syntax-ns#"
@(private) FORMAT_XSD_NAMESPACE :: "http://www.w3.org/2001/XMLSchema#"

// Format_Options selects the batch formatter's compact-IRI policy. Explicit
// prefixes are retained in their supplied order. Infer adds deterministic,
// safe namespace declarations for all dataset terms, including graph names.
Format_Options :: struct {
	prefixes:      []turtle.Prefix,
	prefix_policy: turtle.Prefix_Policy,
}

@(private) Format_State :: struct {
	quads: []rdf.Quad,
	order: [dynamic]int,
}

// format_quads atomically appends a deterministic, readable TriG document for
// a complete RDF dataset. It orders default graph statements before named
// graphs, groups triples by graph/subject/predicate, and removes exact duplicate
// quads. It retains no state after return; use write_quad for streaming output.
format_quads :: proc(builder: ^strings.Builder, quads: []rdf.Quad, options: Format_Options = {}) -> Write_Error {
	validation := strings.builder_make()
	defer strings.builder_destroy(&validation)
	if err := turtle.write_prefixes(&validation, options.prefixes); err != .None do return map_turtle_error(err)
	if err := validate_quads(quads); err != .None do return err
	if err := validate_blank_node_labels(quads); err != .None do return err

	prefixes := make([dynamic]turtle.Prefix)
	defer delete(prefixes)
	owned_labels := make([dynamic]string)
	defer {
		for label in owned_labels do delete(label)
		delete(owned_labels)
	}
	for prefix in options.prefixes do append(&prefixes, prefix)
	if options.prefix_policy == .Infer do infer_prefixes(&prefixes, &owned_labels, quads)

	state := Format_State{quads = quads, order = make([dynamic]int)}
	defer delete(state.order)
	for i in 0..<len(quads) do append(&state.order, i)
	sort.sort(format_sort_interface(&state))

	temporary := strings.builder_make()
	defer strings.builder_destroy(&temporary)
	writer_options := turtle.Writer_Options{prefixes = prefixes[:]}
	if len(prefixes) > 0 {
		if err := turtle.write_prefixes(&temporary, prefixes[:]); err != .None do return map_turtle_error(err)
		if len(state.order) > 0 do strings.write_byte(&temporary, '\n')
	}

	i := 0
	graph_count := 0
	for i < len(state.order) {
		graph := state.quads[state.order[i]]
		if graph_count > 0 do strings.write_byte(&temporary, '\n')
		if graph.has_graph {
			if err := turtle.write_term(&temporary, graph.graph, writer_options); err != .None do return map_turtle_error(err)
			strings.write_string(&temporary, " {\n")
			if err := format_graph(&temporary, &state, &i, graph, writer_options, "  "); err != .None do return err
			strings.write_string(&temporary, "}\n")
		} else {
			if err := format_graph(&temporary, &state, &i, graph, writer_options, ""); err != .None do return err
		}
		graph_count += 1
	}

	strings.write_string(builder, strings.to_string(temporary))
	return .None
}

@(private) validate_quads :: proc(quads: []rdf.Quad) -> Write_Error {
	for quad in quads {
		structure_error := rdf.validate_quad_structure(quad)
		if structure_error == .Invalid_Triple do return .Invalid_Triple
		if structure_error == .Invalid_Graph || structure_error == .Invalid_Graph_Term do return .Invalid_Graph
	}
	return .None
}

@(private) validate_blank_node_labels :: proc(quads: []rdf.Quad) -> Write_Error {
	seen := make(map[string]rdf.Blank_Node_Scope)
	defer delete(seen)
	for quad in quads {
		terms := [4]rdf.Term{quad.subject, quad.predicate, quad.object, quad.graph}
		term_count := 3
		if quad.has_graph do term_count = 4
		for term in terms[:term_count] {
			if term.kind != .Blank_Node do continue
			if scope, exists := seen[term.value]; exists && scope != term.scope do return .Ambiguous_Blank_Node_Label
			seen[term.value] = term.scope
		}
	}
	return .None
}

@(private) format_graph :: proc(builder: ^strings.Builder, state: ^Format_State, index: ^int, graph: rdf.Quad, options: turtle.Writer_Options, indent: string) -> Write_Error {
	previous: rdf.Quad
	has_previous := false
	subject_count := 0
	for index^ < len(state.order) && same_graph(state.quads[state.order[index^]], graph) {
		quad := state.quads[state.order[index^]]
		if has_previous && quads_equal(previous, quad) {
			index^ += 1
			continue
		}
		if subject_count > 0 do strings.write_byte(builder, '\n')
		strings.write_string(builder, indent)
		if err := turtle.write_term(builder, quad.subject, options); err != .None do return map_turtle_error(err)
		strings.write_byte(builder, ' ')

		subject := quad.subject
		predicate_count := 0
		for {
			if predicate_count > 0 {
				strings.write_string(builder, " ;\n")
				strings.write_string(builder, indent)
				strings.write_string(builder, "    ")
			}
			predicate := state.quads[state.order[index^]].predicate
			if predicate.value == FORMAT_RDF_TYPE && len(predicate.language) == 0 && len(predicate.datatype) == 0 {
				strings.write_byte(builder, 'a')
			} else {
				if err := turtle.write_term(builder, predicate, options); err != .None do return map_turtle_error(err)
			}
			strings.write_byte(builder, ' ')

			object_count := 0
			for index^ < len(state.order) {
				current := state.quads[state.order[index^]]
				if !same_graph(current, graph) || !terms_equal(current.subject, subject) || !terms_equal(current.predicate, predicate) do break
				if has_previous && quads_equal(previous, current) {
					index^ += 1
					continue
				}
				if object_count > 0 {
					strings.write_string(builder, " ,\n")
					strings.write_string(builder, indent)
					strings.write_string(builder, "        ")
				}
				if err := turtle.write_term(builder, current.object, options); err != .None do return map_turtle_error(err)
				previous = current
				has_previous = true
				object_count += 1
				index^ += 1
			}
			predicate_count += 1
			if index^ >= len(state.order) || !same_graph(state.quads[state.order[index^]], graph) || !terms_equal(state.quads[state.order[index^]].subject, subject) do break
		}
		strings.write_string(builder, " .\n")
		subject_count += 1
	}
	return .None
}

@(private) compare_terms :: proc(lhs, rhs: rdf.Term) -> int {
	if lhs.kind < rhs.kind do return -1
	if lhs.kind > rhs.kind do return 1
	if result := strings.compare(lhs.value, rhs.value); result != 0 do return result
	if result := strings.compare(lhs.language, rhs.language); result != 0 do return result
	if result := strings.compare(lhs.datatype, rhs.datatype); result != 0 do return result
	if lhs.scope < rhs.scope do return -1
	if lhs.scope > rhs.scope do return 1
	return 0
}

@(private) terms_equal :: proc(lhs, rhs: rdf.Term) -> bool {
	return lhs.kind == rhs.kind && lhs.value == rhs.value && lhs.language == rhs.language && lhs.datatype == rhs.datatype && lhs.scope == rhs.scope
}

@(private) same_graph :: proc(lhs, rhs: rdf.Quad) -> bool {
	return lhs.has_graph == rhs.has_graph && (!lhs.has_graph || terms_equal(lhs.graph, rhs.graph))
}

@(private) quads_equal :: proc(lhs, rhs: rdf.Quad) -> bool {
	return same_graph(lhs, rhs) && terms_equal(lhs.subject, rhs.subject) && terms_equal(lhs.predicate, rhs.predicate) && terms_equal(lhs.object, rhs.object)
}

@(private) format_sort_interface :: proc(state: ^Format_State) -> sort.Interface {
	return sort.Interface{
		collection = rawptr(state),
		len = proc(it: sort.Interface) -> int {
			state := cast(^Format_State)it.collection
			return len(state.order)
		},
		less = proc(it: sort.Interface, i, j: int) -> bool {
			state := cast(^Format_State)it.collection
			lhs, rhs := state.quads[state.order[i]], state.quads[state.order[j]]
			if lhs.has_graph != rhs.has_graph do return !lhs.has_graph
			if lhs.has_graph {
				if result := compare_terms(lhs.graph, rhs.graph); result != 0 do return result < 0
			}
			if result := compare_terms(lhs.subject, rhs.subject); result != 0 do return result < 0
			if result := compare_terms(lhs.predicate, rhs.predicate); result != 0 do return result < 0
			return compare_terms(lhs.object, rhs.object) < 0
		},
		swap = proc(it: sort.Interface, i, j: int) {
			state := cast(^Format_State)it.collection
			state.order[i], state.order[j] = state.order[j], state.order[i]
		},
	}
}

@(private) valid_iri :: proc(value: string) -> bool {
	if !termlex.is_absolute_iri(value) || !utf8.valid_string(value) do return false
	for r in value {
		if r <= ' ' || r == '<' || r == '>' || r == '"' || r == '{' || r == '}' || r == '|' || r == '^' || r == '`' do return false
	}
	return true
}

@(private) valid_prefixed_local :: proc(local: string) -> bool {
	if len(local) == 0 do return true
	if !utf8.valid_string(local) do return false
	r, width := utf8.decode_rune_in_string(local)
	if r == utf8.RUNE_ERROR && width == 1 do return false
	if !(termlex.is_pn_chars_u(r) || (r >= '0' && r <= '9')) do return false
	trailing_dot := false
	for pos := width; pos < len(local); {
		r, width = utf8.decode_rune_in_string(local[pos:])
		if r == utf8.RUNE_ERROR && width == 1 do return false
		if r == '.' {
			trailing_dot = true
		} else if termlex.is_pn_chars(r) || r == ':' {
			trailing_dot = false
		} else {
			return false
		}
		pos += width
	}
	return !trailing_dot
}

@(private) infer_namespace :: proc(value: string) -> (string, bool) {
	for i := len(value) - 1; i >= 0; i -= 1 {
		if value[i] != '#' && value[i] != '/' && value[i] != ':' do continue
		if i + 1 >= len(value) do continue
		namespace, local := value[:i + 1], value[i + 1:]
		if valid_iri(namespace) && valid_prefixed_local(local) do return namespace, true
	}
	return "", false
}

@(private) collect_inferred_namespace :: proc(namespaces: ^[dynamic]string, seen: ^map[string]bool, value: string) {
	namespace, ok := infer_namespace(value)
	if !ok || seen[namespace] do return
	seen[namespace] = true
	append(namespaces, namespace)
}

@(private) collect_term_namespace :: proc(namespaces: ^[dynamic]string, seen: ^map[string]bool, term: rdf.Term) {
	if term.kind == .IRI {
		collect_inferred_namespace(namespaces, seen, term.value)
	} else if term.kind == .Literal && len(term.language) == 0 && term.datatype != rdf.XSD_STRING {
		collect_inferred_namespace(namespaces, seen, term.datatype)
	}
}

@(private) namespace_sort_interface :: proc(namespaces: ^[dynamic]string) -> sort.Interface {
	return sort.Interface{
		collection = rawptr(namespaces),
		len = proc(it: sort.Interface) -> int {
			namespaces := cast(^[dynamic]string)it.collection
			return len(namespaces^)
		},
		less = proc(it: sort.Interface, i, j: int) -> bool {
			namespaces := cast(^[dynamic]string)it.collection
			return strings.compare(namespaces[i], namespaces[j]) < 0
		},
		swap = proc(it: sort.Interface, i, j: int) {
			namespaces := cast(^[dynamic]string)it.collection
			namespaces[i], namespaces[j] = namespaces[j], namespaces[i]
		},
	}
}

@(private) prefix_label_for_namespace :: proc(namespace: string) -> string {
	switch namespace {
	case FORMAT_RDF_NAMESPACE:                     return "rdf"
	case FORMAT_XSD_NAMESPACE:                     return "xsd"
	case "http://www.w3.org/2000/01/rdf-schema#": return "rdfs"
	case "http://www.w3.org/2002/07/owl#":        return "owl"
	case "http://www.w3.org/2004/02/skos/core#":  return "skos"
	case "http://purl.org/dc/terms/":              return "dcterms"
	}
	return ""
}

@(private) infer_prefixes :: proc(prefixes: ^[dynamic]turtle.Prefix, owned_labels: ^[dynamic]string, quads: []rdf.Quad) {
	namespaces := make([dynamic]string)
	defer delete(namespaces)
	seen_namespaces := make(map[string]bool)
	defer delete(seen_namespaces)
	for quad in quads {
		collect_term_namespace(&namespaces, &seen_namespaces, quad.subject)
		collect_term_namespace(&namespaces, &seen_namespaces, quad.predicate)
		collect_term_namespace(&namespaces, &seen_namespaces, quad.object)
		if quad.has_graph do collect_term_namespace(&namespaces, &seen_namespaces, quad.graph)
	}
	sort.sort(namespace_sort_interface(&namespaces))
	configured_namespaces := make(map[string]bool)
	defer delete(configured_namespaces)
	configured_labels := make(map[string]bool)
	defer delete(configured_labels)
	for prefix in prefixes^ {
		configured_namespaces[prefix.namespace] = true
		configured_labels[prefix.label] = true
	}
	next_label := 1
	label_builder := strings.builder_make()
	defer strings.builder_destroy(&label_builder)
	for namespace in namespaces {
		if configured_namespaces[namespace] do continue
		known_label := prefix_label_for_namespace(namespace)
		if len(known_label) > 0 && !configured_labels[known_label] {
			append(prefixes, turtle.Prefix{label = known_label, namespace = namespace})
			configured_namespaces[namespace] = true
			configured_labels[known_label] = true
			continue
		}
		for {
			strings.builder_reset(&label_builder)
			strings.write_string(&label_builder, "ns")
			strings.write_int(&label_builder, next_label)
			candidate := strings.to_string(label_builder)
			if !configured_labels[candidate] {
				label := strings.clone(candidate) or_else ""
				append(owned_labels, label)
				append(prefixes, turtle.Prefix{label = label, namespace = namespace})
				configured_namespaces[namespace] = true
				configured_labels[label] = true
				next_label += 1
				break
			}
			next_label += 1
		}
	}
}
