// Package canon implements the W3C RDF Dataset Canonicalization 1.0
// (RDFC-1.0) algorithm for complete RDF datasets.
package canon

import "core:crypto/hash"
import "core:sort"
import "core:strings"
import rdf ".."
import nquads "../nquads"

// Hash_Algorithm selects the cryptographic hash used by RDFC-1.0. SHA-256 is
// the required default; SHA-384 is provided for interoperable alternate-hash
// use cases.
Hash_Algorithm :: enum {
	SHA_256,
	SHA_384,
}

// Error_Code identifies invalid input, resource-policy, and canonicalization
// failures. The limits are deliberate denial-of-service protections.
Error_Code :: enum {
	None,
	Invalid_Option,
	Invalid_Quad,
	Quad_Limit,
	Blank_Node_Limit,
	Work_Limit,
	Permutation_Limit,
	Recursion_Limit,
	Out_Of_Memory,
}

// error_message returns a stable, allocation-free description.
error_message :: proc(code: Error_Code) -> string {
	switch code {
	case .None:              return "no error"
	case .Invalid_Option:    return "canonicalization limits must not be negative"
	case .Invalid_Quad:      return "invalid RDF quad"
	case .Quad_Limit:        return "canonicalization quad limit reached"
	case .Blank_Node_Limit:  return "canonicalization blank-node limit reached"
	case .Work_Limit:        return "canonicalization work limit reached"
	case .Permutation_Limit: return "canonicalization permutation limit reached"
	case .Recursion_Limit:   return "canonicalization recursion limit reached"
	case .Out_Of_Memory:     return "canonicalization memory allocation failed"
	}
	return "unknown error"
}

// Options bounds a batch canonicalization. A zero limit chooses the documented
// safe default; a positive value overrides it. These bounds intentionally make
// canonicalization a partial operation for adversarially complex datasets.
Options :: struct {
	hash_algorithm:      Hash_Algorithm,
	max_quads:           int,
	max_blank_nodes:     int,
	max_work_steps:      u64,
	max_permutations:    u64,
	max_recursion_depth: int,
}

DEFAULT_MAX_QUADS           :: 100_000
DEFAULT_MAX_BLANK_NODES     :: 100_000
DEFAULT_MAX_WORK_STEPS      :: u64(10_000_000)
DEFAULT_MAX_PERMUTATIONS    :: u64(1_000_000)
DEFAULT_MAX_RECURSION_DEPTH :: 256

@(private) Limits :: struct {
	max_quads:           int,
	max_blank_nodes:     int,
	max_work_steps:      u64,
	max_permutations:    u64,
	max_recursion_depth: int,
}

@(private) resolved_limits :: proc(options: Options) -> (Limits, Error_Code) {
	if options.max_quads < 0 || options.max_blank_nodes < 0 || options.max_recursion_depth < 0 {
		return {}, .Invalid_Option
	}
	return Limits{
		max_quads = options.max_quads > 0 ? options.max_quads : DEFAULT_MAX_QUADS,
		max_blank_nodes = options.max_blank_nodes > 0 ? options.max_blank_nodes : DEFAULT_MAX_BLANK_NODES,
		max_work_steps = options.max_work_steps > 0 ? options.max_work_steps : DEFAULT_MAX_WORK_STEPS,
		max_permutations = options.max_permutations > 0 ? options.max_permutations : DEFAULT_MAX_PERMUTATIONS,
		max_recursion_depth = options.max_recursion_depth > 0 ? options.max_recursion_depth : DEFAULT_MAX_RECURSION_DEPTH,
	}, .None
}

@(private) Digest :: struct {
	bytes: [96]byte,
	len:   int,
}

@(private) digest_equal :: proc(left, right: Digest) -> bool {
	if left.len != right.len do return false
	for i in 0..<left.len do if left.bytes[i] != right.bytes[i] do return false
	return true
}

@(private) digest_compare :: proc(left, right: Digest) -> int {
	limit := left.len < right.len ? left.len : right.len
	for i in 0..<limit {
		if left.bytes[i] < right.bytes[i] do return -1
		if left.bytes[i] > right.bytes[i] do return 1
	}
	if left.len < right.len do return -1
	if left.len > right.len do return 1
	return 0
}

@(private) write_digest :: proc(builder: ^strings.Builder, digest: Digest) {
	for i in 0..<digest.len do strings.write_byte(builder, digest.bytes[i])
}

@(private) hash_text :: proc(algorithm: Hash_Algorithm, value: string) -> Digest {
	crypto_algorithm := algorithm == .SHA_384 ? hash.Algorithm.SHA384 : hash.Algorithm.SHA256
	raw: [48]byte
	hash.hash_string_to_buffer(crypto_algorithm, value, raw[:])
	result: Digest
	result.len = hash.DIGEST_SIZES[crypto_algorithm] * 2
	hex := "0123456789abcdef"
	for byte_value, index in raw[:hash.DIGEST_SIZES[crypto_algorithm]] {
		result.bytes[index * 2] = hex[byte_value >> 4]
		result.bytes[index * 2 + 1] = hex[byte_value & 0x0f]
	}
	return result
}

@(private) Node :: struct {
	value: string,
	scope: rdf.Blank_Node_Scope,
	quads: [dynamic]int,
}

@(private) Issued :: struct {
	node:  int,
	serial: int,
}

@(private) Issuer :: struct {
	prefix: string,
	next:   int,
	issued: [dynamic]Issued,
}

@(private) init_issuer :: proc(prefix: string) -> Issuer {
	return Issuer{prefix = prefix, issued = make([dynamic]Issued)}
}

@(private) destroy_issuer :: proc(issuer: ^Issuer) {
	delete(issuer.issued)
	issuer^ = {}
}

@(private) clone_issuer :: proc(source: Issuer) -> Issuer {
	result := init_issuer(source.prefix)
	result.next = source.next
	for item in source.issued do append(&result.issued, item)
	return result
}

@(private) issued_serial :: proc(issuer: Issuer, node: int) -> (int, bool) {
	for item in issuer.issued do if item.node == node do return item.serial, true
	return 0, false
}

@(private) issue :: proc(issuer: ^Issuer, node: int) -> int {
	serial, exists := issued_serial(issuer^, node)
	if exists do return serial
	serial = issuer.next
	issuer.next += 1
	append(&issuer.issued, Issued{node = node, serial = serial})
	return serial
}

@(private) write_issued :: proc(builder: ^strings.Builder, issuer: Issuer, node: int) {
	serial, exists := issued_serial(issuer, node)
	if !exists do return
	strings.write_string(builder, issuer.prefix)
	strings.write_int(builder, serial)
}

@(private) node_equal_term :: proc(node: Node, term: rdf.Term) -> bool {
	return term.kind == .Blank_Node && node.value == term.value && node.scope == term.scope
}

@(private) term_equal :: proc(left, right: rdf.Term) -> bool {
	return left.kind == right.kind && left.value == right.value && left.language == right.language && left.datatype == right.datatype && left.scope == right.scope
}

@(private) quad_equal :: proc(left, right: rdf.Quad) -> bool {
	return left.has_graph == right.has_graph && term_equal(left.subject, right.subject) && term_equal(left.predicate, right.predicate) && term_equal(left.object, right.object) && (!left.has_graph || term_equal(left.graph, right.graph))
}

@(private) State :: struct {
	quads:            [dynamic]rdf.Quad,
	nodes:            [dynamic]Node,
	first_hashes:     [dynamic]Digest,
	canonical_issuer: Issuer,
	algorithm:        Hash_Algorithm,
	limits:           Limits,
	work_steps:       u64,
	permutations:     u64,
	error:            Error_Code,
}

@(private) init_state :: proc(algorithm: Hash_Algorithm, limits: Limits) -> State {
	return State{
		quads = make([dynamic]rdf.Quad),
		nodes = make([dynamic]Node),
		first_hashes = make([dynamic]Digest),
		canonical_issuer = init_issuer("c14n"),
		algorithm = algorithm,
		limits = limits,
	}
}

@(private) destroy_state :: proc(state: ^State) {
	for &node in state.nodes do delete(node.quads)
	destroy_issuer(&state.canonical_issuer)
	delete(state.first_hashes)
	delete(state.nodes)
	delete(state.quads)
	state^ = {}
}

@(private) step :: proc(state: ^State) -> bool {
	state.work_steps += 1
	if state.work_steps > state.limits.max_work_steps {
		state.error = .Work_Limit
		return false
	}
	return true
}

@(private) node_index :: proc(state: ^State, term: rdf.Term) -> int {
	for node, index in state.nodes do if node_equal_term(node, term) do return index
	return -1
}

@(private) add_node :: proc(state: ^State, term: rdf.Term) -> int {
	if term.kind != .Blank_Node do return -1
	if index := node_index(state, term); index >= 0 do return index
	if len(state.nodes) >= state.limits.max_blank_nodes {
		state.error = .Blank_Node_Limit
		return -1
	}
	append(&state.nodes, Node{value = term.value, scope = term.scope, quads = make([dynamic]int)})
	append(&state.first_hashes, Digest{})
	return len(state.nodes) - 1
}

@(private) append_quad_node :: proc(state: ^State, quad_index: int, term: rdf.Term) -> bool {
	if term.kind != .Blank_Node do return true
	node := add_node(state, term)
	if state.error != .None do return false
	for existing in state.nodes[node].quads do if existing == quad_index do return true
	append(&state.nodes[node].quads, quad_index)
	return true
}

@(private) validate_and_collect :: proc(state: ^State, quads: []rdf.Quad) -> Error_Code {
	validation := strings.builder_make()
	defer strings.builder_destroy(&validation)
	for quad in quads {
		if len(state.quads) >= state.limits.max_quads do return .Quad_Limit
		strings.builder_reset(&validation)
		if nquads.write_quad(&validation, quad) != .None do return .Invalid_Quad
		duplicate := false
		for existing in state.quads {
			if quad_equal(existing, quad) {
				duplicate = true
				break
			}
		}
		if duplicate do continue
		quad_index := len(state.quads)
		append(&state.quads, quad)
		if !append_quad_node(state, quad_index, quad.subject) do return state.error
		if !append_quad_node(state, quad_index, quad.object) do return state.error
		if quad.has_graph && !append_quad_node(state, quad_index, quad.graph) do return state.error
	}
	return .None
}

@(private) serialize_special_quad :: proc(state: ^State, quad: rdf.Quad, reference: int, builder: ^strings.Builder) -> bool {
	converted := quad
	terms := [4]^rdf.Term{&converted.subject, &converted.predicate, &converted.object, &converted.graph}
	limit := converted.has_graph ? 4 : 3
	for term in terms[:limit] {
		if term.kind != .Blank_Node do continue
		node := node_index(state, term^)
		if node == reference {
			term.value = "a"
		} else {
			term.value = "z"
		}
	}
	write_canonical_quad(builder, converted)
	return true
}

@(private) write_hex_escape :: proc(builder: ^strings.Builder, value: u32) {
	hex := "0123456789ABCDEF"
	if value <= 0xffff {
		strings.write_string(builder, "\\u")
		for shift := 12; shift >= 0; shift -= 4 do strings.write_byte(builder, hex[(value >> u32(shift)) & 0xf])
	} else {
		strings.write_string(builder, "\\U")
		for shift := 28; shift >= 0; shift -= 4 do strings.write_byte(builder, hex[(value >> u32(shift)) & 0xf])
	}
}

@(private) write_canonical_iri :: proc(builder: ^strings.Builder, value: string) {
	strings.write_byte(builder, '<')
	for r in value {
		u := u32(r)
		if u <= 0x20 || r == '<' || r == '>' || r == '"' || r == '{' || r == '}' || r == '|' || r == '^' || r == '`' || r == '\\' {
			write_hex_escape(builder, u)
		} else {
			strings.write_rune(builder, r)
		}
	}
	strings.write_byte(builder, '>')
}

@(private) literal_needs_uchar :: proc(value: u32) -> bool {
	return value <= 0x07 || value == 0x0b || (value >= 0x0e && value <= 0x1f) || value == 0x7f || value == 0xfffe || value == 0xffff
}

@(private) write_canonical_literal :: proc(builder: ^strings.Builder, term: rdf.Term) {
	strings.write_byte(builder, '"')
	for r in term.value {
		switch r {
		case '\b': strings.write_string(builder, "\\b")
		case '\t': strings.write_string(builder, "\\t")
		case '\n': strings.write_string(builder, "\\n")
		case '\f': strings.write_string(builder, "\\f")
		case '\r': strings.write_string(builder, "\\r")
		case '"': strings.write_string(builder, "\\\"")
		case '\\': strings.write_string(builder, "\\\\")
		case:
			if literal_needs_uchar(u32(r)) {
				write_hex_escape(builder, u32(r))
			} else {
				strings.write_rune(builder, r)
			}
		}
	}
	strings.write_byte(builder, '"')
	if len(term.language) > 0 {
		strings.write_byte(builder, '@')
		strings.write_string(builder, term.language)
	} else if term.datatype != rdf.XSD_STRING {
		strings.write_string(builder, "^^")
		write_canonical_iri(builder, term.datatype)
	}
}

@(private) write_canonical_term :: proc(builder: ^strings.Builder, term: rdf.Term) {
	switch term.kind {
	case .IRI: write_canonical_iri(builder, term.value)
	case .Blank_Node:
		strings.write_string(builder, "_:")
		strings.write_string(builder, term.value)
	case .Literal: write_canonical_literal(builder, term)
	case: return
	}
}

@(private) write_canonical_quad :: proc(builder: ^strings.Builder, quad: rdf.Quad) {
	write_canonical_term(builder, quad.subject)
	strings.write_byte(builder, ' ')
	write_canonical_term(builder, quad.predicate)
	strings.write_byte(builder, ' ')
	write_canonical_term(builder, quad.object)
	if quad.has_graph {
		strings.write_byte(builder, ' ')
		write_canonical_term(builder, quad.graph)
	}
	strings.write_string(builder, " .\n")
}

@(private) string_sort_interface :: proc(values: ^[dynamic]string) -> sort.Interface {
	return sort.Interface{
		collection = rawptr(values),
		len = proc(it: sort.Interface) -> int { return len((cast(^[dynamic]string)it.collection)^) },
		less = proc(it: sort.Interface, i, j: int) -> bool {
			values := cast(^[dynamic]string)it.collection
			return strings.compare(values[i], values[j]) < 0
		},
		swap = proc(it: sort.Interface, i, j: int) {
			values := cast(^[dynamic]string)it.collection
			values[i], values[j] = values[j], values[i]
		},
	}
}

@(private) hash_first_degree :: proc(state: ^State, node: int) -> Digest {
	serialized := make([dynamic]string)
	defer delete(serialized)
	for quad_index in state.nodes[node].quads {
		if !step(state) do return {}
		line := strings.builder_make()
		if !serialize_special_quad(state, state.quads[quad_index], node, &line) {
			strings.builder_destroy(&line)
			return {}
		}
		cloned, clone_error := strings.clone(strings.to_string(line))
		strings.builder_destroy(&line)
		if clone_error != nil {
			state.error = .Out_Of_Memory
			return {}
		}
		append(&serialized, cloned)
	}
	defer for value in serialized do delete(value)
	sort.sort(string_sort_interface(&serialized))
	input := strings.builder_make()
	defer strings.builder_destroy(&input)
	for value in serialized do strings.write_string(&input, value)
	return hash_text(state.algorithm, strings.to_string(input))
}

@(private) Hash_Group :: struct {
	hash:  Digest,
	nodes: [dynamic]int,
}

@(private) destroy_hash_groups :: proc(groups: ^[dynamic]Hash_Group) {
	for &group in groups do delete(group.nodes)
	delete(groups^)
}

@(private) add_hash_node :: proc(groups: ^[dynamic]Hash_Group, digest: Digest, node: int) {
	for &group in groups^ {
		if digest_equal(group.hash, digest) {
			append(&group.nodes, node)
			return
		}
	}
	nodes := make([dynamic]int)
	append(&nodes, node)
	append(groups, Hash_Group{hash = digest, nodes = nodes})
}

@(private) hash_group_sort_interface :: proc(groups: ^[dynamic]Hash_Group) -> sort.Interface {
	return sort.Interface{
		collection = rawptr(groups),
		len = proc(it: sort.Interface) -> int { return len((cast(^[dynamic]Hash_Group)it.collection)^) },
		less = proc(it: sort.Interface, i, j: int) -> bool {
			groups := cast(^[dynamic]Hash_Group)it.collection
			return digest_compare(groups[i].hash, groups[j].hash) < 0
		},
		swap = proc(it: sort.Interface, i, j: int) {
			groups := cast(^[dynamic]Hash_Group)it.collection
			groups[i], groups[j] = groups[j], groups[i]
		},
	}
}

@(private) related_hash :: proc(state: ^State, related: int, quad: rdf.Quad, issuer: Issuer, position: byte) -> Digest {
	input := strings.builder_make()
	defer strings.builder_destroy(&input)
	strings.write_byte(&input, position)
	if position != 'g' {
		strings.write_byte(&input, '<')
		strings.write_string(&input, quad.predicate.value)
		strings.write_byte(&input, '>')
	}
	if _, exists := issued_serial(state.canonical_issuer, related); exists {
		strings.write_string(&input, "_:")
		write_issued(&input, state.canonical_issuer, related)
	} else if _, temporary_exists := issued_serial(issuer, related); temporary_exists {
		strings.write_string(&input, "_:")
		write_issued(&input, issuer, related)
	} else {
		write_digest(&input, state.first_hashes[related])
	}
	return hash_text(state.algorithm, strings.to_string(input))
}

@(private) Related_Group :: struct {
	hash:  Digest,
	nodes: [dynamic]int,
}

@(private) destroy_related_groups :: proc(groups: ^[dynamic]Related_Group) {
	for &group in groups do delete(group.nodes)
	delete(groups^)
}

@(private) add_related :: proc(groups: ^[dynamic]Related_Group, digest: Digest, node: int) {
	for &group in groups^ {
		if digest_equal(group.hash, digest) {
			append(&group.nodes, node)
			return
		}
	}
	nodes := make([dynamic]int)
	append(&nodes, node)
	append(groups, Related_Group{hash = digest, nodes = nodes})
}

@(private) related_group_sort_interface :: proc(groups: ^[dynamic]Related_Group) -> sort.Interface {
	return sort.Interface{
		collection = rawptr(groups),
		len = proc(it: sort.Interface) -> int { return len((cast(^[dynamic]Related_Group)it.collection)^) },
		less = proc(it: sort.Interface, i, j: int) -> bool {
			groups := cast(^[dynamic]Related_Group)it.collection
			return digest_compare(groups[i].hash, groups[j].hash) < 0
		},
		swap = proc(it: sort.Interface, i, j: int) {
			groups := cast(^[dynamic]Related_Group)it.collection
			groups[i], groups[j] = groups[j], groups[i]
		},
	}
}

@(private) N_Degree_Result :: struct {
	hash:   Digest,
	issuer: Issuer,
}

@(private) Permutation_State :: struct {
	state:         ^State,
	identifier:    int,
	issuer:        Issuer,
	depth:         int,
	related:       []int,
	order:         [dynamic]int,
	used:          [dynamic]bool,
	chosen_path:   strings.Builder,
	chosen_issuer: Issuer,
	has_choice:    bool,
}

@(private) destroy_permutation_state :: proc(permutations: ^Permutation_State) {
	destroy_issuer(&permutations.issuer)
	destroy_issuer(&permutations.chosen_issuer)
	strings.builder_destroy(&permutations.chosen_path)
	delete(permutations.used)
	delete(permutations.order)
	permutations^ = {}
}

@(private) path_worse_than_choice :: proc(path, choice: string) -> bool {
	return len(path) >= len(choice) && strings.compare(path, choice) > 0
}

@(private) evaluate_permutation :: proc(permutations: ^Permutation_State) {
	state := permutations.state
	state.permutations += 1
	if state.permutations > state.limits.max_permutations {
		state.error = .Permutation_Limit
		return
	}
	if !step(state) do return
	issuer := clone_issuer(permutations.issuer)
	path := strings.builder_make()
	recursion := make([dynamic]int)
	defer {
		delete(recursion)
		strings.builder_destroy(&path)
		destroy_issuer(&issuer)
	}
	for related in permutations.order {
		if _, canonical := issued_serial(state.canonical_issuer, related); canonical {
			strings.write_string(&path, "_:")
			write_issued(&path, state.canonical_issuer, related)
		} else {
			if _, known := issued_serial(issuer, related); !known do append(&recursion, related)
			strings.write_string(&path, "_:")
			_ = issue(&issuer, related)
			write_issued(&path, issuer, related)
		}
		if permutations.has_choice && path_worse_than_choice(strings.to_string(path), strings.to_string(permutations.chosen_path)) do return
	}
	for related in recursion {
		result := hash_n_degree(state, related, issuer, permutations.depth + 1)
		if state.error != .None {
			destroy_issuer(&result.issuer)
			return
		}
		destroy_issuer(&issuer)
		issuer = result.issuer
		strings.write_string(&path, "_:")
		_ = issue(&issuer, related)
		write_issued(&path, issuer, related)
		strings.write_byte(&path, '<')
		write_digest(&path, result.hash)
		strings.write_byte(&path, '>')
		if permutations.has_choice && path_worse_than_choice(strings.to_string(path), strings.to_string(permutations.chosen_path)) do return
	}
	if !permutations.has_choice || strings.compare(strings.to_string(path), strings.to_string(permutations.chosen_path)) < 0 {
		destroy_issuer(&permutations.chosen_issuer)
		permutations.chosen_issuer = clone_issuer(issuer)
		strings.builder_reset(&permutations.chosen_path)
		strings.write_string(&permutations.chosen_path, strings.to_string(path))
		permutations.has_choice = true
	}
}

@(private) enumerate_permutations :: proc(permutations: ^Permutation_State, index: int) {
	if permutations.state.error != .None do return
	if index == len(permutations.related) {
		evaluate_permutation(permutations)
		return
	}
	for candidate in 0..<len(permutations.related) {
		if permutations.used[candidate] do continue
		permutations.used[candidate] = true
		append(&permutations.order, permutations.related[candidate])
		enumerate_permutations(permutations, index + 1)
		pop(&permutations.order)
		permutations.used[candidate] = false
		if permutations.state.error != .None do return
	}
}

@(private) hash_n_degree :: proc(state: ^State, identifier: int, issuer: Issuer, depth: int) -> N_Degree_Result {
	result := N_Degree_Result{issuer = clone_issuer(issuer)}
	if depth > state.limits.max_recursion_depth {
		state.error = .Recursion_Limit
		return result
	}
	if !step(state) do return result
	related_groups := make([dynamic]Related_Group)
	defer destroy_related_groups(&related_groups)
	for quad_index in state.nodes[identifier].quads {
		quad := state.quads[quad_index]
		terms := [4]rdf.Term{quad.subject, quad.predicate, quad.object, quad.graph}
		limit := quad.has_graph ? 4 : 3
		positions := [4]byte{'s', 'x', 'o', 'g'}
		for term, position_index in terms[:limit] {
			if term.kind != .Blank_Node do continue
			related := node_index(state, term)
			if related == identifier do continue
			digest := related_hash(state, related, quad, result.issuer, positions[position_index])
			add_related(&related_groups, digest, related)
			if !step(state) do return result
		}
	}
	sort.sort(related_group_sort_interface(&related_groups))
	data := strings.builder_make()
	defer strings.builder_destroy(&data)
	for group in related_groups {
		write_digest(&data, group.hash)
		permutations := Permutation_State{
			state = state,
			identifier = identifier,
			issuer = clone_issuer(result.issuer),
			depth = depth,
			related = group.nodes[:],
			order = make([dynamic]int),
			used = make([dynamic]bool, len(group.nodes)),
			chosen_path = strings.builder_make(),
			chosen_issuer = init_issuer("b"),
		}
		enumerate_permutations(&permutations, 0)
		if state.error != .None {
			destroy_permutation_state(&permutations)
			return result
		}
		strings.write_string(&data, strings.to_string(permutations.chosen_path))
		destroy_issuer(&result.issuer)
		result.issuer = clone_issuer(permutations.chosen_issuer)
		destroy_permutation_state(&permutations)
	}
	result.hash = hash_text(state.algorithm, strings.to_string(data))
	return result
}

@(private) Path_Result :: struct {
	hash:   Digest,
	issuer: Issuer,
}

@(private) path_result_sort_interface :: proc(results: ^[dynamic]Path_Result) -> sort.Interface {
	return sort.Interface{
		collection = rawptr(results),
		len = proc(it: sort.Interface) -> int { return len((cast(^[dynamic]Path_Result)it.collection)^) },
		less = proc(it: sort.Interface, i, j: int) -> bool {
			results := cast(^[dynamic]Path_Result)it.collection
			return digest_compare(results[i].hash, results[j].hash) < 0
		},
		swap = proc(it: sort.Interface, i, j: int) {
			results := cast(^[dynamic]Path_Result)it.collection
			results[i], results[j] = results[j], results[i]
		},
	}
}

@(private) canonical_labels :: proc(state: ^State) -> Error_Code {
	groups := make([dynamic]Hash_Group)
	defer destroy_hash_groups(&groups)
	for node in 0..<len(state.nodes) {
		state.first_hashes[node] = hash_first_degree(state, node)
		if state.error != .None do return state.error
		add_hash_node(&groups, state.first_hashes[node], node)
	}
	sort.sort(hash_group_sort_interface(&groups))
	for &group in groups {
		if len(group.nodes) != 1 do continue
		_ = issue(&state.canonical_issuer, group.nodes[0])
		delete(group.nodes)
		group.nodes = nil
	}
	for group in groups {
		if len(group.nodes) == 0 do continue
		paths := make([dynamic]Path_Result)
		for node in group.nodes {
			if _, issued := issued_serial(state.canonical_issuer, node); issued do continue
			temporary := init_issuer("b")
			_ = issue(&temporary, node)
			computed := hash_n_degree(state, node, temporary, 0)
			destroy_issuer(&temporary)
			if state.error != .None {
				destroy_issuer(&computed.issuer)
				for &path in paths do destroy_issuer(&path.issuer)
				delete(paths)
				return state.error
			}
			append(&paths, Path_Result{hash = computed.hash, issuer = computed.issuer})
		}
		sort.sort(path_result_sort_interface(&paths))
		for path in paths {
			for issued in path.issuer.issued do _ = issue(&state.canonical_issuer, issued.node)
		}
		for &path in paths do destroy_issuer(&path.issuer)
		delete(paths)
	}
	return .None
}

@(private) serialize_canonical :: proc(state: ^State, builder: ^strings.Builder) -> Error_Code {
	lines := make([dynamic]string)
	defer {
		for line in lines do delete(line)
		delete(lines)
	}
	for quad in state.quads {
		line := strings.builder_make()
		converted := quad
		labels: [4]strings.Builder
		for &label in labels do label = strings.builder_make()
		defer for &label in labels do strings.builder_destroy(&label)
		terms := [4]^rdf.Term{&converted.subject, &converted.predicate, &converted.object, &converted.graph}
		limit := converted.has_graph ? 4 : 3
		for term, index in terms[:limit] {
			if term.kind != .Blank_Node do continue
			node := node_index(state, term^)
			write_issued(&labels[index], state.canonical_issuer, node)
			term.value = strings.to_string(labels[index])
		}
		write_canonical_quad(&line, converted)
		cloned, clone_error := strings.clone(strings.to_string(line))
		strings.builder_destroy(&line)
		if clone_error != nil do return .Out_Of_Memory
		append(&lines, cloned)
	}
	sort.sort(string_sort_interface(&lines))
	for line in lines do strings.write_string(builder, line)
	return .None
}

// canonicalize atomically appends the RDFC-1.0 canonical N-Quads form of a
// complete RDF dataset. It treats input as a set and therefore removes exact
// duplicate quads. The input remains caller-owned and is never retained after
// the call returns.
canonicalize :: proc(builder: ^strings.Builder, quads: []rdf.Quad, options: Options = {}) -> Error_Code {
	limits, limits_error := resolved_limits(options)
	if limits_error != .None do return limits_error
	state := init_state(options.hash_algorithm, limits)
	defer destroy_state(&state)
	if collected := validate_and_collect(&state, quads); collected != .None do return collected
	if labels := canonical_labels(&state); labels != .None do return labels
	temporary := strings.builder_make()
	defer strings.builder_destroy(&temporary)
	if serialized := serialize_canonical(&state, &temporary); serialized != .None do return serialized
	strings.write_string(builder, strings.to_string(temporary))
	return .None
}

// canonical_hash atomically appends the lowercase hexadecimal digest of a
// dataset's RDFC-1.0 canonical N-Quads form. It uses options.hash_algorithm
// (SHA-256 by default) and otherwise has exactly the same validation,
// duplicate-set, and resource-limit behavior as canonicalize. This is useful
// for stable cache keys, integrity records, and inputs to higher-level signing
// protocols; it does not itself create or verify a signature.
canonical_hash :: proc(builder: ^strings.Builder, quads: []rdf.Quad, options: Options = {}) -> Error_Code {
	canonical := strings.builder_make()
	defer strings.builder_destroy(&canonical)
	if err := canonicalize(&canonical, quads, options); err != .None do return err
	digest := hash_text(options.hash_algorithm, strings.to_string(canonical))
	temporary := strings.builder_make()
	defer strings.builder_destroy(&temporary)
	write_digest(&temporary, digest)
	strings.write_string(builder, strings.to_string(temporary))
	return .None
}

// isomorphic reports whether two complete RDF datasets have identical RDFC-1.0
// canonical N-Quads forms. Blank-node labels and scopes may differ between the
// inputs. It compares canonical text rather than hashes, so the result does
// not rely on collision resistance. Options apply independently to each input;
// neither dataset is retained after the call returns.
isomorphic :: proc(left, right: []rdf.Quad, options: Options = {}) -> (bool, Error_Code) {
	left_canonical := strings.builder_make()
	defer strings.builder_destroy(&left_canonical)
	if err := canonicalize(&left_canonical, left, options); err != .None do return false, err
	right_canonical := strings.builder_make()
	defer strings.builder_destroy(&right_canonical)
	if err := canonicalize(&right_canonical, right, options); err != .None do return false, err
	return strings.to_string(left_canonical) == strings.to_string(right_canonical), .None
}
