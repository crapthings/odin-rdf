// Batch Turtle formatting for complete RDF graphs.
package turtle

import "core:sort"
import "core:strings"
import rdf ".."

// Prefix_Policy controls whether the formatter augments supplied prefixes with
// deterministic, safe namespace declarations.
Prefix_Policy :: enum {
	Infer,
	Explicit_Only,
}

// Format_Options selects the batch formatter's compact-IRI policy. Explicit
// prefixes are retained in their supplied order. With Infer (the default), the
// formatter adds known W3C names where possible and ns1, ns2, ... otherwise.
Format_Options :: struct {
	prefixes:      []Prefix,
	prefix_policy: Prefix_Policy,
}

// format_triples atomically appends a deterministic, readable Turtle document
// for a complete RDF graph. It orders triples by RDF term, groups repeated
// subjects and predicates, uses a for rdf:type, and removes exact duplicate
// triples. It intentionally does not preserve source whitespace or statement
// order; use write_triple for streaming serialization.
format_triples :: proc(builder: ^strings.Builder, triples: []rdf.Triple, options: Format_Options = {}) -> Write_Error {
	if err := validate_options(Writer_Options{prefixes = options.prefixes}); err != .None do return err
	if err := validate_blank_node_labels(triples); err != .None do return err

	prefixes := make([dynamic]Prefix)
	defer delete(prefixes)
	inferred_labels := make([dynamic]string)
	defer {
		for label in inferred_labels do delete(label)
		delete(inferred_labels)
	}
	for prefix in options.prefixes do append(&prefixes, prefix)
	if options.prefix_policy == .Infer {
		infer_prefixes(&prefixes, &inferred_labels, triples)
	}

	state := Format_State{triples = triples, order = make([dynamic]int)}
	defer delete(state.order)
	for i in 0..<len(triples) do append(&state.order, i)
	sort.sort(format_sort_interface(&state))

	temporary := strings.builder_make()
	defer strings.builder_destroy(&temporary)
	writer_options := Writer_Options{prefixes = prefixes[:]}
	if len(prefixes) > 0 {
		if err := write_prefixes(&temporary, prefixes[:]); err != .None do return err
		if len(state.order) > 0 do strings.write_byte(&temporary, '\n')
	}

	previous: rdf.Triple
	has_previous := false
	i := 0
	subject_count := 0
	for i < len(state.order) {
		triple := triples[state.order[i]]
		if has_previous && triples_equal(previous, triple) {
			i += 1
			continue
		}

		if subject_count > 0 do strings.write_byte(&temporary, '\n')
		if triple.subject.kind == .Literal do return .Invalid_Subject
		if triple.predicate.kind != .IRI do return .Invalid_Predicate
		if err := write_term_unchecked(&temporary, triple.subject, writer_options); err != .None do return err
		strings.write_byte(&temporary, ' ')

		subject := triple.subject
		predicate_count := 0
		for {
			if predicate_count > 0 do strings.write_string(&temporary, " ;\n    ")
			predicate := triples[state.order[i]].predicate
			if predicate.value == RDF_TYPE && len(predicate.language) == 0 && len(predicate.datatype) == 0 {
				strings.write_byte(&temporary, 'a')
			} else {
				if err := write_term_unchecked(&temporary, predicate, writer_options); err != .None do return err
			}
			strings.write_byte(&temporary, ' ')

			object_count := 0
			for i < len(state.order) {
				current := triples[state.order[i]]
				if !terms_equal(current.subject, subject) || !terms_equal(current.predicate, predicate) do break
				if has_previous && triples_equal(previous, current) {
					i += 1
					continue
				}
				if object_count > 0 do strings.write_string(&temporary, " ,\n        ")
				if err := write_term_unchecked(&temporary, current.object, writer_options); err != .None do return err
				previous = current
				has_previous = true
				object_count += 1
				i += 1
			}
			predicate_count += 1
			if i >= len(state.order) || !terms_equal(triples[state.order[i]].subject, subject) do break
		}
		strings.write_string(&temporary, " .\n")
		subject_count += 1
	}

	strings.write_string(builder, strings.to_string(temporary))
	return .None
}

@(private) FORMATTER_RDF_NAMESPACE :: "http://www.w3.org/1999/02/22-rdf-syntax-ns#"
@(private) FORMATTER_XSD_NAMESPACE :: "http://www.w3.org/2001/XMLSchema#"

@(private) Format_State :: struct {
	triples: []rdf.Triple,
	order:   [dynamic]int,
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

@(private) triples_equal :: proc(lhs, rhs: rdf.Triple) -> bool {
	return terms_equal(lhs.subject, rhs.subject) && terms_equal(lhs.predicate, rhs.predicate) && terms_equal(lhs.object, rhs.object)
}

@(private) validate_blank_node_labels :: proc(triples: []rdf.Triple) -> Write_Error {
	seen := make(map[string]rdf.Blank_Node_Scope)
	defer delete(seen)
	for triple in triples {
		terms := [3]rdf.Term{triple.subject, triple.predicate, triple.object}
		for term in terms {
			if term.kind != .Blank_Node do continue
			if scope, exists := seen[term.value]; exists && scope != term.scope do return .Ambiguous_Blank_Node_Label
			seen[term.value] = term.scope
		}
	}
	return .None
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
			lhs, rhs := state.triples[state.order[i]], state.triples[state.order[j]]
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

@(private) prefix_label_for_namespace :: proc(namespace: string) -> string {
	switch namespace {
	case FORMATTER_RDF_NAMESPACE:           return "rdf"
	case FORMATTER_XSD_NAMESPACE:           return "xsd"
	case "http://www.w3.org/2000/01/rdf-schema#": return "rdfs"
	case "http://www.w3.org/2002/07/owl#":       return "owl"
	case "http://www.w3.org/2004/02/skos/core#": return "skos"
	case "http://purl.org/dc/terms/":             return "dcterms"
	}
	return ""
}

@(private) infer_namespace :: proc(value: string) -> (string, bool) {
	for i := len(value) - 1; i >= 0; i -= 1 {
		if value[i] != '#' && value[i] != '/' && value[i] != ':' do continue
		if i + 1 >= len(value) do continue
		namespace, local := value[:i + 1], value[i + 1:]
		if valid_turtle_iri(namespace) && valid_prefixed_local(local) do return namespace, true
	}
	return "", false
}

@(private) collect_inferred_namespace :: proc(namespaces: ^[dynamic]string, seen: ^map[string]bool, value: string) {
	namespace, ok := infer_namespace(value)
	if !ok do return
	if seen[namespace] do return
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

@(private) infer_prefixes :: proc(prefixes: ^[dynamic]Prefix, owned_labels: ^[dynamic]string, triples: []rdf.Triple) {
	namespaces := make([dynamic]string)
	defer delete(namespaces)
	seen_namespaces := make(map[string]bool)
	defer delete(seen_namespaces)
	for triple in triples {
		collect_term_namespace(&namespaces, &seen_namespaces, triple.subject)
		collect_term_namespace(&namespaces, &seen_namespaces, triple.predicate)
		collect_term_namespace(&namespaces, &seen_namespaces, triple.object)
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
			append(prefixes, Prefix{label = known_label, namespace = namespace})
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
				append(prefixes, Prefix{label = label, namespace = namespace})
				configured_namespaces[namespace] = true
				configured_labels[label] = true
				next_label += 1
				break
			}
			next_label += 1
		}
	}
}
