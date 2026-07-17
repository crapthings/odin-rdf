// Package support contains test-only helpers for W3C syntax suites.
package support

import rdf "../../../rdf"

term_identity_equal :: proc(a, b: rdf.Term) -> bool {
	if a.kind != b.kind do return false
	if a.kind == .Blank_Node do return a.value == b.value && a.scope == b.scope
	return a.value == b.value && a.language == b.language && a.datatype == b.datatype
}

append_blank_node :: proc(nodes: ^[dynamic]rdf.Term, term: rdf.Term) {
	if term.kind != .Blank_Node do return
	for node in nodes^ {
		if term_identity_equal(node, term) do return
	}
	append(nodes, term)
}

collect_blank_nodes :: proc(graph: []rdf.Triple) -> [dynamic]rdf.Term {
	nodes := make([dynamic]rdf.Term)
	for triple in graph {
		append_blank_node(&nodes, triple.subject)
		append_blank_node(&nodes, triple.object)
	}
	return nodes
}

triple_identity_equal :: proc(a, b: rdf.Triple) -> bool {
	return term_identity_equal(a.subject, b.subject) &&
	       term_identity_equal(a.predicate, b.predicate) &&
	       term_identity_equal(a.object, b.object)
}

unique_graph :: proc(graph: []rdf.Triple) -> [dynamic]rdf.Triple {
	unique := make([dynamic]rdf.Triple)
	for triple in graph {
		seen := false
		for existing in unique {
			if triple_identity_equal(triple, existing) {
				seen = true
				break
			}
		}
		if !seen do append(&unique, triple)
	}
	return unique
}

blank_index :: proc(term: rdf.Term, nodes: []rdf.Term) -> int {
	for node, index in nodes {
		if term_identity_equal(term, node) do return index
	}
	return -1
}

mapped_term_equal :: proc(
	left, right: rdf.Term,
	left_nodes, right_nodes: []rdf.Term,
	mapping: []int,
) -> (equal, resolved: bool) {
	if left.kind != .Blank_Node do return term_identity_equal(left, right), true
	if right.kind != .Blank_Node do return false, true
	left_index := blank_index(left, left_nodes)
	if left_index < 0 || mapping[left_index] < 0 do return false, false
	return term_identity_equal(right_nodes[mapping[left_index]], right), true
}

mapped_triple_equal :: proc(
	left, right: rdf.Triple,
	left_nodes, right_nodes: []rdf.Term,
	mapping: []int,
) -> (equal, resolved: bool) {
	subject_equal, subject_resolved := mapped_term_equal(left.subject, right.subject, left_nodes, right_nodes, mapping)
	if !subject_resolved do return false, false
	if !subject_equal do return false, true
	predicate_equal, predicate_resolved := mapped_term_equal(left.predicate, right.predicate, left_nodes, right_nodes, mapping)
	if !predicate_resolved do return false, false
	if !predicate_equal do return false, true
	object_equal, object_resolved := mapped_term_equal(left.object, right.object, left_nodes, right_nodes, mapping)
	if !object_resolved do return false, false
	return object_equal, true
}

resolved_triples_fit :: proc(
	left, right: []rdf.Triple,
	left_nodes, right_nodes: []rdf.Term,
	mapping: []int,
) -> bool {
	used := make([]bool, len(right))
	defer delete(used)
	for left_triple in left {
		resolved := true
		terms := [3]rdf.Term{left_triple.subject, left_triple.predicate, left_triple.object}
		for term in terms {
			if term.kind == .Blank_Node {
				index := blank_index(term, left_nodes)
				if index < 0 || mapping[index] < 0 {
					resolved = false
					break
				}
			}
		}
		if !resolved do continue
		found := false
		for right_triple, index in right {
			if used[index] do continue
			equal, fully_resolved := mapped_triple_equal(left_triple, right_triple, left_nodes, right_nodes, mapping)
			if fully_resolved && equal {
				used[index] = true
				found = true
				break
			}
		}
		if !found do return false
	}
	return true
}

node_position_counts :: proc(node: rdf.Term, graph: []rdf.Triple) -> (subjects, objects: int) {
	for triple in graph {
		if term_identity_equal(node, triple.subject) do subjects += 1
		if term_identity_equal(node, triple.object) do objects += 1
	}
	return
}

find_mapping :: proc(
	depth: int,
	left, right: []rdf.Triple,
	left_nodes, right_nodes: []rdf.Term,
	mapping: []int,
	used: []bool,
) -> bool {
	if depth == len(left_nodes) do return resolved_triples_fit(left, right, left_nodes, right_nodes, mapping)
	left_subjects, left_objects := node_position_counts(left_nodes[depth], left)
	for right_node, right_index in right_nodes {
		if used[right_index] do continue
		right_subjects, right_objects := node_position_counts(right_node, right)
		if left_subjects != right_subjects || left_objects != right_objects do continue
		mapping[depth] = right_index
		used[right_index] = true
		if resolved_triples_fit(left, right, left_nodes, right_nodes, mapping) &&
		   find_mapping(depth + 1, left, right, left_nodes, right_nodes, mapping, used) {
			return true
		}
		mapping[depth] = -1
		used[right_index] = false
	}
	return false
}

// graph_isomorphic compares RDF graphs as triple sets while allowing a
// bijective renaming of blank nodes. Duplicate statements are ignored according
// to the RDF graph model. This is test-only and does not establish a public
// graph storage API.
graph_isomorphic :: proc(left, right: []rdf.Triple) -> bool {
	left_unique := unique_graph(left)
	defer delete(left_unique)
	right_unique := unique_graph(right)
	defer delete(right_unique)
	if len(left_unique) != len(right_unique) do return false

	left_nodes := collect_blank_nodes(left_unique[:])
	defer delete(left_nodes)
	right_nodes := collect_blank_nodes(right_unique[:])
	defer delete(right_nodes)
	if len(left_nodes) != len(right_nodes) do return false

	mapping := make([]int, len(left_nodes))
	defer delete(mapping)
	for &entry in mapping do entry = -1
	used := make([]bool, len(right_nodes))
	defer delete(used)
	return find_mapping(0, left_unique[:], right_unique[:], left_nodes[:], right_nodes[:], mapping, used)
}
