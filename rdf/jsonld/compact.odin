// Context-directed compaction for deterministic expanded JSON-LD output.
package jsonld

import json "core:encoding/json"
import "core:fmt"
import "core:sort"
import "core:strings"
import "core:unicode/utf8"
import rdf ".."
import turtle "../turtle"

Compact_Array_Policy :: enum { Compact, Preserve }

// Compact_Native_Type_Policy controls whether xsd:boolean, xsd:integer, and
// finite xsd:double values become JSON scalars before value compaction.
Compact_Native_Type_Policy :: enum { Native, Lexical }

Compact_Options :: struct {
	context_options:    Options,
	serializer_options: Serialize_Options,
	array_policy:       Compact_Array_Policy,
	native_type_policy: Compact_Native_Type_Policy,
	// source_document optionally preserves RDF-invisible JSON-LD annotations
	// such as ordinary @index map keys while compacting its RDF dataset.
	source_document:    string,
}

@(private) Compact_List_Term_Group :: struct {
	term:       string,
	definition: Term_Definition,
	has_definition: bool,
	values:     [dynamic]json.Value,
}

@(private) Compact_Single_Value_Term_Group :: struct {
	term:           string,
	definition:     Term_Definition,
	has_definition: bool,
	value:          json.Value,
}

@(private) Compact_Nest_Output :: struct {
	term:       string,
	properties: strings.Builder,
	count:      int,
}

@(private) Compact_Type_Context :: struct {
	term:       string,
	definition: Term_Definition,
}

@(private) Compact_Property_Index_Entry :: struct {
	source:            json.Value,
	object:            json.Object,
	index_value_index: int,
}

@(private) Compact_Property_Index_Group :: struct {
	key:     string,
	entries: [dynamic]Compact_Property_Index_Entry,
}

@(private) Compact_Annotated_Index_Group :: struct {
	key:    string,
	values: [dynamic]json.Value,
}

// Compact_Reverse_Reference records an RDF edge whose natural JSON-LD form
// may be expressed from the target node with @reverse.
@(private) Compact_Reverse_Reference :: struct {
	target_index:    int,
	source_index:    int,
	predicate_index: int,
}

@(private) Compact_Reverse_Predicate_Sort :: struct {
	state:   ^State,
	indices: ^[dynamic]int,
}

@(private) Compact_Index_Annotation :: struct {
	subject_id: string,
	predicate:  string,
	target_id:  string,
	target_signature: string,
	index:      string,
	order:      int,
	list:       bool,
	raw_none:   bool,
}

// Compact_Source_ID_Map_Annotation preserves an explicit blank-node map key
// from source input. RDF blank-node labels are serializer-local, so the
// annotation is used only after a unique id-free node signature matches.
@(private) Compact_Source_ID_Map_Annotation :: struct {
	predicate:        string,
	target_signature: string,
	key:              string,
}

@(private) Compact_Source_Type_Map_Annotation :: struct {
	predicate:        string,
	target_signature: string,
	key:              string,
	remaining_key:    string,
}

// Compact_Source_Graph_Index_Annotation retains the RDF-invisible @index
// member of one anonymous graph container from the source expansion.
@(private) Compact_Source_Graph_Index_Annotation :: struct {
	predicate: string,
	index:     string,
}

@(private) Compact_Source_Graph_Index_Node :: struct {
	graph_id:     string,
	index:        string,
	keyword_none: bool,
	fragment_predicate: string,
}

@(private) Compact_Source_Graph_ID_Annotation :: struct {
	predicate:                string,
	target_id:                string,
	graph_fragment_signature: string,
}

@(private) Compact_Source_Named_Graph_Index_Annotation :: struct {
	predicate: string,
	target_id: string,
	index:     string,
}

@(private) Compact_Source_Named_Graph_Index_Node :: struct {
	graph_id: string,
	index:    string,
}

@(private) Compact_Source_Named_Graph_Annotation :: struct {
	predicate: string,
	target_id: string,
}

// Compact_Source_Reverse_Index_Annotation retains the source-only root of a
// reverse custom-index map. The root is commonly absent from RDF serializer
// nodes because it occurs only as the object of the reversed edge.
@(private) Compact_Source_Reverse_Index_Annotation :: struct {
	root_id:          string,
	term:             string,
	reverse_predicate: string,
	index_predicate:  string,
	index_id:         string,
	source_signature: string,
	source_node_id:   string,
}

@(private) Compact_Source_Included_Root :: struct {
	root_signature: string,
	root_node_id:   string,
	parent_node_id: string,
	parent_predicate: string,
	container_set:  bool,
	root_empty:     bool,
	top_level:      bool,
}

@(private) Compact_Source_Included_Child :: struct {
	root_signature: string,
	signature:      string,
	node_id:        string,
}

// Empty arrays have no RDF statements. A named source node is nevertheless a
// stable place to restore an explicitly empty ordinary property.
@(private) Compact_Source_Empty_Property_Annotation :: struct {
	subject_id: string,
	predicate:  string,
}

// Compact_Source_Property_Term_Annotation retains a source-selected term for
// a single scalar IRI-coerced property. RDF retains the edge but not whether
// its author chose an @id or @vocab alias (nor the original compact spelling).
@(private) Compact_Source_Property_Term_Annotation :: struct {
	subject_id: string,
	predicate:  string,
	term:       string,
	raw_value:  string,
}

@(private) Compact_Source_Notype_Value_Annotation :: struct {
	subject_id: string,
	predicate:  string,
	signature:  string,
	order:      int,
}

// RDF does not preserve the order of rdf:type statements. A named source node
// provides a stable identity for restoring its explicitly authored type list.
@(private) Compact_Source_Type_Order_Annotation :: struct {
	subject_id: string,
	type_id:    string,
	order:      int,
}

@(private) Compact_Source_Value_Order_Annotation :: struct {
	subject_id:        string,
	subject_signature: string,
	predicate:         string,
	signature:         string,
	order:             int,
}

@(private) destroy_compact_list_term_groups :: proc(groups: ^[dynamic]Compact_List_Term_Group) {
	for &group in groups^ do delete(group.values)
	delete(groups^)
}

@(private) destroy_compact_nest_outputs :: proc(outputs: ^[dynamic]Compact_Nest_Output) {
	for &output in outputs^ do strings.builder_destroy(&output.properties)
	delete(outputs^)
}

@(private) destroy_compact_property_index_groups :: proc(groups: ^[dynamic]Compact_Property_Index_Group) {
	for &group in groups^ do delete(group.entries)
	delete(groups^)
}

@(private) destroy_compact_annotated_index_groups :: proc(groups: ^[dynamic]Compact_Annotated_Index_Group) {
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

@(private) compact_term_can_prefix :: proc(term: string) -> bool {
	if len(term) == 0 do return false
	switch term[len(term) - 1] {
	case ':', '/', '?', '#', '[', ']', '@': return false
	}
	return true
}

@(private) compact_iri :: proc(state: ^State, ctx: ^Context, value: string, vocab: bool, allow_terms: bool = true) -> (string, Compact_Error) {
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
	best_is_term := false
	for term, definition in ctx.terms {
		if !vocab && !allow_terms do continue
		if definition.reverse || len(definition.id) == 0 do continue
		definition_id, definition_error := compact_expand_annotation_iri(state, ctx, definition.id)
		if definition_error != .None do return "", definition_error
		if definition_id == value && compact_prefer(term, best) {
			best = term
			best_is_term = true
		}
	}
	vocab_candidate := ""
	if vocab && len(ctx.vocab) > 0 && strings.has_prefix(value, ctx.vocab) {
		candidate := value[len(ctx.vocab):]
		// A vocabulary suffix must not be reused when an existing term gives it
		// unrelated (especially keyword-alias) meaning on expansion.
		candidate_matches_term := false
		if definition, found := ctx.terms[candidate]; found && definition.id == value do candidate_matches_term = true
		if len(candidate) > 0 && (!ctx.terms[candidate].disabled || candidate_matches_term) && (!ctx.terms[candidate].reverse || candidate_matches_term) {
			if definition, found := ctx.terms[candidate]; !found || definition.id == value {
				vocab_candidate = candidate
			}
		}
	}
	if !vocab && len(ctx.base_iri) > 0 {
		candidate, relative := turtle.relativize_iri_reference(ctx.base_iri, value)
		if relative {
			owned_candidate, own_error := own(state, candidate)
			delete(candidate)
			if own_error.code != .None do return "", .Out_Of_Memory
			if compact_prefer(owned_candidate, best) do best = owned_candidate
		}
	}
	for term, definition in ctx.terms {
		// JSON-LD gives a valid @vocab suffix precedence over compact IRIs
		// created from prefix terms, even when that suffix is longer.
		if len(vocab_candidate) > 0 do continue
		if definition.reverse || !definition.prefix || !compact_term_can_prefix(term) || len(definition.id) == 0 do continue
		definition_id, definition_error := compact_expand_annotation_iri(state, ctx, definition.id)
		if definition_error != .None do return "", definition_error
		if !strings.has_prefix(value, definition_id) do continue
		suffix := value[len(definition_id):]
		if len(suffix) == 0 do continue
		candidate_builder := strings.builder_make()
		strings.write_string(&candidate_builder, term)
		strings.write_byte(&candidate_builder, ':')
		strings.write_string(&candidate_builder, suffix)
		candidate_text := strings.to_string(candidate_builder)
		// A defined term applies its own type/language/container coercion when
		// used as a property. This fallback is only safe for a compact IRI that
		// is not itself a term.
		if _, is_defined_term := ctx.terms[candidate_text]; is_defined_term {
			strings.builder_destroy(&candidate_builder)
			continue
		}
		candidate, own_error := own(state, candidate_text)
		strings.builder_destroy(&candidate_builder)
		if own_error.code != .None do return "", .Out_Of_Memory
		if compact_prefer(candidate, best) do best = candidate
	}
	if len(vocab_candidate) > 0 && !best_is_term do return vocab_candidate, .None
	if len(best) > 0 do return best, .None
	// An absolute IRI that looks like a compact IRI must not be emitted when
	// the active context would expand it through a conflicting prefix term.
	// Doing so changes the RDF identifier on a compact/expand round trip.
	if has_iri_scheme(value) {
		expanded, expand_error := expand_iri(state, ctx, value, vocab, true)
		if expand_error.code != .None do return "", compact_context_error(expand_error)
		if expanded != value do return "", .Invalid_Context
	}
	return value, .None
}

@(private) compact_value_matches_definition :: proc(ctx: ^Context, value: json.Value, definition: Term_Definition) -> bool {
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
	// A term without an explicit language inherits the active default language
	// for string values. It therefore cannot safely compact a plain or
	// differently-language-tagged RDF literal.
	if ctx.has_language {
		raw_value, has_raw_value := object_value(object, "@value")
		_, is_string := string_value(raw_value)
		if has_raw_value && is_string {
			language_value, has_language := object_value(object, "@language")
			language, language_valid := string_value(language_value)
			return has_language && language_valid && language == ctx.language
		}
	}
	return true
}

@(private) compact_values_match_definition :: proc(ctx: ^Context, values: json.Array, definition: Term_Definition) -> bool {
	items := values
	value_context := ctx^
	if len(values) == 1 {
		list_object, valid := object_from_value(values[0])
		if valid {
			list_value, has_list := object_value(list_object, "@list")
			if has_list {
				items_valid: bool
				items, items_valid = array_from_value(list_value)
				if !items_valid do return false
				// A property's coercion applies to each member of an @list, even
				// when that property does not itself use an @list container.
				// Container-list terms additionally allow mixed plain/language
				// members unless they declare their own coercion.
				if definition.container_list && !definition.has_language && !definition.language_null && len(definition.type) == 0 do value_context.has_language = false
			} else if definition.container_list {
				return false
			}
		} else if definition.container_list {
			return false
		}
	} else if definition.container_list {
		return false
	}
	// Language-map entries encode their language in the map key, so an active
	// default language does not constrain the values unless the term explicitly
	// supplies its own language coercion.
	if definition.container_language && !definition.has_language && !definition.language_null do value_context.has_language = false
	for item in items {
		if !compact_value_matches_definition(&value_context, item, definition) do return false
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
		if definition.id != iri || definition.reverse || !compact_values_match_definition(ctx, values, definition) do continue
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
	// A compact IRI can spell exactly like a context term whose coercion did not
	// match these values. Emitting it would reintroduce that term's semantics on
	// parse. Prefer another safe prefixed spelling (for example `ex:property`)
	// before falling back to the expanded predicate.
	if conflicting, found := ctx.terms[compacted]; found && conflicting.id == iri && !compact_values_match_definition(ctx, values, conflicting) {
		prefixed, prefix_error := compact_undefined_prefixed_property(state, ctx, iri)
		if prefix_error != .None do return "", {}, false, prefix_error
		if len(prefixed) > 0 {
			compacted = prefixed
		} else {
			compacted = iri
		}
	}
	return compacted, {}, false, .None
}

// A plain term can safely carry an explicitly expanded value object even when
// its context supplies a default language. This is the fallback for a mixed
// value group only; the value writer keeps nonmatching members explicit.
@(private) compact_plain_property_term :: proc(ctx: ^Context, iri: string) -> (string, bool) {
	best := ""
	for term, definition in ctx.terms {
		if definition.id != iri || definition.reverse || definition.container_set || definition.container_list || definition.container_language || definition.container_index || definition.container_id || definition.container_type || definition.container_graph || len(definition.type) > 0 || definition.has_language || definition.language_null || definition.has_direction || definition.direction_null || len(definition.nest) > 0 do continue
		if compact_prefer(term, best) do best = term
	}
	return best, len(best) > 0
}

@(private) compact_undefined_prefixed_property :: proc(state: ^State, ctx: ^Context, iri: string) -> (string, Compact_Error) {
	best := ""
	for term, definition in ctx.terms {
		if definition.reverse || !definition.prefix || !compact_term_can_prefix(term) || len(definition.id) == 0 do continue
		definition_id, definition_error := compact_expand_annotation_iri(state, ctx, definition.id)
		if definition_error != .None do return "", definition_error
		if !strings.has_prefix(iri, definition_id) do continue
		suffix := iri[len(definition_id):]
		if len(suffix) == 0 do continue
		candidate_builder := strings.builder_make()
		strings.write_string(&candidate_builder, term)
		strings.write_byte(&candidate_builder, ':')
		strings.write_string(&candidate_builder, suffix)
		candidate_text := strings.to_string(candidate_builder)
		if _, is_defined_term := ctx.terms[candidate_text]; is_defined_term {
			strings.builder_destroy(&candidate_builder)
			continue
		}
		candidate, own_error := own(state, candidate_text)
		strings.builder_destroy(&candidate_builder)
		if own_error.code != .None do return "", .Out_Of_Memory
		expanded, expand_error := expand_iri(state, ctx, candidate, true, true)
		if expand_error.code != .None do return "", compact_context_error(expand_error)
		if expanded == iri && compact_prefer(candidate, best) do best = candidate
	}
	return best, .None
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

@(private) compact_write_identifier :: proc(builder: ^strings.Builder, state: ^State, ctx: ^Context, value: json.Value, vocab: bool, allow_terms: bool = true) -> Compact_Error {
	id, valid := string_value(value)
	if !valid do return .Invalid_Expanded_JSON
	compacted, compact_error := compact_iri(state, ctx, id, vocab, allow_terms)
	if compact_error != .None do return compact_error
	write_json_string(builder, compacted)
	return .None
}

@(private) compact_expand_error :: proc(err: Expand_Error) -> Compact_Error {
	if err == .None do return .None
	if err == .Out_Of_Memory do return .Out_Of_Memory
	return .Invalid_Context
}

// Compaction receives expanded type IRIs from RDF serialization, whereas a
// source JSON-LD document carries compact type terms. Resolve type scopes by
// their expanded definition IDs, in deterministic term order, so the final
// context matches JSON-LD's ordered scoped-context application.
@(private) compact_apply_type_scoped_contexts :: proc(state: ^State, current: ^Context, object: json.Object) -> (Context, Compact_Error) {
	type_value, has_types := object_value(object, "@type")
	if !has_types do return current^, .None
	types, is_array := array_from_value(type_value)
	count := is_array ? len(types) : 1
	candidates := make([dynamic]Compact_Type_Context)
	defer delete(candidates)
	for index in 0..<count {
		type_item := is_array ? types[index] : type_value
		type_id, type_valid := string_value(type_item)
		if !type_valid do return {}, .Invalid_Expanded_JSON
		for term, definition in current.terms {
			if definition.id != type_id || !definition.has_local_context do continue
			found := false
			for candidate in candidates do if candidate.term == term { found = true; break }
			if !found do append(&candidates, Compact_Type_Context{term = term, definition = definition})
		}
	}
	sort.sort(sort.Interface{
		collection = rawptr(&candidates),
		len = proc(it: sort.Interface) -> int { return len((cast(^[dynamic]Compact_Type_Context)it.collection)^) },
		less = proc(it: sort.Interface, i, j: int) -> bool {
			terms := cast(^[dynamic]Compact_Type_Context)it.collection
			return strings.compare(terms[i].term, terms[j].term) < 0
		},
		swap = proc(it: sort.Interface, i, j: int) {
			terms := cast(^[dynamic]Compact_Type_Context)it.collection
			terms[i], terms[j] = terms[j], terms[i]
		},
	})
	result := current^
	for candidate in candidates {
		updated, context_error := apply_term_scoped_context(state, &result, candidate.definition)
		if context_error.code != .None do return {}, compact_context_error(context_error)
		result = updated
	}
	return result, .None
}

// Compaction consumes the same expanded node shape as Expansion produces.
// Keep property scopes, local contexts, and non-propagating scope boundaries
// aligned with that path; then resolve type scopes from serialized expanded
// identifiers rather than compact input spellings.
@(private) compact_resolve_object_context :: proc(state: ^State, current: ^Context, definition: Term_Definition, object: json.Object, roll_back := true) -> (Context, Context, Compact_Error) {
	result := current^
	if roll_back && expand_rolls_back_context(&result, object) do result = previous_context(&result)
	if definition.has_local_context {
		updated, context_error := apply_term_scoped_context(state, &result, definition, true)
		if context_error.code != .None do return {}, {}, compact_context_error(context_error)
		result = updated
	}
	if context_value, has_context := object_value(object, "@context"); has_context {
		updated, expand_error := expand_apply_local_context(state, &result, context_value)
		if compact_error := compact_expand_error(expand_error); compact_error != .None do return {}, {}, compact_error
		result = updated
	}
	type_context := result
	active, compact_error := compact_apply_type_scoped_contexts(state, &result, object)
	if compact_error != .None do return {}, {}, compact_error
	return active, type_context, .None
}

@(private) compact_write_list :: proc(builder: ^strings.Builder, state: ^State, ctx: ^Context, value: json.Value, definition: Term_Definition, has_definition: bool, policy: Compact_Array_Policy) -> Compact_Error {
	array, valid := array_from_value(value)
	if !valid do return .Invalid_Expanded_JSON
	strings.write_byte(builder, '[')
	for item, index in array {
		if index > 0 do strings.write_string(builder, ", ")
		if item_object, is_object := object_from_value(item); is_object {
			if nested_list, has_list := object_value(item_object, "@list"); has_list {
				if err := compact_write_list(builder, state, ctx, nested_list, definition, has_definition, policy); err != .None do return err
				continue
			}
		}
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
	_, value_is_string := string_value(value)
	can_scalar := !has_type && !has_language && (!ctx.has_language || !value_is_string || (has_definition && definition.language_null))
	if has_type && type_is_string && has_definition && definition.type == type_name do can_scalar = true
	if has_definition && definition.type == "@none" do can_scalar = false
	if has_language && language_is_string {
		if has_definition && definition.has_language && definition.language == language do can_scalar = true
		if has_definition && !definition.language_null && !definition.has_language && ctx.has_language && ctx.language == language do can_scalar = true
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

// A JSON-typed array is one JSON-LD value, not a list of property values.
// When its term also uses @set, the JSON array itself provides the required
// outer array shape and must not be wrapped again.
@(private) compact_value_is_json_array :: proc(value: json.Value) -> bool {
	object, valid_object := object_from_value(value)
	type_value, has_type := object_value(object, "@type")
	type_name, valid_type := string_value(type_value)
	raw_value, has_raw_value := object_value(object, "@value")
	if !valid_object || !has_type || !valid_type || type_name != "@json" || !has_raw_value do return false
	#partial switch _ in raw_value {
	case json.Array: return true
	}
	return false
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
@(private) compact_write_language_map :: proc(builder: ^strings.Builder, state: ^State, ctx: ^Context, source: json.Object, predicate: string, values: json.Array, policy: Compact_Array_Policy, force_set := false) -> Compact_Error {
	ordered_indices, order_error := compact_source_ordered_value_indices(state, source, predicate, values[:])
	if order_error != .None do return order_error
	defer delete(ordered_indices)
	keys := make([dynamic]string)
	defer delete(keys)
	for index in ordered_indices {
		value := values[index]
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
	strings.write_byte(builder, '{')
	for key, key_index in keys {
		if key_index > 0 do strings.write_string(builder, ", ")
		compacted_key := key == "@none" ? compact_keyword(ctx, "@none") : key
		write_json_string(builder, compacted_key)
		strings.write_string(builder, ": ")
		count := 0
		for index in ordered_indices {
			value := values[index]
			if compact_language_map_key(value) == key do count += 1
		}
		if policy == .Compact && count == 1 && !force_set {
			for index in ordered_indices {
				value := values[index]
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
			for index in ordered_indices {
				value := values[index]
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

@(private) compact_write_source_empty_properties :: proc(builder: ^strings.Builder, state: ^State, ctx: ^Context, object: json.Object, first: ^bool) -> Compact_Error {
	subject_value, has_subject := object_value(object, "@id")
	subject_id, valid_subject := string_value(subject_value)
	if !has_subject || !valid_subject || strings.has_prefix(subject_id, "_:") do return .None
	for annotation in state.compact_source_empty_property_annotations {
		if annotation.subject_id != subject_id do continue
		if _, present := object[annotation.predicate]; present do continue
		empty_values := make(json.Array)
		term, definition, has_definition, term_error := compact_property_term(state, ctx, annotation.predicate, empty_values)
		delete(empty_values)
		if term_error != .None do return term_error
		// Empty maps require source-specific map reconstruction; do not invent
		// a bare array for them. Ordinary and @set properties are unambiguous.
		if has_definition && (definition.container_language || definition.container_index || definition.container_id || definition.container_type || definition.container_graph) do continue
		if !first^ do strings.write_string(builder, ", ")
		write_json_string(builder, term)
		strings.write_string(builder, ": []")
		first^ = false
	}
	return .None
}

// A graph serializer is free to order rdf:type statements differently from
// their source JSON-LD representation. When a named source node has exactly
// the same type set after the RDF round-trip, use its recorded order rather
// than the serializer's incidental order.
@(private) compact_write_source_type_order :: proc(builder: ^strings.Builder, state: ^State, type_context: ^Context, object: json.Object, types: json.Array) -> (bool, Compact_Error) {
	subject_value, has_subject := object_value(object, "@id")
	subject_id, valid_subject := string_value(subject_value)
	if !has_subject || !valid_subject || strings.has_prefix(subject_id, "_:") do return false, .None
	annotation_count := 0
	for annotation in state.compact_source_type_order_annotations {
		if annotation.subject_id == subject_id do annotation_count += 1
	}
	if annotation_count != len(types) || annotation_count == 0 do return false, .None
	used := make([dynamic]bool)
	defer delete(used)
	for _ in types do append(&used, false)
	for source_order := 0; source_order < len(types); source_order += 1 {
		annotation_found := false
		annotation: Compact_Source_Type_Order_Annotation
		for candidate in state.compact_source_type_order_annotations {
			if candidate.subject_id == subject_id && candidate.order == source_order {
				annotation = candidate
				annotation_found = true
				break
			}
		}
		if !annotation_found do return false, .None
		matched_index := -1
		for item, item_index in types {
			item_id, valid_item := string_value(item)
			if !valid_item do return false, .Invalid_Expanded_JSON
			if !used[item_index] && item_id == annotation.type_id {
				matched_index = item_index
				break
			}
		}
		if matched_index < 0 do return false, .None
		used[matched_index] = true
	}
	strings.write_byte(builder, '[')
	for source_order := 0; source_order < len(types); source_order += 1 {
		annotation: Compact_Source_Type_Order_Annotation
		for candidate in state.compact_source_type_order_annotations {
			if candidate.subject_id == subject_id && candidate.order == source_order {
				annotation = candidate
				break
			}
		}
		if source_order > 0 do strings.write_string(builder, ", ")
		for item in types {
			item_id, valid_item := string_value(item)
			if valid_item && item_id == annotation.type_id {
				if err := compact_write_identifier(builder, state, type_context, item, true); err != .None do return false, err
				break
			}
		}
	}
	strings.write_byte(builder, ']')
	return true, .None
}

@(private) compact_source_ordered_value_indices :: proc(state: ^State, object: json.Object, predicate: string, values: []json.Value) -> ([dynamic]int, Compact_Error) {
	indices := make([dynamic]int)
	subject_value, has_subject := object_value(object, "@id")
	subject_id, valid_subject := string_value(subject_value)
	if !has_subject || !valid_subject {
		for index in 0..<len(values) do append(&indices, index)
		return indices, .None
	}
	annotation_subject := subject_id
	if strings.has_prefix(subject_id, "_:") {
		// Nested blank labels are safe only while writing a uniquely recovered
		// anonymous source root. That source and the serializer share one
		// deterministic blank-node allocation, so their value-order annotations
		// can be used without generalizing serializer-local labels.
		if state.compact_node_depth == 1 {
			annotation_subject = ""
		} else if !state.compact_writing_source_root {
			for index in 0..<len(values) do append(&indices, index)
			return indices, .None
		}
	}
	matching_by_signature := strings.has_prefix(subject_id, "_:") && state.compact_writing_source_root && state.compact_node_depth > 1
	subject_signature, signature_error := compact_value_order_subject_signature(object, matching_by_signature)
	if signature_error != .None { delete(indices); return {}, signature_error }
	defer delete(subject_signature)
	matching_annotations := 0
	for annotation in state.compact_source_value_order_annotations {
		if annotation.predicate != predicate do continue
		if matching_by_signature {
			if annotation.subject_signature == subject_signature do matching_annotations += 1
		} else if annotation.subject_id == annotation_subject && (len(annotation_subject) > 0 || len(annotation.subject_signature) == 0) do matching_annotations += 1
	}
	if matching_annotations == 0 {
		for index in 0..<len(values) do append(&indices, index)
		return indices, .None
	}
	used := make([dynamic]bool)
	defer delete(used)
	for _ in values do append(&used, false)
	for source_order := 0; source_order < matching_annotations; source_order += 1 {
		annotation_found := false
		annotation: Compact_Source_Value_Order_Annotation
		for candidate in state.compact_source_value_order_annotations {
			matches_subject := matching_by_signature ? candidate.subject_signature == subject_signature : candidate.subject_id == annotation_subject && (len(annotation_subject) > 0 || len(candidate.subject_signature) == 0)
			if matches_subject && candidate.predicate == predicate && candidate.order == source_order {
				annotation = candidate
				annotation_found = true
				break
			}
		}
		if !annotation_found do continue
		for value, value_index in values {
			if used[value_index] do continue
			matches := false
			if matching_by_signature {
				signature, signature_error := compact_value_order_match_signature(state, value)
				if signature_error != .None { delete(indices); return {}, signature_error }
				matches = signature == annotation.signature
				delete(signature)
			} else {
				signature, signature_error := compact_value_order_signature(value)
				if signature_error != .None { delete(indices); return {}, signature_error }
				matches = signature == annotation.signature
				delete(signature)
			}
			if !matches do continue
			append(&indices, value_index)
			used[value_index] = true
			break
		}
	}
	if len(indices) != len(values) {
		delete(indices)
		indices = make([dynamic]int)
		for index in 0..<len(values) do append(&indices, index)
	}
	return indices, .None
}

// RDF datasets collapse duplicate statements, while an explicit @set array
// may intentionally retain duplicate JSON-LD values. Restore that source
// multiplicity only after proving every serialized value occurs in the source
// annotations and every source annotation has the same value signature.
@(private) compact_write_source_duplicate_set :: proc(builder: ^strings.Builder, state: ^State, ctx, type_context: ^Context, object: json.Object, predicate: string, values: json.Array, definition: Term_Definition, policy: Compact_Array_Policy) -> (bool, Compact_Error) {
	subject_value, has_subject := object_value(object, "@id")
	subject_id, valid_subject := string_value(subject_value)
	if !has_subject || !valid_subject do return false, .None
	annotation_subject := subject_id
	if strings.has_prefix(subject_id, "_:") {
		if state.compact_node_depth != 1 do return false, .None
		annotation_subject = ""
	}
	raw_annotation_count := 0
	for annotation in state.compact_source_notype_value_annotations {
		if annotation.subject_id == annotation_subject && annotation.predicate == predicate do raw_annotation_count += 1
	}
	if raw_annotation_count > len(values) {
		strings.write_byte(builder, '[')
		for source_order := 0; source_order < raw_annotation_count; source_order += 1 {
			annotation_found := false
			annotation: Compact_Source_Notype_Value_Annotation
			for candidate in state.compact_source_notype_value_annotations {
				if candidate.subject_id == annotation_subject && candidate.predicate == predicate && candidate.order == source_order {
					annotation = candidate
					annotation_found = true
					break
				}
			}
			if !annotation_found do return false, .None
			value, json_error := json.parse_string(annotation.signature, .JSON, true)
			if json_error != .None do return false, .Invalid_Expanded_JSON
			if source_order > 0 do strings.write_string(builder, ", ")
			value_error := compact_write_value_with_inherited_context(builder, state, ctx, type_context, value, definition, true, policy)
			json.destroy_value(value)
			if value_error != .None do return false, value_error
		}
		strings.write_byte(builder, ']')
		return true, .None
	}
	annotation_count := 0
	for annotation in state.compact_source_value_order_annotations {
		if annotation.subject_id == annotation_subject && annotation.predicate == predicate do annotation_count += 1
	}
	if annotation_count <= len(values) do return false, .None
	runtime_signatures := make([dynamic]string)
	defer {
		for signature in runtime_signatures do delete(signature)
		delete(runtime_signatures)
	}
	for value in values {
		signature, signature_error := compact_value_order_signature(value)
		if signature_error != .None do return false, signature_error
		append(&runtime_signatures, signature)
	}
	for annotation in state.compact_source_value_order_annotations {
		if annotation.subject_id != subject_id || annotation.predicate != predicate do continue
		matches_runtime := false
		for signature in runtime_signatures do if signature == annotation.signature { matches_runtime = true; break }
		if !matches_runtime do return false, .None
	}
	for signature in runtime_signatures {
		found_source := false
		for annotation in state.compact_source_value_order_annotations {
			if annotation.subject_id == subject_id && annotation.predicate == predicate && annotation.signature == signature {
				found_source = true
				break
			}
		}
		if !found_source do return false, .None
	}
	strings.write_byte(builder, '[')
	written := 0
	for source_order := 0; source_order < annotation_count; source_order += 1 {
		annotation_found := false
		annotation: Compact_Source_Value_Order_Annotation
		for candidate in state.compact_source_value_order_annotations {
			if candidate.subject_id == subject_id && candidate.predicate == predicate && candidate.order == source_order {
				annotation = candidate
				annotation_found = true
				break
			}
		}
		if !annotation_found do return false, .None
		value, json_error := json.parse_string(annotation.signature, .JSON, true)
		if json_error != .None do return false, .Invalid_Expanded_JSON
		if written > 0 do strings.write_string(builder, ", ")
		value_error := compact_write_value_with_inherited_context(builder, state, ctx, type_context, value, definition, true, policy)
		json.destroy_value(value)
		if value_error != .None do return false, value_error
		written += 1
	}
	strings.write_byte(builder, ']')
	return true, .None
}

// @type: @none deliberately preserves expanded value-object distinctions.
// RDF may still collapse two values with the same native RDF literal (for
// example JSON true and an explicitly typed xsd:boolean true), so retain the
// complete source sequence when every serialized value is represented there.
@(private) compact_write_source_notype_values :: proc(builder: ^strings.Builder, state: ^State, ctx, type_context: ^Context, object: json.Object, predicate: string, values: json.Array, definition: Term_Definition, policy: Compact_Array_Policy) -> (bool, Compact_Error) {
	if definition.type != "@none" do return false, .None
	subject_value, has_subject := object_value(object, "@id")
	subject_id, valid_subject := string_value(subject_value)
	if !has_subject || !valid_subject do return false, .None
	annotation_subject := subject_id
	if strings.has_prefix(subject_id, "_:") {
		if state.compact_node_depth != 1 do return false, .None
		annotation_subject = ""
	}
	annotation_count := 0
	for annotation in state.compact_source_notype_value_annotations {
		if annotation.subject_id == annotation_subject && annotation.predicate == predicate do annotation_count += 1
	}
	if annotation_count <= len(values) do return false, .None
	// A larger source sequence proves RDF collapsed at least one value under
	// @type: @none. The original source document was used to produce this
	// dataset, so replaying that sequence restores the only lost distinction.
	strings.write_byte(builder, '[')
	for source_order := 0; source_order < annotation_count; source_order += 1 {
		annotation_found := false
		annotation: Compact_Source_Notype_Value_Annotation
		for candidate in state.compact_source_notype_value_annotations {
			if candidate.subject_id == annotation_subject && candidate.predicate == predicate && candidate.order == source_order {
				annotation = candidate
				annotation_found = true
				break
			}
		}
		if !annotation_found do return false, .None
		value, json_error := json.parse_string(annotation.signature, .JSON, true)
		if json_error != .None do return false, .Invalid_Expanded_JSON
		if source_order > 0 do strings.write_string(builder, ", ")
		value_error: Compact_Error
		value_object, valid_value_object := object_from_value(value)
		identifier, has_identifier := object_value(value_object, "@id")
		if valid_value_object && has_identifier && len(value_object) == 1 {
			strings.write_byte(builder, '{')
			write_json_string(builder, compact_keyword(ctx, "@id"))
			strings.write_string(builder, ": ")
			value_error = compact_write_identifier(builder, state, ctx, identifier, false)
			strings.write_byte(builder, '}')
		} else {
			value_error = compact_write_value_with_inherited_context(builder, state, ctx, type_context, value, definition, true, policy)
		}
		json.destroy_value(value)
		if value_error != .None do return false, value_error
	}
	strings.write_byte(builder, ']')
	return true, .None
}

@(private) compact_write_source_indexed_values :: proc(builder: ^strings.Builder, state: ^State, ctx, type_context: ^Context, subject: json.Object, predicate: string, values: json.Array, definition: Term_Definition, has_definition: bool, policy: Compact_Array_Policy) -> (bool, Compact_Error) {
	subject_value, has_subject := object_value(subject, "@id")
	subject_id, valid_subject := string_value(subject_value)
	if !has_subject || !valid_subject do return false, .None
	has_index := false
	for value in values {
		item, valid_item := object_from_value(value)
		if !valid_item do return false, .None
		item_id_value, has_item_id := object_value(item, "@id")
		item_id, valid_item_id := string_value(item_id_value)
		if has_item_id && !valid_item_id do return false, .Invalid_Expanded_JSON
		if !has_item_id do item_id = ""
		target := item
		if has_item_id {
			if indexed, found := state.compact_nodes[item_id]; found do target = indexed
		}
		_, found_index, index_error := compact_index_annotation(state, ctx, subject_id, predicate, predicate, definition.id, item_id, target)
		if index_error != .None do return false, index_error
		if found_index do has_index = true
	}
	if !has_index do return false, .None
	ordered_indices, order_error := compact_source_ordered_value_indices(state, subject, predicate, values[:])
	if order_error != .None do return false, order_error
	defer delete(ordered_indices)
	strings.write_byte(builder, '[')
	for ordered_index, position in ordered_indices {
		if position > 0 do strings.write_string(builder, ", ")
		item := values[ordered_index]
		item_object, valid_item := object_from_value(item)
		if !valid_item do return false, .None
		item_id_value, has_item_id := object_value(item_object, "@id")
		item_id, valid_item_id := string_value(item_id_value)
		if has_item_id && !valid_item_id do return false, .Invalid_Expanded_JSON
		if !has_item_id do item_id = ""
		target := item_object
		if has_item_id {
			if indexed, found := state.compact_nodes[item_id]; found do target = indexed
		}
		index, found_index, index_error := compact_index_annotation(state, ctx, subject_id, predicate, predicate, definition.id, item_id, target)
		if index_error != .None do return false, index_error
		value_builder := strings.builder_make()
		value_error := compact_write_value_with_inherited_context(&value_builder, state, ctx, type_context, item, definition, has_definition, policy)
		value_text := strings.to_string(value_builder)
		if value_error != .None { strings.builder_destroy(&value_builder); return false, value_error }
		if !found_index {
			strings.write_string(builder, value_text)
			strings.builder_destroy(&value_builder)
			continue
		}
		if len(value_text) >= 2 && value_text[0] == '{' && value_text[len(value_text) - 1] == '}' {
			strings.write_string(builder, value_text[:len(value_text) - 1])
			strings.write_string(builder, ", \"@index\": ")
			write_json_string(builder, index)
			strings.write_byte(builder, '}')
		} else {
			strings.write_string(builder, "{\"@value\": ")
			strings.write_string(builder, value_text)
			strings.write_string(builder, ", \"@index\": ")
			write_json_string(builder, index)
			strings.write_byte(builder, '}')
		}
		strings.builder_destroy(&value_builder)
	}
	strings.write_byte(builder, ']')
	return true, .None
}

@(private) compact_property_has_source_index :: proc(state: ^State, subject: json.Object, predicate: string) -> bool {
	subject_value, has_subject := object_value(subject, "@id")
	subject_id, valid_subject := string_value(subject_value)
	if !has_subject || !valid_subject do return false
	for annotation in state.compact_index_annotations {
		if annotation.raw_none || annotation.list do continue
		if !compact_index_annotation_subject_matches(state, annotation.subject_id, subject_id) do continue
		if compact_annotation_predicate_matches(annotation.predicate, predicate, predicate, "") do return true
	}
	return false
}

@(private) compact_write_node_resolved :: proc(builder: ^strings.Builder, state: ^State, ctx, type_context: ^Context, object: json.Object, policy: Compact_Array_Policy) -> Compact_Error {
	state.compact_node_depth += 1
	defer compact_leave_node(state)
	keys := compact_sorted_keys(object)
	defer delete(keys)
	nests := make([dynamic]Compact_Nest_Output)
	defer destroy_compact_nest_outputs(&nests)
	strings.write_byte(builder, '{')
	first := true
	for key in keys {
		value := object[key]
		// A blank-node type retained by a source-matched @type map has no stable
		// RDF label. Emit the proven source spelling while the enclosing map entry
		// establishes the target-node signature that made the match unique.
		if key == RDF_TYPE && len(state.compact_type_map_remaining_runtime) > 0 {
			values, valid_values := array_from_value(value)
			if !valid_values do return .Invalid_Expanded_JSON
			if len(values) == 1 {
				identifier, identifier_error := compact_type_map_value_identifier(RDF_TYPE, values[0])
				if identifier_error != .None do return identifier_error
				if identifier == state.compact_type_map_remaining_runtime {
					if !first do strings.write_string(builder, ", ")
					write_json_string(builder, compact_keyword(ctx, "@type"))
					strings.write_string(builder, ": ")
					write_json_string(builder, state.compact_type_map_remaining_source)
					first = false
					continue
				}
			}
		}
		if key == "@id" && len(state.compact_omit_singleton_blank_id) > 0 {
			identifier, valid_identifier := string_value(value)
			if valid_identifier && identifier == state.compact_omit_singleton_blank_id do continue
		}
		compacted_key := ""
		definition: Term_Definition
		has_definition := false
		source_index := ""
		has_source_index := false
		raw_index_subject := ""
		has_raw_index_values := false
		source_property_value := ""
		has_source_property_value := false
		if is_keyword(key) {
			compacted_key = compact_keyword(ctx, key)
			definition, has_definition = context_definition_for_iri(ctx, key)
		} else {
			array, valid := array_from_value(value)
			if !valid do return .Invalid_Expanded_JSON
			err: Compact_Error
			compacted_key, definition, has_definition, err = compact_property_term(state, ctx, key, array)
			if err != .None do return err
			subject_value, has_subject := object_value(object, "@id")
			subject_id, subject_valid := string_value(subject_value)
			if has_subject && !subject_valid do return .Invalid_Expanded_JSON
			if has_subject {
				matches := 0
				for annotation in state.compact_source_property_term_annotations {
					if annotation.subject_id != subject_id || annotation.predicate != key do continue
					matches += 1
					if matches > 1 { matches = -1; break }
					candidate, candidate_found := ctx.terms[annotation.term]
					if !candidate_found || candidate.id != key || candidate.reverse || !compact_values_match_definition(ctx, array, candidate) { matches = -1; break }
					compacted_key = annotation.term
					definition = candidate
					has_definition = true
					source_property_value = annotation.raw_value
					has_source_property_value = true
				}
				if matches != 1 do has_source_property_value = false
			}
			// An ordinary @index on a list is RDF-invisible. A list-container
			// term would consume the list and lose that annotation, so restore the
			// explicit list object from the retained source annotation instead.
			if len(array) == 1 {
				item, item_valid := object_from_value(array[0])
				_, has_list := object_value(item, "@list")
				if item_valid && has_list {
					subject_value, has_subject := object_value(object, "@id")
					subject_id, subject_valid := string_value(subject_value)
					if !has_subject do subject_id = ""
					if has_subject && !subject_valid do return .Invalid_Expanded_JSON
					index, found_index, index_error := compact_index_annotation(state, ctx, subject_id, key, key, definition.id, "", item)
					if index_error != .None do return index_error
					if !found_index do index, found_index = compact_raw_list_index_annotation(state, subject_id, key, key, definition.id)
					if found_index {
						source_index = index
						has_source_index = true
						if has_definition && definition.container_list {
							compacted_key = key
							definition = {}
							has_definition = false
						}
					}
				}
			}
			if has_definition && definition.container_language {
				subject_value, has_subject := object_value(object, "@id")
				subject_id, subject_valid := string_value(subject_value)
				if !has_subject do subject_id = ""
				if has_subject && !subject_valid do return .Invalid_Expanded_JSON
				raw_index_count := compact_raw_index_annotation_count(state, subject_id, key, key, definition.id)
				if raw_index_count == len(array) && raw_index_count > 0 {
					raw_index_subject = subject_id
					has_raw_index_values = true
					compacted_key = key
					definition = {}
					has_definition = false
				}
			}
			// A language map may represent @none, but an explicit language-null
			// term is the more specific source form for untagged values. Keep the
			// map for tagged values and emit that term separately.
			if has_definition && definition.container_language && len(array) > 1 {
				null_term := ""
				null_definition: Term_Definition
				for term, candidate in ctx.terms {
					if candidate.id != key || candidate.reverse || !candidate.language_null || candidate.container_set || candidate.container_list || candidate.container_language || candidate.container_index || candidate.container_id || candidate.container_type || candidate.container_graph || len(candidate.nest) > 0 do continue
					if len(null_term) > 0 { null_term = ""; break }
					null_term = term
					null_definition = candidate
				}
				if len(null_term) > 0 {
					mapped := make(json.Array)
					defer delete(mapped)
					plain := make(json.Array)
					defer delete(plain)
					for item in array {
						single := make(json.Array)
						append(&single, item)
						is_plain := compact_values_match_definition(ctx, single, null_definition)
						delete(single)
						if is_plain { append(&plain, item) } else { append(&mapped, item) }
					}
					if len(mapped) > 0 && len(plain) > 0 {
						if !first do strings.write_string(builder, ", ")
						write_json_string(builder, compacted_key)
						strings.write_string(builder, ": ")
						if map_error := compact_write_language_map(builder, state, ctx, object, key, mapped, policy, definition.container_set); map_error != .None do return map_error
						strings.write_string(builder, ", ")
						write_json_string(builder, null_term)
						strings.write_string(builder, ": ")
						if policy == .Compact && len(plain) == 1 && !null_definition.container_set {
							if value_error := compact_write_value_with_inherited_context(builder, state, ctx, type_context, plain[0], null_definition, true, policy); value_error != .None do return value_error
						} else {
							strings.write_byte(builder, '[')
							for item, index in plain {
								if index > 0 do strings.write_string(builder, ", ")
								if value_error := compact_write_value_with_inherited_context(builder, state, ctx, type_context, item, null_definition, true, policy); value_error != .None do return value_error
							}
							strings.write_byte(builder, ']')
						}
						first = false
						continue
					}
				}
			}
			// A mixed IRI set may require separate @id and @vocab aliases for the
			// same predicate. Split only this narrow coercion pair: other term
			// features continue through their dedicated container/value writers.
			if len(array) > 1 {
				groups := make([dynamic]Compact_List_Term_Group)
				split_iris := true
				for item in array {
					item_object, valid_item := object_from_value(item)
					item_id_value, has_item_id := object_value(item_object, "@id")
					item_id, valid_item_id := string_value(item_id_value)
					if !valid_item || !has_item_id || !valid_item_id { split_iris = false; break }
					single := make(json.Array)
					append(&single, item)
					term, candidate, candidate_found, candidate_error := compact_property_term(state, ctx, key, single)
					delete(single)
					if candidate_error != .None { destroy_compact_list_term_groups(&groups); return candidate_error }
					if !candidate_found || (candidate.type != "@id" && candidate.type != "@vocab") { split_iris = false; break }
					vocab_value, vocab_error := compact_iri(state, ctx, item_id, true)
					if vocab_error != .None { destroy_compact_list_term_groups(&groups); return vocab_error }
					if vocabulary_term, vocabulary_found := ctx.terms[vocab_value]; vocabulary_found && vocabulary_term.id == item_id {
						for candidate_term, candidate_definition in ctx.terms {
							if candidate_definition.id == key && !candidate_definition.reverse && candidate_definition.type == "@vocab" {
								term = candidate_term
								candidate = candidate_definition
								break
							}
						}
					}
					group_index := -1
					for group, index in groups do if group.term == term { group_index = index; break }
					if group_index < 0 {
						append(&groups, Compact_List_Term_Group{term = term, definition = candidate, has_definition = true, values = make([dynamic]json.Value)})
						group_index = len(groups) - 1
					}
					append(&groups[group_index].values, item)
				}
				if split_iris && len(groups) > 1 {
					for group in groups {
						if !first do strings.write_string(builder, ", ")
						write_json_string(builder, group.term)
						strings.write_string(builder, ": ")
						if policy == .Compact && len(group.values) == 1 && !group.definition.container_set {
							if value_error := compact_write_value_with_inherited_context(builder, state, ctx, type_context, group.values[0], group.definition, true, policy); value_error != .None { destroy_compact_list_term_groups(&groups); return value_error }
						} else {
							strings.write_byte(builder, '[')
							for grouped_value, grouped_index in group.values {
								if grouped_index > 0 do strings.write_string(builder, ", ")
								if value_error := compact_write_value_with_inherited_context(builder, state, ctx, type_context, grouped_value, group.definition, true, policy); value_error != .None { destroy_compact_list_term_groups(&groups); return value_error }
							}
							strings.write_byte(builder, ']')
						}
						first = false
					}
					destroy_compact_list_term_groups(&groups)
					continue
				}
				destroy_compact_list_term_groups(&groups)
			}
			// A list container term applies to one expanded list. Even when a
			// generic non-list term can carry every list object, split entries that
			// resolve to distinct list-container terms; otherwise language/type
			// coercions on those terms would be lost.
			if len(array) > 1 {
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
						append(&groups, Compact_List_Term_Group{term = term, definition = candidate, has_definition = candidate_found, values = make([dynamic]json.Value)})
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
			// A mixed value set can use distinct scalar terms for its individual
			// members (for example an English-language term plus an untyped
			// fallback). Split only when every term is unique and has no container
			// or nest behavior; those shapes require the normal grouped writer.
			if !has_definition && len(array) > 1 {
				groups := make([dynamic]Compact_Single_Value_Term_Group)
				defer delete(groups)
				split_values := true
				for item in array {
					single := make(json.Array)
					append(&single, item)
					term, candidate, candidate_found, candidate_error := compact_property_term(state, ctx, key, single)
					delete(single)
					if candidate_error != .None do return candidate_error
					if candidate_found && (candidate.container_set || candidate.container_list || candidate.container_language || candidate.container_index || candidate.container_id || candidate.container_type || candidate.container_graph || len(candidate.nest) > 0) {
						split_values = false
						break
					}
					for group in groups {
						if group.term == term { split_values = false; break }
					}
					if !split_values do break
					append(&groups, Compact_Single_Value_Term_Group{term = term, definition = candidate, has_definition = candidate_found, value = item})
				}
				if split_values && len(groups) > 1 {
					for group in groups {
						if !first do strings.write_string(builder, ", ")
						write_json_string(builder, group.term)
						strings.write_string(builder, ": ")
						if value_error := compact_write_value_with_inherited_context(builder, state, ctx, type_context, group.value, group.definition, group.has_definition, policy); value_error != .None do return value_error
						first = false
					}
					continue
				}
			}
			// Extend the scalar split to repeated terms and single list values.
			// This retains the regular array shape for repeated values while still
			// letting language/type/list coercions choose different terms for the
			// same expanded predicate. Map and graph containers remain on the
			// dedicated writer below.
			if !has_definition && len(array) > 1 {
				groups := make([dynamic]Compact_List_Term_Group)
				defer destroy_compact_list_term_groups(&groups)
				split_groups := true
				for item in array {
					single := make(json.Array)
					append(&single, item)
					term, candidate, candidate_found, candidate_error := compact_property_term(state, ctx, key, single)
					delete(single)
					if candidate_error != .None do return candidate_error
					if !candidate_found {
						item_object, item_is_object := object_from_value(item)
						_, item_is_list := object_value(item_object, "@list")
						plain_term, has_plain_term := compact_plain_property_term(ctx, key)
						if !item_is_object || item_is_list || !has_plain_term {
							split_groups = false
							break
						}
						term = plain_term
						candidate = {}
					} else if candidate.container_index || candidate.container_id || candidate.container_type || candidate.container_graph || candidate.container_language || len(candidate.nest) > 0 {
						split_groups = false
						break
					}
					group_index := -1
					for group, index in groups do if group.term == term { group_index = index; break }
					if group_index < 0 {
						append(&groups, Compact_List_Term_Group{term = term, definition = candidate, has_definition = candidate_found, values = make([dynamic]json.Value)})
						group_index = len(groups) - 1
					}
					append(&groups[group_index].values, item)
				}
				if split_groups && len(groups) > 1 {
					for group in groups {
						if group.definition.container_list && len(group.values) != 1 {
							split_groups = false
							break
						}
					}
				}
				if split_groups && len(groups) > 1 {
					for group in groups {
						if !first do strings.write_string(builder, ", ")
						write_json_string(builder, group.term)
						strings.write_string(builder, ": ")
						if group.definition.container_list {
							item, item_valid := object_from_value(group.values[0])
							list, has_list := object_value(item, "@list")
							if !item_valid || !has_list do return .Invalid_Expanded_JSON
							if list_error := compact_write_list(builder, state, ctx, list, group.definition, true, policy); list_error != .None do return list_error
						} else if policy == .Compact && len(group.values) == 1 && !group.definition.container_set {
							if value_error := compact_write_value_with_inherited_context(builder, state, ctx, type_context, group.values[0], group.definition, group.has_definition, policy); value_error != .None do return value_error
						} else {
							strings.write_byte(builder, '[')
							ordered_indices, order_error := compact_source_ordered_value_indices(state, object, key, group.values[:])
							if order_error != .None do return order_error
							defer delete(ordered_indices)
							for ordered_index, position in ordered_indices {
								if position > 0 do strings.write_string(builder, ", ")
								group_value := group.values[ordered_index]
								if value_error := compact_write_value_with_inherited_context(builder, state, ctx, type_context, group_value, group.definition, group.has_definition, policy); value_error != .None do return value_error
							}
							strings.write_byte(builder, ']')
						}
						first = false
					}
					continue
				}
			}
			// A direction-constrained language map can consume only the values
			// whose direction matches its term. Keep the remaining values under a
			// non-term compact IRI so their explicit direction semantics survive.
			if !has_definition && len(array) > 1 {
				language_term := ""
				language_definition: Term_Definition
				for term, candidate in ctx.terms {
					if candidate.id != key || candidate.reverse || !candidate.container_language || !candidate.has_direction do continue
					if len(language_term) > 0 { language_term = ""; break }
					language_term = term
					language_definition = candidate
				}
				if len(language_term) > 0 {
					mapped := make(json.Array)
					defer delete(mapped)
					remaining := make(json.Array)
					defer delete(remaining)
					for item in array {
						single := make(json.Array)
						append(&single, item)
						matches := compact_values_match_definition(ctx, single, language_definition)
						delete(single)
						if matches { append(&mapped, item) } else { append(&remaining, item) }
					}
					fallback_term, fallback_error := compact_undefined_prefixed_property(state, ctx, key)
					if fallback_error != .None do return fallback_error
					if len(mapped) > 0 && len(remaining) > 0 && len(fallback_term) > 0 {
						if !first do strings.write_string(builder, ", ")
						write_json_string(builder, language_term)
						strings.write_string(builder, ": ")
						if map_error := compact_write_language_map(builder, state, ctx, object, key, mapped, policy, language_definition.container_set); map_error != .None do return map_error
						strings.write_string(builder, ", ")
						write_json_string(builder, fallback_term)
						strings.write_string(builder, ": [")
						ordered_indices, order_error := compact_source_ordered_value_indices(state, object, key, remaining[:])
						if order_error != .None do return order_error
						defer delete(ordered_indices)
						for ordered_index, position in ordered_indices {
							if position > 0 do strings.write_string(builder, ", ")
							if value_error := compact_write_value_with_inherited_context(builder, state, ctx, type_context, remaining[ordered_index], {}, false, policy); value_error != .None do return value_error
						}
						strings.write_byte(builder, ']')
						first = false
						continue
					}
				}
			}
		}
		output := builder
		nest_index := -1
		if has_definition && len(definition.nest) > 0 {
			for nest, index in nests do if nest.term == definition.nest { nest_index = index; break }
			if nest_index < 0 {
				append(&nests, Compact_Nest_Output{term = definition.nest, properties = strings.builder_make()})
				nest_index = len(nests) - 1
			}
			output = &nests[nest_index].properties
			if nests[nest_index].count > 0 do strings.write_string(output, ", ")
		} else if !first do strings.write_string(output, ", ")
		write_json_string(output, compacted_key)
		strings.write_string(output, ": ")
		if key == "@id" {
			if err := compact_write_identifier(output, state, ctx, value, false); err != .None do return err
		} else if key == "@type" {
			array, valid := array_from_value(value)
			if !valid do return .Invalid_Expanded_JSON
			if policy == .Compact && len(array) == 1 && !ctx.type_container_set && (!has_definition || !definition.container_set || state.legacy_prefixes) {
				if err := compact_write_identifier(output, state, type_context, array[0], true); err != .None do return err
			} else {
				restored, restore_error := compact_write_source_type_order(output, state, type_context, object, array)
				if restore_error != .None do return restore_error
				if !restored {
					strings.write_byte(output, '[')
					for reverse_index := len(array) - 1; reverse_index >= 0; reverse_index -= 1 {
						item := array[reverse_index]
						index := len(array) - reverse_index - 1
						if index > 0 do strings.write_string(output, ", ")
						if err := compact_write_identifier(output, state, type_context, item, true); err != .None do return err
					}
					strings.write_byte(output, ']')
				}
			}
		} else if key == "@graph" {
			array, valid := array_from_value(value)
			if !valid do return .Invalid_Expanded_JSON
			strings.write_byte(output, '[')
			for item, index in array {
				if index > 0 do strings.write_string(output, ", ")
				node, node_valid := object_from_value(item)
				if !node_valid do return .Invalid_Expanded_JSON
				if err := compact_write_graph_node(output, state, ctx, node, policy); err != .None do return err
			}
			strings.write_byte(output, ']')
		} else {
			array, valid := array_from_value(value)
			if !valid do return .Invalid_Expanded_JSON
			handled_annotation := false
			if has_source_property_value && len(array) == 1 && has_definition && (definition.type == "@id" || definition.type == "@vocab") && !definition.container_set && !definition.container_list && !definition.container_language && !definition.container_index && !definition.container_id && !definition.container_type && !definition.container_graph {
				write_json_string(output, source_property_value)
				handled_annotation = true
			}
			if has_definition && definition.container_set {
				set_handled, set_error := compact_write_source_duplicate_set(output, state, ctx, type_context, object, key, array, definition, policy)
				if set_error != .None do return set_error
				handled_annotation = set_handled
			}
			if !handled_annotation && has_definition && definition.type == "@none" {
				notype_handled, notype_error := compact_write_source_notype_values(output, state, ctx, type_context, object, key, array, definition, policy)
				if notype_error != .None do return notype_error
				handled_annotation = notype_handled
			}
			if has_definition && definition.container_index && (!definition.has_index || definition.index == "@index") {
				annotation_handled, annotation_error := compact_write_annotated_index_map(output, state, ctx, object, compacted_key, key, definition.id, array, definition, policy)
				if annotation_error != .None do return annotation_error
				handled_annotation = annotation_handled
			}
			if !handled_annotation && has_definition && definition.container_graph && (definition.container_index || definition.container_id) {
				graph_map_handled, graph_map_error := compact_write_source_graph_index_map(output, state, ctx, array, definition, policy)
				if graph_map_error != .None do return graph_map_error
				handled_annotation = graph_map_handled
			}
			if !handled_annotation && has_definition && definition.container_type {
				type_map_handled, type_map_error := compact_write_type_map(output, state, ctx, array, definition, policy)
				if type_map_error != .None do return type_map_error
				if !type_map_handled do return .Invalid_Expanded_JSON
				handled_annotation = true
			}
			if !handled_annotation && has_definition && definition.container_id && !definition.container_graph {
				id_map_handled, id_map_error := compact_write_id_map(output, state, ctx, array, definition, policy)
				if id_map_error != .None do return id_map_error
				if !id_map_handled do return .Invalid_Expanded_JSON
				handled_annotation = true
			}
			if !handled_annotation && has_definition && definition.container_index && definition.has_index && definition.index != "@index" {
				handled, index_error := compact_write_property_index_map(output, state, ctx, array, definition, policy)
				if index_error != .None do return index_error
				if !handled do return .Invalid_Expanded_JSON
			} else if !handled_annotation && has_definition && definition.container_language {
				if err := compact_write_language_map(output, state, ctx, object, key, array, policy, definition.container_set); err != .None do return err
			} else if !handled_annotation && has_definition && definition.container_list && len(array) == 1 {
				item, item_valid := object_from_value(array[0])
				list, has_list := object_value(item, "@list")
				if !item_valid || !has_list do return .Invalid_Expanded_JSON
				if err := compact_write_list(output, state, ctx, list, definition, has_definition, policy); err != .None do return err
			} else if !handled_annotation && has_source_index {
				item, item_valid := object_from_value(array[0])
				list, has_list := object_value(item, "@list")
				if !item_valid || !has_list do return .Invalid_Expanded_JSON
				strings.write_byte(output, '{')
				write_json_string(output, compact_keyword(ctx, "@list"))
				strings.write_string(output, ": ")
				if list_error := compact_write_list(output, state, ctx, list, {}, false, policy); list_error != .None do return list_error
				strings.write_string(output, ", ")
				write_json_string(output, compact_keyword(ctx, "@index"))
				strings.write_string(output, ": ")
				write_json_string(output, source_index)
				strings.write_byte(output, '}')
			} else if !handled_annotation && has_raw_index_values {
				strings.write_byte(output, '[')
				ordered_indices, order_error := compact_source_ordered_value_indices(state, object, key, array[:])
				if order_error != .None do return order_error
				defer delete(ordered_indices)
				for ordered_index, position in ordered_indices {
					index, found_index := compact_raw_index_annotation_at(state, raw_index_subject, key, key, "", position)
					if !found_index do return .Invalid_Expanded_JSON
					value_builder := strings.builder_make()
					value_error := compact_write_value_with_inherited_context(&value_builder, state, ctx, type_context, array[ordered_index], {}, false, policy)
					value_text := strings.to_string(value_builder)
					if value_error != .None { strings.builder_destroy(&value_builder); return value_error }
					if len(value_text) < 2 || value_text[0] != '{' || value_text[len(value_text) - 1] != '}' { strings.builder_destroy(&value_builder); return .Invalid_Expanded_JSON }
					if position > 0 do strings.write_string(output, ", ")
					strings.write_string(output, value_text[:len(value_text) - 1])
					strings.write_string(output, ", \"@index\": ")
					write_json_string(output, index)
					strings.write_byte(output, '}')
					strings.builder_destroy(&value_builder)
				}
				strings.write_byte(output, ']')
			} else if !handled_annotation && compact_property_has_source_index(state, object, key) {
				indexed_handled, indexed_error := compact_write_source_indexed_values(output, state, ctx, type_context, object, key, array, definition, has_definition, policy)
				if indexed_error != .None do return indexed_error
				if !indexed_handled do return .Invalid_Expanded_JSON
			} else if !handled_annotation && policy == .Compact && len(array) == 1 && has_definition && definition.container_set && definition.type == "@json" && compact_value_is_json_array(array[0]) {
				if err := compact_write_value_with_inherited_context(output, state, ctx, type_context, array[0], definition, has_definition, policy); err != .None do return err
			} else if !handled_annotation && policy == .Compact && len(array) == 1 && (!has_definition || !definition.container_set || (definition.container_graph && compact_value_has_source_graph_recovery(state, array[0]))) {
				force_source_graph_set := has_definition && definition.container_graph && definition.container_set && compact_value_has_source_graph_recovery(state, array[0])
				state.compact_source_graph_set_value = force_source_graph_set
				err := compact_write_value_with_inherited_context(output, state, ctx, type_context, array[0], definition, has_definition, policy)
				state.compact_source_graph_set_value = false
				if err != .None do return err
			} else if !handled_annotation {
				strings.write_byte(output, '[')
				ordered_indices, order_error := compact_source_ordered_value_indices(state, object, key, array[:])
				if order_error != .None do return order_error
				defer delete(ordered_indices)
				for ordered_index, position in ordered_indices {
					if position > 0 do strings.write_string(output, ", ")
					item := array[ordered_index]
					if err := compact_write_value_with_inherited_context(output, state, ctx, type_context, item, definition, has_definition, policy); err != .None do return err
				}
				strings.write_byte(output, ']')
			}
		}
		if nest_index >= 0 {
			nests[nest_index].count += 1
		} else {
			first = false
		}
	}
	if empty_error := compact_write_source_empty_properties(builder, state, ctx, object, &first); empty_error != .None do return empty_error
	for nest in nests {
		if nest.count == 0 do continue
		if !first do strings.write_string(builder, ", ")
		write_json_string(builder, nest.term)
		strings.write_string(builder, ": {")
		strings.write_string(builder, strings.to_string(nest.properties))
		strings.write_byte(builder, '}')
		first = false
	}
	if err := compact_write_reverse_references(builder, state, ctx, object, policy, &first); err != .None do return err
	strings.write_byte(builder, '}')
	return .None
}

@(private) compact_leave_node :: proc(state: ^State) {
	state.compact_node_depth -= 1
}

@(private) compact_clear_omitted_singleton_blank_id :: proc(state: ^State) {
	state.compact_omit_singleton_blank_id = ""
}

@(private) compact_reverse_source_without_reference :: proc(source: json.Object, predicate, target_id: string) -> json.Object {
	temporary := make(json.Object)
	for key, value in source {
		if key != predicate {
			temporary[key] = value
			continue
		}
		values, valid_values := array_from_value(value)
		if !valid_values {
			temporary[key] = value
			continue
		}
		remaining := make(json.Array)
		for item in values {
			candidate, is_candidate := object_from_value(item)
			candidate_id, has_candidate_id := object_value(candidate, "@id")
			identifier, valid_identifier := string_value(candidate_id)
			if is_candidate && has_candidate_id && valid_identifier && identifier == target_id do continue
			append(&remaining, item)
		}
		if len(remaining) == 0 {
			delete(remaining)
		} else {
			temporary[key] = remaining
		}
	}
	return temporary
}

@(private) compact_reverse_predicate_indices :: proc(state: ^State, target_index: int) -> [dynamic]int {
	predicates := make([dynamic]int)
	for reference in state.compact_reverse_refs {
		if reference.target_index != target_index do continue
		found := false
		for predicate in predicates do if predicate == reference.predicate_index { found = true; break }
		if !found do append(&predicates, reference.predicate_index)
	}
	sort_state := Compact_Reverse_Predicate_Sort{state = state, indices = &predicates}
	sort.sort(sort.Interface{
		collection = rawptr(&sort_state),
		len = proc(it: sort.Interface) -> int { return len((cast(^Compact_Reverse_Predicate_Sort)it.collection).indices^) },
		less = proc(it: sort.Interface, i, j: int) -> bool {
			sort_state := cast(^Compact_Reverse_Predicate_Sort)it.collection
			return strings.compare(sort_state.state.compact_reverse_predicate_iris[sort_state.indices[i]], sort_state.state.compact_reverse_predicate_iris[sort_state.indices[j]]) < 0
		},
		swap = proc(it: sort.Interface, i, j: int) {
			sort_state := cast(^Compact_Reverse_Predicate_Sort)it.collection
			sort_state.indices[i], sort_state.indices[j] = sort_state.indices[j], sort_state.indices[i]
		},
	})
	return predicates
}

@(private) compact_reverse_term :: proc(ctx: ^Context, predicate: string) -> (string, Term_Definition, bool) {
	term := ""
	definition: Term_Definition
	for candidate, candidate_definition in ctx.terms {
		if !candidate_definition.reverse || candidate_definition.id != predicate do continue
		if len(term) > 0 do return "", {}, false
		term = candidate
		definition = candidate_definition
	}
	return term, definition, len(term) > 0
}

@(private) compact_write_reverse_reference_value :: proc(builder: ^strings.Builder, state: ^State, ctx: ^Context, source: json.Object, predicate, target_id: string, definition: Term_Definition, policy: Compact_Array_Policy) -> Compact_Error {
	temporary := compact_reverse_source_without_reference(source, predicate, target_id)
	defer {
		if remaining_value, has_remaining := object_value(temporary, predicate); has_remaining {
			if remaining, valid_remaining := array_from_value(remaining_value); valid_remaining do delete(remaining)
		}
		delete(temporary)
	}
	source_id_value, has_source_id := object_value(temporary, "@id")
	source_id, valid_source_id := string_value(source_id_value)
	if has_source_id && valid_source_id && strings.has_prefix(source_id, "_:") do delete_key(&temporary, "@id")
	if len(temporary) == 1 {
		if identifier, has_identifier := object_value(temporary, "@id"); has_identifier {
			if definition.type == "@id" || definition.type == "@vocab" do return compact_write_identifier(builder, state, ctx, identifier, definition.type == "@vocab", definition.type != "@id")
			strings.write_byte(builder, '{')
			write_json_string(builder, compact_keyword(ctx, "@id"))
			strings.write_string(builder, ": ")
			if err := compact_write_identifier(builder, state, ctx, identifier, false); err != .None do return err
			strings.write_byte(builder, '}')
			return .None
		}
	}
	state.compacting_reverse_reference = true
	err := compact_write_referenced_node(builder, state, ctx, temporary, policy)
	state.compacting_reverse_reference = false
	return err
}

@(private) compact_write_reverse_index_map :: proc(builder: ^strings.Builder, state: ^State, ctx: ^Context, target_index, predicate_index: int, target_id: string, definition: Term_Definition, policy: Compact_Array_Policy) -> (bool, Compact_Error) {
	predicate := state.compact_reverse_predicate_iris[predicate_index]
	groups := make([dynamic]Compact_Annotated_Index_Group)
	defer destroy_compact_annotated_index_groups(&groups)
	for reference in state.compact_reverse_refs {
		if reference.target_index != target_index || reference.predicate_index != predicate_index do continue
		source, found_source := state.compact_nodes[state.compact_reverse_source_ids[reference.source_index]]
		if !found_source do return false, .None
		source_id_value, has_source_id := object_value(source, "@id")
		source_id, valid_source_id := string_value(source_id_value)
		if !has_source_id || !valid_source_id do return false, .None
		index, found_index, index_error := compact_index_annotation(state, ctx, target_id, predicate, predicate, definition.id, source_id, source)
		if index_error != .None do return false, index_error
		if !found_index do return false, .None
		group_index := -1
		for group, candidate_index in groups do if group.key == index { group_index = candidate_index; break }
		if group_index < 0 {
			append(&groups, Compact_Annotated_Index_Group{key = index, values = make([dynamic]json.Value)})
			group_index = len(groups) - 1
		}
		append(&groups[group_index].values, source)
	}
	if len(groups) == 0 do return false, .None
	strings.write_byte(builder, '{')
	for group, group_index in groups {
		if group_index > 0 do strings.write_string(builder, ", ")
		write_json_string(builder, group.key)
		strings.write_string(builder, ": ")
		write_array := policy != .Compact || len(group.values) != 1 || definition.container_set
		if write_array do strings.write_byte(builder, '[')
		for source_value, source_index in group.values {
			if source_index > 0 do strings.write_string(builder, ", ")
			source, valid_source := object_from_value(source_value)
			if !valid_source do return false, .Invalid_Expanded_JSON
			if err := compact_write_reverse_reference_value(builder, state, ctx, source, predicate, target_id, definition, policy); err != .None do return false, err
		}
		if write_array do strings.write_byte(builder, ']')
	}
	strings.write_byte(builder, '}')
	return true, .None
}

@(private) compact_write_reverse_references :: proc(builder: ^strings.Builder, state: ^State, ctx: ^Context, object: json.Object, policy: Compact_Array_Policy, first: ^bool) -> Compact_Error {
	if state.compacting_reverse_reference || state.compact_node_depth != 1 do return .None
	id_value, has_id := object_value(object, "@id")
	identifier, valid_identifier := string_value(id_value)
	if !has_id || !valid_identifier do return .None
	target_index, found_target := state.compact_reverse_target_indices[identifier]
	if !found_target do return .None
	predicates := compact_reverse_predicate_indices(state, target_index)
	defer delete(predicates)
	for predicate_index in predicates {
		predicate := state.compact_reverse_predicate_iris[predicate_index]
		term, definition, has_term := compact_reverse_term(ctx, predicate)
		if !has_term do continue
		if !first^ do strings.write_string(builder, ", ")
		write_json_string(builder, term)
		strings.write_string(builder, ": ")
		if definition.container_index {
			handled, index_error := compact_write_reverse_index_map(builder, state, ctx, target_index, predicate_index, identifier, definition, policy)
			if index_error != .None do return index_error
			if !handled do return .Invalid_Expanded_JSON
			first^ = false
			continue
		}
		matches := 0
		for reference in state.compact_reverse_refs do if reference.target_index == target_index && reference.predicate_index == predicate_index { matches += 1 }
		write_array := policy != .Compact || matches != 1 || definition.container_set
		if write_array do strings.write_byte(builder, '[')
		written := 0
		for reference in state.compact_reverse_refs {
			if reference.target_index != target_index || reference.predicate_index != predicate_index do continue
			source, found_source := state.compact_nodes[state.compact_reverse_source_ids[reference.source_index]]
			if !found_source do continue
			if written > 0 do strings.write_string(builder, ", ")
			if err := compact_write_reverse_reference_value(builder, state, ctx, source, predicate, identifier, definition, policy); err != .None do return err
			written += 1
		}
		if write_array do strings.write_byte(builder, ']')
		first^ = false
	}
	writable_predicates := make([dynamic]int)
	defer delete(writable_predicates)
	for predicate_index in predicates {
		predicate := state.compact_reverse_predicate_iris[predicate_index]
		_, _, has_reverse_term := compact_reverse_term(ctx, predicate)
		if has_reverse_term do continue
		definition, has_definition := context_definition_for_iri(ctx, predicate)
		if has_definition && (definition.reverse || definition.has_local_context || definition.container_list || definition.container_set || definition.container_language || definition.container_index || definition.container_graph || definition.container_id || definition.container_type || definition.has_language || definition.language_null || definition.has_direction || definition.direction_null || (len(definition.type) > 0 && identifier != state.compact_source_reverse_root_id)) do continue
		append(&writable_predicates, predicate_index)
	}
	if len(writable_predicates) == 0 do return .None
	if !first^ do strings.write_string(builder, ", ")
	write_json_string(builder, compact_keyword(ctx, "@reverse"))
	strings.write_string(builder, ": {")
	reverse_written := 0
	for predicate_index in writable_predicates {
		predicate := state.compact_reverse_predicate_iris[predicate_index]
		definition, has_definition := context_definition_for_iri(ctx, predicate)
		if has_definition && len(definition.type) > 0 {
			groups := make([dynamic]Compact_List_Term_Group)
			for reference in state.compact_reverse_refs {
				if reference.target_index != target_index || reference.predicate_index != predicate_index do continue
				source, found_source := state.compact_nodes[state.compact_reverse_source_ids[reference.source_index]]
				if !found_source do continue
				source_id_value, has_source_id := object_value(source, "@id")
				source_id, valid_source_id := string_value(source_id_value)
				if !has_source_id || !valid_source_id {
					destroy_compact_list_term_groups(&groups)
					return .Invalid_Expanded_JSON
				}
				reference_value := make(json.Object)
				reference_value["@id"] = source_id
				single := make(json.Array)
				append(&single, json.Value(reference_value))
				term, term_definition, _, term_error := compact_property_term(state, ctx, predicate, single)
				delete(single)
				delete(reference_value)
				if term_error != .None {
					destroy_compact_list_term_groups(&groups)
					return term_error
				}
				// When both @id and @vocab aliases apply, @vocab is more specific
				// only if this identifier can itself be represented by a vocabulary
				// term. Otherwise keep the ordinary @id coercion.
				vocab_value, vocab_error := compact_iri(state, ctx, source_id, true)
				if vocab_error != .None {
					destroy_compact_list_term_groups(&groups)
					return vocab_error
				}
				if vocabulary_term, vocabulary_found := ctx.terms[vocab_value]; vocabulary_found && vocabulary_term.id == source_id {
					for candidate, candidate_definition in ctx.terms {
						if candidate_definition.id == predicate && !candidate_definition.reverse && candidate_definition.type == "@vocab" {
							term = candidate
							term_definition = candidate_definition
							break
						}
					}
				}
				group_index := -1
				for group, index in groups do if group.term == term { group_index = index; break }
				if group_index < 0 {
					append(&groups, Compact_List_Term_Group{term = term, definition = term_definition, has_definition = true, values = make([dynamic]json.Value)})
					group_index = len(groups) - 1
				}
				append(&groups[group_index].values, source)
			}
			for group in groups {
				if reverse_written > 0 do strings.write_string(builder, ", ")
				write_json_string(builder, group.term)
				strings.write_string(builder, ": ")
				write_array := policy != .Compact || len(group.values) != 1 || group.definition.container_set
				if write_array do strings.write_byte(builder, '[')
				for source_value, source_index in group.values {
					if source_index > 0 do strings.write_string(builder, ", ")
					source, valid_source := object_from_value(source_value)
					if !valid_source {
						destroy_compact_list_term_groups(&groups)
						return .Invalid_Expanded_JSON
					}
					if err := compact_write_reverse_reference_value(builder, state, ctx, source, predicate, identifier, group.definition, policy); err != .None {
						destroy_compact_list_term_groups(&groups)
						return err
					}
				}
				if write_array do strings.write_byte(builder, ']')
				reverse_written += 1
			}
			destroy_compact_list_term_groups(&groups)
			continue
		}
		if reverse_written > 0 do strings.write_string(builder, ", ")
		compacted_predicate, predicate_error := compact_iri(state, ctx, predicate, true)
		if predicate_error != .None do return predicate_error
		write_json_string(builder, compacted_predicate)
		strings.write_string(builder, ": ")
		matches := 0
		for reference in state.compact_reverse_refs do if reference.target_index == target_index && reference.predicate_index == predicate_index { matches += 1 }
		if policy != .Compact || matches != 1 do strings.write_byte(builder, '[')
		written := 0
		for reference in state.compact_reverse_refs {
			if reference.target_index != target_index || reference.predicate_index != predicate_index do continue
			source, found_source := state.compact_nodes[state.compact_reverse_source_ids[reference.source_index]]
			if !found_source do continue
			if written > 0 do strings.write_string(builder, ", ")
			temporary := compact_reverse_source_without_reference(source, predicate, identifier)
			state.compacting_reverse_reference = true
			err := compact_write_referenced_node(builder, state, ctx, temporary, policy)
			state.compacting_reverse_reference = false
			if remaining_value, has_remaining := object_value(temporary, predicate); has_remaining {
				if remaining, valid_remaining := array_from_value(remaining_value); valid_remaining do delete(remaining)
			}
			delete(temporary)
			if err != .None do return err
			written += 1
		}
		if policy != .Compact || matches != 1 do strings.write_byte(builder, ']')
		reverse_written += 1
	}
	strings.write_byte(builder, '}')
	first^ = false
	return .None
}

@(private) compact_build_reverse_reference_index :: proc(state: ^State, nodes: json.Array) -> Compact_Error {
	state.compact_reverse_refs = make([dynamic]Compact_Reverse_Reference)
	state.compact_reverse_target_indices = make(map[string]int)
	for node_value in nodes {
		source, valid_source := object_from_value(node_value)
		if !valid_source do return .Invalid_Expanded_JSON
		source_id_value, has_source_id := object_value(source, "@id")
		source_id, valid_source_id := string_value(source_id_value)
		if !has_source_id || !valid_source_id do continue
		source_copy, source_error := strings.clone(source_id)
		if source_error != nil do return .Out_Of_Memory
		append(&state.compact_reverse_source_ids, source_copy)
		source_index := len(state.compact_reverse_source_ids) - 1
		for predicate, values_value in source {
			if is_keyword(predicate) do continue
			values, valid_values := array_from_value(values_value)
			if !valid_values do return .Invalid_Expanded_JSON
			for value in values {
				target, valid_target := object_from_value(value)
				if !valid_target do continue
				target_id_value, has_target_id := object_value(target, "@id")
				target_id, valid_target_id := string_value(target_id_value)
				if !has_target_id || !valid_target_id do continue
				if _, found_target := state.compact_nodes[target_id]; !found_target do continue
				target_index, found_target_index := state.compact_reverse_target_indices[target_id]
				if !found_target_index {
					target_copy, target_error := strings.clone(target_id)
					if target_error != nil do return .Out_Of_Memory
					append(&state.compact_reverse_target_ids, target_copy)
					target_index = len(state.compact_reverse_target_ids) - 1
					state.compact_reverse_target_indices[target_id] = target_index
				}
				predicate_index := -1
				for candidate, index in state.compact_reverse_predicate_iris do if candidate == predicate { predicate_index = index; break }
				if predicate_index < 0 {
					predicate_copy, predicate_error := strings.clone(predicate)
					if predicate_error != nil do return .Out_Of_Memory
					append(&state.compact_reverse_predicate_iris, predicate_copy)
					predicate_index = len(state.compact_reverse_predicate_iris) - 1
				}
				append(&state.compact_reverse_refs, Compact_Reverse_Reference{target_index = target_index, source_index = source_index, predicate_index = predicate_index})
			}
		}
	}
	return .None
}

// compact_mark_source_reverse_index_nodes matches each source reverse-map
// statement to one serialized node after the root-only reverse edge is
// removed. A non-unique match is deliberately left unrecovered.
@(private) compact_mark_source_reverse_index_nodes :: proc(state: ^State, nodes: json.Array) -> Compact_Error {
	if len(state.compact_source_reverse_index_annotations) == 0 do return .None
	for &annotation in state.compact_source_reverse_index_annotations {
		match_id := ""
		for node_value in nodes {
			source, valid_source := object_from_value(node_value)
			if !valid_source do return .Invalid_Expanded_JSON
			source_id_value, has_source_id := object_value(source, "@id")
			source_id, valid_source_id := string_value(source_id_value)
			if !has_source_id || !valid_source_id do continue
			values_value, has_values := object_value(source, annotation.reverse_predicate)
			values, valid_values := array_from_value(values_value)
			if !has_values || !valid_values do continue
			references_root := false
			for value in values {
				reference, valid_reference := object_from_value(value)
				reference_id_value, has_reference_id := object_value(reference, "@id")
				reference_id, valid_reference_id := string_value(reference_id_value)
				if valid_reference && has_reference_id && valid_reference_id && reference_id == annotation.root_id { references_root = true; break }
			}
			if !references_root do continue
			temporary := compact_reverse_source_without_reference(source, annotation.reverse_predicate, annotation.root_id)
			signature, signature_error := compact_graph_fragment_signature(json.Value(temporary))
			delete(temporary)
			if signature_error != .None do return signature_error
			matches := signature == annotation.source_signature
			delete(signature)
			if !matches do continue
			if len(match_id) > 0 do return .None
			owned_match, match_error := own(state, source_id)
			if match_error.code != .None do return .Out_Of_Memory
			match_id = owned_match
		}
		if len(match_id) == 0 do return .None
		annotation.source_node_id = match_id
	}
	return .None
}

// compact_mark_source_included_nodes reconnects a source @included boundary
// only when its root and every included child have unique serialized matches.
@(private) compact_mark_source_included_nodes :: proc(state: ^State, nodes: json.Array) -> Compact_Error {
	if len(state.compact_source_included_roots) == 0 do return .None
	for &root in state.compact_source_included_roots {
		root_id := ""
		parent_id := ""
		if !root.root_empty {
			for node_value in nodes {
				node, valid_node := object_from_value(node_value)
				if !valid_node do return .Invalid_Expanded_JSON
				node_id_value, has_node_id := object_value(node, "@id")
				node_id, valid_node_id := string_value(node_id_value)
				if !has_node_id || !valid_node_id do continue
				signature_value := node_value
				candidate_parent_id := ""
				if len(root.parent_predicate) > 0 {
					for parent_value in nodes {
						parent, valid_parent := object_from_value(parent_value)
						parent_id_value, has_parent_id := object_value(parent, "@id")
						parent_id, valid_parent_id := string_value(parent_id_value)
						parent_values_value, has_parent_values := object_value(parent, root.parent_predicate)
						parent_values, valid_parent_values := array_from_value(parent_values_value)
						if !valid_parent || !has_parent_id || !valid_parent_id || !has_parent_values || !valid_parent_values || len(parent_values) != 1 do continue
						parent_target, valid_parent_target := object_from_value(parent_values[0])
						parent_target_id_value, has_parent_target_id := object_value(parent_target, "@id")
						parent_target_id, valid_parent_target_id := string_value(parent_target_id_value)
						if !valid_parent_target || !has_parent_target_id || !valid_parent_target_id || parent_target_id != node_id do continue
						if len(candidate_parent_id) > 0 {
							candidate_parent_id = ""
							break
						}
						candidate_parent_id = parent_id
					}
					if len(candidate_parent_id) == 0 do continue
				}
				signature, signature_error := compact_graph_fragment_signature(signature_value)
				if signature_error != .None do return signature_error
				matches := signature == root.root_signature
				delete(signature)
				if !matches do continue
				if len(root_id) > 0 do return .None
				owned_root_id, root_error := own(state, node_id)
				if root_error.code != .None do return .Out_Of_Memory
				root_id = owned_root_id
				if len(candidate_parent_id) > 0 {
					owned_parent_id, parent_error := own(state, candidate_parent_id)
					if parent_error.code != .None do return .Out_Of_Memory
					parent_id = owned_parent_id
				}
			}
			if len(root_id) == 0 do return .None
		}
		child_count := 0
		for &child in state.compact_source_included_children {
			if child.root_signature != root.root_signature do continue
			child_count += 1
			match_id := ""
			for node_value in nodes {
				node, valid_node := object_from_value(node_value)
				if !valid_node do return .Invalid_Expanded_JSON
				node_id_value, has_node_id := object_value(node, "@id")
				node_id, valid_node_id := string_value(node_id_value)
				if !has_node_id || !valid_node_id || (!root.root_empty && node_id == root_id) do continue
				signature, signature_error := compact_graph_fragment_signature(node_value)
				if signature_error != .None do return signature_error
				matches := signature == child.signature
				delete(signature)
				if !matches do continue
				if len(match_id) > 0 do return .None
				owned_child_id, child_error := own(state, node_id)
				if child_error.code != .None do return .Out_Of_Memory
				match_id = owned_child_id
			}
			if len(match_id) == 0 do return .None
			child.node_id = match_id
		}
		if child_count == 0 do return .None
		root.root_node_id = root_id
		root.parent_node_id = parent_id
	}
	return .None
}

// compact_write_source_reverse_index_root restores the source root that is
// represented only as the object of a reverse RDF edge. The narrow one-entry
// form is emitted only after compact_mark_source_reverse_index_nodes proved a
// unique source statement match.
@(private) compact_write_source_reverse_index_root :: proc(builder: ^strings.Builder, state: ^State, ctx: ^Context, policy: Compact_Array_Policy) -> (bool, Compact_Error) {
	if len(state.compact_source_reverse_index_annotations) != 1 do return false, .None
	annotation := state.compact_source_reverse_index_annotations[0]
	if len(annotation.source_node_id) == 0 do return false, .None
	source, found_source := state.compact_nodes[annotation.source_node_id]
	if !found_source do return false, .None
	root_id, root_error := compact_iri(state, ctx, annotation.root_id, false)
	if root_error != .None do return false, root_error
	index_id, index_error := compact_iri(state, ctx, annotation.index_id, true)
	if index_error != .None do return false, index_error
	temporary := compact_reverse_source_without_reference(source, annotation.reverse_predicate, annotation.root_id)
	defer delete(temporary)
	delete_key(&temporary, "@id")
	delete_key(&temporary, annotation.index_predicate)
	strings.write_byte(builder, '{')
	write_json_string(builder, compact_keyword(ctx, "@id"))
	strings.write_string(builder, ": ")
	write_json_string(builder, root_id)
	strings.write_string(builder, ", ")
	write_json_string(builder, annotation.term)
	strings.write_string(builder, ": {")
	write_json_string(builder, index_id)
	strings.write_string(builder, ": ")
	if node_error := compact_write_node(builder, state, ctx, temporary, policy); node_error != .None do return false, node_error
	strings.write_string(builder, "}}")
	return true, .None
}

@(private) compact_write_source_included_node :: proc(builder: ^strings.Builder, state: ^State, ctx: ^Context, root_signature: string, policy: Compact_Array_Policy) -> Compact_Error {
	root_index := -1
	for root, index in state.compact_source_included_roots {
		if root.root_signature == root_signature {
			if root_index >= 0 do return .Invalid_Expanded_JSON
			root_index = index
		}
	}
	if root_index < 0 do return .Invalid_Expanded_JSON
	root := state.compact_source_included_roots[root_index]
	root_builder := strings.builder_make()
	defer strings.builder_destroy(&root_builder)
	if root.root_empty {
		strings.write_byte(&root_builder, '{')
	} else {
		if len(root.root_node_id) == 0 do return .Invalid_Expanded_JSON
		source_root, found_root := state.compact_nodes[root.root_node_id]
		if !found_root do return .Invalid_Expanded_JSON
		root_temporary := make(json.Object)
		defer delete(root_temporary)
		for key, value in source_root {
			if key != "@id" && (len(root.parent_predicate) == 0 || key != "@reverse") do root_temporary[key] = value
		}
		if root_error := compact_write_node(&root_builder, state, ctx, root_temporary, policy); root_error != .None do return root_error
	}
	root_text := strings.to_string(root_builder)
	if root.root_empty {
		strings.write_byte(builder, '{')
	} else {
		if len(root_text) < 2 do return .Invalid_Expanded_JSON
		strings.write_string(builder, root_text[:len(root_text) - 1])
		if len(root_text) > 2 do strings.write_string(builder, ", ")
	}
	write_json_string(builder, compact_keyword(ctx, "@included"))
	strings.write_string(builder, ": ")
	child_count := 0
	for child in state.compact_source_included_children {
		if child.root_signature == root.root_signature do child_count += 1
	}
	if child_count == 0 do return .Invalid_Expanded_JSON
	if root.container_set || child_count > 1 do strings.write_byte(builder, '[')
	written := 0
	for child in state.compact_source_included_children {
		if child.root_signature != root.root_signature do continue
		if written > 0 do strings.write_string(builder, ", ")
		nested := false
		for candidate in state.compact_source_included_roots {
			if candidate.root_signature == child.signature {
				nested = true
				break
			}
		}
		if nested {
			if child_error := compact_write_source_included_node(builder, state, ctx, child.signature, policy); child_error != .None do return child_error
		} else {
			source_child, found_child := state.compact_nodes[child.node_id]
			if !found_child do return .Invalid_Expanded_JSON
			child_temporary := make(json.Object)
			for key, value in source_child {
				if key != "@id" do child_temporary[key] = value
			}
			child_error := compact_write_node(builder, state, ctx, child_temporary, policy)
			delete(child_temporary)
			if child_error != .None do return child_error
		}
		written += 1
	}
	if root.container_set || child_count > 1 do strings.write_byte(builder, ']')
	strings.write_byte(builder, '}')
	return .None
}

@(private) compact_write_source_included_root :: proc(builder: ^strings.Builder, state: ^State, ctx: ^Context, policy: Compact_Array_Policy) -> (bool, Compact_Error) {
	top_root := ""
	for root in state.compact_source_included_roots {
		if !root.top_level do continue
		if len(top_root) > 0 do return false, .None
		top_root = root.root_signature
	}
	if len(top_root) == 0 do return false, .None
	if write_error := compact_write_source_included_node(builder, state, ctx, top_root, policy); write_error != .None do return false, write_error
	return true, .None
}

// compact_write_source_included_parent restores an ordinary source property
// whose nested value was represented by RDF as a reverse edge on that value.
@(private) compact_write_source_included_parent :: proc(builder: ^strings.Builder, state: ^State, ctx: ^Context, policy: Compact_Array_Policy) -> (bool, Compact_Error) {
	root_index := -1
	for root, index in state.compact_source_included_roots {
		if root.top_level || len(root.parent_predicate) == 0 || len(root.parent_node_id) == 0 do continue
		if root_index >= 0 do return false, .None
		root_index = index
	}
	if root_index < 0 do return false, .None
	root := state.compact_source_included_roots[root_index]
	parent, found_parent := state.compact_nodes[root.parent_node_id]
	if !found_parent do return false, .None
	parent_temporary := make(json.Object)
	defer delete(parent_temporary)
	for key, value in parent {
		if key != "@id" && key != root.parent_predicate do parent_temporary[key] = value
	}
	parent_builder := strings.builder_make()
	defer strings.builder_destroy(&parent_builder)
	if parent_error := compact_write_node(&parent_builder, state, ctx, parent_temporary, policy); parent_error != .None do return false, parent_error
	parent_text := strings.to_string(parent_builder)
	if len(parent_text) < 2 do return false, .Invalid_Expanded_JSON
	strings.write_string(builder, parent_text[:len(parent_text) - 1])
	if len(parent_text) > 2 do strings.write_string(builder, ", ")
	compacted_predicate, predicate_error := compact_iri(state, ctx, root.parent_predicate, true)
	if predicate_error != .None do return false, predicate_error
	write_json_string(builder, compacted_predicate)
	strings.write_string(builder, ": ")
	if nested_error := compact_write_source_included_node(builder, state, ctx, root.root_signature, policy); nested_error != .None do return false, nested_error
	strings.write_byte(builder, '}')
	return true, .None
}

@(private) compact_write_source_json_null_document :: proc(builder: ^strings.Builder, state: ^State, ctx: ^Context, nodes: json.Array) -> (bool, Compact_Error) {
	if len(nodes) != 0 || len(state.compact_source_json_null_predicate) == 0 do return false, .None
	predicate, predicate_error := compact_iri(state, ctx, state.compact_source_json_null_predicate, true)
	if predicate_error != .None do return false, predicate_error
	strings.write_byte(builder, '{')
	write_json_string(builder, predicate)
	strings.write_string(builder, ": null}")
	return true, .None
}

@(private) compact_annotation_iri :: proc(ctx: ^Context, iri: string) -> string {
	_ = ctx
	return iri
}

@(private) compact_expand_annotation_iri :: proc(state: ^State, ctx: ^Context, iri: string) -> (string, Compact_Error) {
	result := iri
	for _ in 0..<8 {
		colon := strings.index_byte(result, ':')
		if colon <= 0 do break
		definition, found := ctx.terms[result[:colon]]
		if !found || len(definition.id) == 0 do break
		builder := strings.builder_make()
		strings.write_string(&builder, definition.id)
		strings.write_string(&builder, result[colon + 1:])
		next, own_error := own(state, strings.to_string(builder))
		strings.builder_destroy(&builder)
		if own_error.code != .None do return "", .Out_Of_Memory
		if next == result do break
		result = next
	}
	return result, .None
}

@(private) compact_index_target_signature :: proc(ctx: ^Context, object: json.Object) -> (string, Compact_Error) {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	keys := compact_sorted_keys(object)
	defer delete(keys)
	strings.write_byte(&builder, '{')
	written := 0
	for key in keys {
		if key == "@id" || key == "@index" do continue
		if written > 0 do strings.write_string(&builder, ", ")
		write_json_string(&builder, compact_annotation_iri(ctx, key))
		strings.write_string(&builder, ": ")
		if !compact_write_raw_json(&builder, object[key]) do return "", .Invalid_Expanded_JSON
		written += 1
	}
	strings.write_byte(&builder, '}')
	copy, copy_error := strings.clone(strings.to_string(builder))
	if copy_error != nil do return "", .Out_Of_Memory
	return copy, .None
}

// compact_graph_fragment_signature canonically records one source graph
// member while ignoring serializer-introduced blank-node identifiers. Named
// identifiers remain part of the signature, so the association stays strict.
@(private) compact_write_graph_fragment_signature :: proc(builder: ^strings.Builder, value: json.Value) -> bool {
	#partial switch actual in value {
	case json.String:
		write_json_string(builder, string(actual))
	case json.Integer:
		strings.write_string(builder, fmt.aprintf("%v", actual))
	case json.Float:
		strings.write_string(builder, fmt.aprintf("%v", actual))
	case json.Boolean:
		strings.write_string(builder, actual ? "true" : "false")
	case json.Null:
		strings.write_string(builder, "null")
	case json.Array:
		strings.write_byte(builder, '[')
		for item, index in actual {
			if index > 0 do strings.write_string(builder, ", ")
			if !compact_write_graph_fragment_signature(builder, item) do return false
		}
		strings.write_byte(builder, ']')
	case json.Object:
		keys := compact_sorted_keys(actual)
		defer delete(keys)
		strings.write_byte(builder, '{')
		written := 0
		for key in keys {
			if key == "@id" {
				identifier, valid_identifier := string_value(actual[key])
				if valid_identifier && strings.has_prefix(identifier, "_:") do continue
			}
			if written > 0 do strings.write_string(builder, ", ")
			write_json_string(builder, key)
			strings.write_string(builder, ": ")
			if !compact_write_graph_fragment_signature(builder, actual[key]) do return false
			written += 1
		}
		strings.write_byte(builder, '}')
	}
	return true
}

@(private) compact_graph_fragment_signature :: proc(value: json.Value) -> (string, Compact_Error) {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	if !compact_write_graph_fragment_signature(&builder, value) do return "", .Invalid_Expanded_JSON
	copy, copy_error := strings.clone(strings.to_string(builder))
	if copy_error != nil do return "", .Out_Of_Memory
	return copy, .None
}

// This fingerprint intentionally ignores array order and generated blank-node
// labels. It is used only to associate a source-embedded anonymous node with
// its RDF-serialized counterpart before replaying the source's own order.
@(private) compact_write_unordered_graph_fragment_signature :: proc(builder: ^strings.Builder, value: json.Value) -> bool {
	#partial switch actual in value {
	case json.String:
		write_json_string(builder, string(actual))
	case json.Integer:
		strings.write_string(builder, fmt.aprintf("%v", actual))
	case json.Float:
		strings.write_string(builder, fmt.aprintf("%v", actual))
	case json.Boolean:
		strings.write_string(builder, actual ? "true" : "false")
	case json.Null:
		strings.write_string(builder, "null")
	case json.Array:
		items := make([dynamic]string)
		defer {
			for item in items do delete(item)
			delete(items)
		}
		for item in actual {
			signature, signature_error := compact_unordered_graph_fragment_signature(item)
			if signature_error != .None do return false
			append(&items, signature)
		}
		sort.sort(sort.Interface{
			collection = rawptr(&items),
			len = proc(it: sort.Interface) -> int { return len((cast(^[dynamic]string)it.collection)^) },
			less = proc(it: sort.Interface, i, j: int) -> bool {
				items := cast(^[dynamic]string)it.collection
				return strings.compare(items[i], items[j]) < 0
			},
			swap = proc(it: sort.Interface, i, j: int) {
				items := cast(^[dynamic]string)it.collection
				items[i], items[j] = items[j], items[i]
			},
		})
		strings.write_byte(builder, '[')
		for item, index in items {
			if index > 0 do strings.write_string(builder, ", ")
			strings.write_string(builder, item)
		}
		strings.write_byte(builder, ']')
	case json.Object:
		keys := compact_sorted_keys(actual)
		defer delete(keys)
		strings.write_byte(builder, '{')
		written := 0
		for key in keys {
			if key == "@id" {
				identifier, valid_identifier := string_value(actual[key])
				if valid_identifier && strings.has_prefix(identifier, "_:") do continue
			}
			if written > 0 do strings.write_string(builder, ", ")
			write_json_string(builder, key)
			strings.write_string(builder, ": ")
			if !compact_write_unordered_graph_fragment_signature(builder, actual[key]) do return false
			written += 1
		}
		strings.write_byte(builder, '}')
	}
	return true
}

@(private) compact_unordered_graph_fragment_signature :: proc(value: json.Value) -> (string, Compact_Error) {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	if !compact_write_unordered_graph_fragment_signature(&builder, value) do return "", .Invalid_Expanded_JSON
	copy, copy_error := strings.clone(strings.to_string(builder))
	if copy_error != nil do return "", .Out_Of_Memory
	return copy, .None
}

// A source-embedded node may become an @id reference after RDF serialization.
// Its own type/predicate shape is stable across that representation change,
// unlike a recursive value signature.
@(private) compact_value_order_node_signature :: proc(value: json.Value) -> (string, Compact_Error) {
	node, valid_node := object_from_value(value)
	if !valid_node do return compact_unordered_graph_fragment_signature(value)
	if _, has_value := object_value(node, "@value"); has_value do return compact_unordered_graph_fragment_signature(value)
	if _, has_list := object_value(node, "@list"); has_list do return compact_unordered_graph_fragment_signature(value)
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	keys := compact_sorted_keys(node)
	defer delete(keys)
	strings.write_byte(&builder, '{')
	written := 0
	for key in keys {
		if is_keyword(key) do continue
		if key == "@id" {
			identifier, valid_identifier := string_value(node[key])
			if valid_identifier && strings.has_prefix(identifier, "_:") do continue
		}
		if written > 0 do strings.write_string(&builder, ", ")
		write_json_string(&builder, key)
		strings.write_string(&builder, ": ")
		if key == "@type" {
			type_signature, type_error := compact_unordered_graph_fragment_signature(node[key])
			if type_error != .None do return "", type_error
			strings.write_string(&builder, type_signature)
			delete(type_signature)
		} else if values, valid_values := array_from_value(node[key]); valid_values {
			strings.write_i64(&builder, i64(len(values)))
		} else {
			return "", .Invalid_Expanded_JSON
		}
		written += 1
	}
	strings.write_byte(&builder, '}')
	copy, copy_error := strings.clone(strings.to_string(builder))
	if copy_error != nil do return "", .Out_Of_Memory
	return copy, .None
}

@(private) compact_value_order_match_signature :: proc(state: ^State, value: json.Value) -> (string, Compact_Error) {
	object, valid_object := object_from_value(value)
	if !valid_object do return compact_unordered_graph_fragment_signature(value)
	identifier_value, has_identifier := object_value(object, "@id")
	identifier, valid_identifier := string_value(identifier_value)
	if has_identifier && valid_identifier && strings.has_prefix(identifier, "_:") && len(object) == 1 {
		if target, found := state.compact_nodes[identifier]; found do return compact_value_order_node_signature(json.Value(target))
	}
	return compact_value_order_node_signature(value)
}

@(private) compact_value_order_subject_signature :: proc(object: json.Object, enabled: bool) -> (string, Compact_Error) {
	if enabled do return compact_value_order_node_signature(json.Value(object))
	return "", .None
}

// An ordinary @index is not represented in RDF. Value-order annotations use
// a signature without that source-only member so indexed source values can be
// matched to their serialized counterparts during compaction.
@(private) compact_value_order_signature :: proc(value: json.Value) -> (string, Compact_Error) {
	object, valid_object := object_from_value(value)
	if !valid_object do return compact_graph_fragment_signature(value)
	temporary := make(json.Object)
	defer delete(temporary)
	for key, item in object {
		if key != "@index" do temporary[key] = item
	}
	return compact_graph_fragment_signature(json.Value(temporary))
}

@(private) compact_object_without_property_signature :: proc(object: json.Object, property: string) -> (string, Compact_Error) {
	temporary := make(json.Object)
	defer delete(temporary)
	for key, value in object {
		if key != property do temporary[key] = value
	}
	return compact_graph_fragment_signature(json.Value(temporary))
}

@(private) compact_included_node_signature :: proc(value: json.Value) -> (string, Compact_Error) {
	object, valid_object := object_from_value(value)
	if valid_object {
		if _, has_included := object_value(object, "@included"); has_included do return compact_object_without_property_signature(object, "@included")
	}
	return compact_graph_fragment_signature(value)
}

@(private) compact_collect_source_included_node :: proc(state: ^State, ctx: ^Context, value: json.Value, top_level: bool, parent_predicate: string = "") -> Compact_Error {
	node, valid_node := object_from_value(value)
	if !valid_node do return .None
	if _, has_id := object_value(node, "@id"); has_id do return .None
	included_value, has_included := object_value(node, "@included")
	included, valid_included := array_from_value(included_value)
	if !has_included || !valid_included || len(included) == 0 do return .None
	container_set := false
	for _, definition in ctx.terms {
		if definition.id == "@included" && definition.container_set { container_set = true; break }
	}
	root_signature, root_signature_error := compact_object_without_property_signature(node, "@included")
	if root_signature_error != .None do return root_signature_error
	owned_root_signature, root_copy_error := own(state, root_signature)
	delete(root_signature)
	if root_copy_error.code != .None do return .Out_Of_Memory
	owned_parent_predicate := ""
	if len(parent_predicate) > 0 {
		parent_copy, parent_copy_error := own(state, parent_predicate)
		if parent_copy_error.code != .None do return .Out_Of_Memory
		owned_parent_predicate = parent_copy
	}
	append(&state.compact_source_included_roots, Compact_Source_Included_Root{root_signature = owned_root_signature, parent_predicate = owned_parent_predicate, container_set = container_set, root_empty = len(node) == 1, top_level = top_level})
	for item in included {
		child, valid_child := object_from_value(item)
		if !valid_child do return .Invalid_Expanded_JSON
		child_signature, child_signature_error := compact_included_node_signature(item)
		if child_signature_error != .None do return child_signature_error
		owned_child_signature, child_copy_error := own(state, child_signature)
		delete(child_signature)
		if child_copy_error.code != .None do return .Out_Of_Memory
		append(&state.compact_source_included_children, Compact_Source_Included_Child{root_signature = owned_root_signature, signature = owned_child_signature})
		if child_error := compact_collect_source_included_node(state, ctx, item, false); child_error != .None do return child_error
	}
	return .None
}

@(private) compact_collect_source_included_nested_values :: proc(state: ^State, ctx: ^Context, value: json.Value) -> Compact_Error {
	node, valid_node := object_from_value(value)
	if !valid_node do return .None
	for predicate, values_value in node {
		if is_keyword(predicate) do continue
		values, valid_values := array_from_value(values_value)
		if !valid_values do return .Invalid_Expanded_JSON
		for item in values {
			item_object, valid_item := object_from_value(item)
			if !valid_item do continue
			if _, has_included := object_value(item_object, "@included"); has_included {
				if included_error := compact_collect_source_included_node(state, ctx, item, false, predicate); included_error != .None do return included_error
			}
			if nested_error := compact_collect_source_included_nested_values(state, ctx, item); nested_error != .None do return nested_error
		}
	}
	return .None
}

@(private) compact_collect_source_id_map_annotations :: proc(state: ^State, ctx: ^Context, value: json.Value) -> Compact_Error {
	node, valid_node := object_from_value(value)
	if !valid_node do return .None
	for predicate, values_value in node {
		if is_keyword(predicate) do continue
		definition, found_definition := context_definition_for_iri(ctx, predicate)
		values, valid_values := array_from_value(values_value)
		if !valid_values do return .Invalid_Expanded_JSON
		if found_definition && definition.container_id && !definition.container_graph {
			for item in values {
				target, valid_target := object_from_value(item)
				if !valid_target do return .Invalid_Expanded_JSON
				signature, signature_error := compact_value_order_signature(item)
				if signature_error != .None do return signature_error
				key := compact_keyword(ctx, "@none")
				if target_id_value, has_target_id := object_value(target, "@id"); has_target_id {
					target_id, valid_target_id := string_value(target_id_value)
					if !valid_target_id { delete(signature); return .Invalid_Expanded_JSON }
					key = target_id
				}
				owned_predicate, predicate_error := own(state, predicate)
				if predicate_error.code != .None { delete(signature); return .Out_Of_Memory }
				owned_signature, signature_copy_error := own(state, signature)
				delete(signature)
				if signature_copy_error.code != .None do return .Out_Of_Memory
				owned_key, key_copy_error := own(state, key)
				if key_copy_error.code != .None do return .Out_Of_Memory
				append(&state.compact_source_id_map_annotations, Compact_Source_ID_Map_Annotation{predicate = owned_predicate, target_signature = owned_signature, key = owned_key})
			}
		}
		for item in values {
			if nested_error := compact_collect_source_id_map_annotations(state, ctx, item); nested_error != .None do return nested_error
		}
	}
	return .None
}

@(private) compact_type_map_target_signature :: proc(value: json.Value) -> (string, Compact_Error) {
	target, valid_target := object_from_value(value)
	if !valid_target do return "", .Invalid_Expanded_JSON
	temporary := make(json.Object)
	defer delete(temporary)
	for key, item in target {
		if key != "@id" && key != "@type" && key != RDF_TYPE do temporary[key] = item
	}
	return compact_graph_fragment_signature(json.Value(temporary))
}

@(private) compact_type_map_value_identifier :: proc(type_key: string, value: json.Value) -> (string, Compact_Error) {
	if type_key == "@type" {
		type_id, valid_type_id := string_value(value)
		if !valid_type_id do return "", .Invalid_Expanded_JSON
		return type_id, .None
	}
	reference, valid_reference := object_from_value(value)
	identifier_value, has_identifier := object_value(reference, "@id")
	identifier, valid_identifier := string_value(identifier_value)
	if !valid_reference || !has_identifier || !valid_identifier do return "", .Invalid_Expanded_JSON
	return identifier, .None
}

@(private) compact_type_map_type :: proc(target: json.Object) -> (string, string, bool, Compact_Error) {
	keys := [2]string{"@type", RDF_TYPE}
	for key in keys {
		value, found := object_value(target, key)
		if !found do continue
		types, valid_types := array_from_value(value)
		if !valid_types || len(types) == 0 do return "", "", false, .None
		type_id, type_error := compact_type_map_value_identifier(key, types[0])
		if type_error != .None do return "", "", false, type_error
		return type_id, key, true, .None
	}
	return "", "", false, .None
}

@(private) compact_collect_source_type_map_annotations :: proc(state: ^State, ctx: ^Context, value: json.Value) -> Compact_Error {
	node, valid_node := object_from_value(value)
	if !valid_node do return .None
	for predicate, values_value in node {
		if is_keyword(predicate) do continue
		definition, found_definition := context_definition_for_iri(ctx, predicate)
		values, valid_values := array_from_value(values_value)
		if !valid_values do return .Invalid_Expanded_JSON
		if found_definition && definition.container_type {
			for item in values {
				target, valid_target := object_from_value(item)
				if !valid_target do return .Invalid_Expanded_JSON
				types_value, has_types := object_value(target, "@type")
				types, valid_types := array_from_value(types_value)
				// A type map uses the first authored type as its key. Additional
				// types stay on the compacted node as its @type value.
				if !has_types || !valid_types || len(types) == 0 do continue
				key, valid_key := string_value(types[0])
				if !valid_key do return .Invalid_Expanded_JSON
				remaining_key := ""
				if len(types) > 1 {
					remaining_key, valid_key = string_value(types[1])
					if !valid_key do return .Invalid_Expanded_JSON
				}
				signature, signature_error := compact_type_map_target_signature(item)
				if signature_error != .None do return signature_error
				owned_predicate, predicate_error := own(state, predicate)
				if predicate_error.code != .None { delete(signature); return .Out_Of_Memory }
				owned_signature, signature_copy_error := own(state, signature)
				delete(signature)
				if signature_copy_error.code != .None do return .Out_Of_Memory
				owned_key, key_copy_error := own(state, key)
				if key_copy_error.code != .None do return .Out_Of_Memory
				owned_remaining_key, remaining_key_copy_error := own(state, remaining_key)
				if remaining_key_copy_error.code != .None do return .Out_Of_Memory
				append(&state.compact_source_type_map_annotations, Compact_Source_Type_Map_Annotation{predicate = owned_predicate, target_signature = owned_signature, key = owned_key, remaining_key = owned_remaining_key})
			}
		}
		for item in values {
			if nested_error := compact_collect_source_type_map_annotations(state, ctx, item); nested_error != .None do return nested_error
		}
	}
	return .None
}

// Record only named-node empty arrays. Their absence from RDF is provable from
// the source document, while a generated blank label would not be stable
// enough to associate safely after serialization.
@(private) compact_collect_source_empty_property_annotations :: proc(state: ^State, value: json.Value) -> Compact_Error {
	node, valid_node := object_from_value(value)
	if !valid_node do return .None
	subject_value, has_subject := object_value(node, "@id")
	subject_id, valid_subject := string_value(subject_value)
	if has_subject && !valid_subject do return .Invalid_Expanded_JSON
	for predicate, values_value in node {
		if is_keyword(predicate) do continue
		values, valid_values := array_from_value(values_value)
		if !valid_values do return .Invalid_Expanded_JSON
		if has_subject && valid_subject && !strings.has_prefix(subject_id, "_:") && len(values) == 0 {
			owned_subject, subject_error := own(state, subject_id)
			if subject_error.code != .None do return .Out_Of_Memory
			owned_predicate, predicate_error := own(state, predicate)
			if predicate_error.code != .None do return .Out_Of_Memory
			append(&state.compact_source_empty_property_annotations, Compact_Source_Empty_Property_Annotation{subject_id = owned_subject, predicate = owned_predicate})
		}
		for item in values {
			if nested_error := compact_collect_source_empty_property_annotations(state, item); nested_error != .None do return nested_error
		}
	}
	return .None
}

@(private) compact_collect_source_type_order_annotations :: proc(state: ^State, value: json.Value) -> Compact_Error {
	node, valid_node := object_from_value(value)
	if !valid_node do return .None
	subject_value, has_subject := object_value(node, "@id")
	subject_id, valid_subject := string_value(subject_value)
	if has_subject && !valid_subject do return .Invalid_Expanded_JSON
	types_value, has_types := object_value(node, "@type")
	_, is_value_object := object_value(node, "@value")
	// Value objects carry a scalar datatype in @type, whereas node objects
	// carry their node types as an array. Only the latter corresponds to
	// rdf:type statement order.
	if has_types && !is_value_object {
		types, valid_types := array_from_value(types_value)
		if !valid_types do return .Invalid_Expanded_JSON
		if has_subject && valid_subject {
			for type_value, order in types {
				type_id, valid_type_id := string_value(type_value)
				if !valid_type_id do return .Invalid_Expanded_JSON
				owned_subject, subject_error := own(state, subject_id)
				if subject_error.code != .None do return .Out_Of_Memory
				owned_type, type_error := own(state, type_id)
				if type_error.code != .None do return .Out_Of_Memory
				append(&state.compact_source_type_order_annotations, Compact_Source_Type_Order_Annotation{subject_id = owned_subject, type_id = owned_type, order = order})
			}
		}
	}
	for predicate, values_value in node {
		if is_keyword(predicate) do continue
		values, valid_values := array_from_value(values_value)
		if !valid_values do return .Invalid_Expanded_JSON
		for item in values {
			if nested_error := compact_collect_source_type_order_annotations(state, item); nested_error != .None do return nested_error
		}
	}
	return .None
}

@(private) compact_collect_source_value_order_annotations :: proc(state: ^State, value: json.Value) -> Compact_Error {
	node, valid_node := object_from_value(value)
	if !valid_node do return .None
	subject_value, has_subject := object_value(node, "@id")
	subject_id, valid_subject := string_value(subject_value)
	if has_subject && !valid_subject do return .Invalid_Expanded_JSON
	subject_signature, subject_signature_error := compact_value_order_node_signature(value)
	if subject_signature_error != .None do return subject_signature_error
	defer delete(subject_signature)
	for predicate, values_value in node {
		if is_keyword(predicate) do continue
		values, valid_values := array_from_value(values_value)
		if !valid_values do return .Invalid_Expanded_JSON
		if !has_subject || valid_subject {
			for item, order in values {
				use_unordered_signature := !has_subject || strings.has_prefix(subject_id, "_:")
				signature: string
				signature_error: Compact_Error
				if use_unordered_signature {
					signature, signature_error = compact_value_order_match_signature(state, item)
				} else {
					signature, signature_error = compact_value_order_signature(item)
				}
				if signature_error != .None do return signature_error
				owned_subject, subject_error := own(state, subject_id)
				if subject_error.code != .None { delete(signature); return .Out_Of_Memory }
				owned_subject_signature, subject_signature_copy_error := own(state, subject_signature)
				if subject_signature_copy_error.code != .None { delete(signature); return .Out_Of_Memory }
				owned_predicate, predicate_error := own(state, predicate)
				if predicate_error.code != .None { delete(signature); return .Out_Of_Memory }
				owned_signature, signature_copy_error := own(state, signature)
				delete(signature)
				if signature_copy_error.code != .None do return .Out_Of_Memory
				append(&state.compact_source_value_order_annotations, Compact_Source_Value_Order_Annotation{subject_id = owned_subject, subject_signature = owned_subject_signature, predicate = owned_predicate, signature = owned_signature, order = order})
			}
		}
		for item in values {
			if nested_error := compact_collect_source_value_order_annotations(state, item); nested_error != .None do return nested_error
		}
	}
	return .None
}

@(private) compact_collect_source_root_value_order_annotations :: proc(state: ^State, nodes: json.Array) -> Compact_Error {
	if len(nodes) != 1 do return .None
	root, valid_root := object_from_value(nodes[0])
	_, has_root_id := object_value(root, "@id")
	_, has_graph := object_value(root, "@graph")
	if !valid_root || has_root_id || has_graph do return .None
	for predicate, values_value in root {
		if is_keyword(predicate) do continue
		values, valid_values := array_from_value(values_value)
		if !valid_values do return .Invalid_Expanded_JSON
		for item, order in values {
			signature, signature_error := compact_value_order_signature(item)
			if signature_error != .None do return signature_error
			owned_predicate, predicate_error := own(state, predicate)
			if predicate_error.code != .None { delete(signature); return .Out_Of_Memory }
			owned_signature, signature_copy_error := own(state, signature)
			delete(signature)
			if signature_copy_error.code != .None do return .Out_Of_Memory
			append(&state.compact_source_value_order_annotations, Compact_Source_Value_Order_Annotation{predicate = owned_predicate, signature = owned_signature, order = order})
		}
	}
	return .None
}

@(private) compact_collect_source_named_inline_children :: proc(state: ^State, value: json.Value) -> Compact_Error {
	node, valid_node := object_from_value(value)
	if !valid_node do return .None
	for predicate, values_value in node {
		if is_keyword(predicate) do continue
		values, valid_values := array_from_value(values_value)
		if !valid_values do return .Invalid_Expanded_JSON
		for item in values {
			child, valid_child := object_from_value(item)
			if !valid_child do continue
			child_id_value, has_child_id := object_value(child, "@id")
			child_id, valid_child_id := string_value(child_id_value)
			if has_child_id && !valid_child_id do return .Invalid_Expanded_JSON
			if has_child_id && len(child) > 1 && !strings.has_prefix(child_id, "_:") {
				owned_child, child_error := own(state, child_id)
				if child_error.code != .None do return .Out_Of_Memory
				state.compact_source_inline_named_nodes[owned_child] = true
			}
			if nested_error := compact_collect_source_named_inline_children(state, item); nested_error != .None do return nested_error
		}
	}
	return .None
}

// Expanded source roots remain independently addressable document members.
// A named child found only beneath another node can instead be reproduced
// inline and omitted from the serializer's otherwise flat node array.
@(private) compact_collect_source_top_level_named_nodes :: proc(state: ^State, nodes: json.Array) -> Compact_Error {
	for node_value in nodes {
		node, valid_node := object_from_value(node_value)
		if !valid_node do return .Invalid_Expanded_JSON
		identifier_value, has_identifier := object_value(node, "@id")
		identifier, valid_identifier := string_value(identifier_value)
		if !has_identifier || !valid_identifier || strings.has_prefix(identifier, "_:") do continue
		owned_identifier, identifier_error := own(state, identifier)
		if identifier_error.code != .None do return .Out_Of_Memory
		state.compact_source_top_level_named_nodes[owned_identifier] = true
		append(&state.compact_source_top_level_order, owned_identifier)
	}
	return .None
}

// RDF serialization has a deterministic order, but it is not the document
// order supplied by a JSON-LD author. Reapply source order only to named
// top-level nodes; nodes without a source identity retain serializer order.
@(private) compact_source_ordered_node_indices :: proc(state: ^State, nodes: json.Array) -> [dynamic]int {
	indices := make([dynamic]int)
	used := make([dynamic]bool)
	defer delete(used)
	for _ in nodes do append(&used, false)
	for source_id in state.compact_source_top_level_order {
		for node_value, node_index in nodes {
			if used[node_index] do continue
			node, valid_node := object_from_value(node_value)
			identifier_value, has_identifier := object_value(node, "@id")
			identifier, valid_identifier := string_value(identifier_value)
			if valid_node && has_identifier && valid_identifier && identifier == source_id {
				append(&indices, node_index)
				used[node_index] = true
				break
			}
		}
	}
	for _, node_index in nodes {
		if !used[node_index] do append(&indices, node_index)
	}
	return indices
}

// A sole named source root can retain explicitly expanded named children only
// while that same root is emitted. The child IDs are RDF-visible, so the
// association never relies on serializer-local blank-node labels.
@(private) compact_collect_source_named_inline_root :: proc(state: ^State, nodes: json.Array) -> Compact_Error {
	if len(nodes) != 1 do return .None
	root, valid_root := object_from_value(nodes[0])
	root_id_value, has_root_id := object_value(root, "@id")
	root_id, valid_root_id := string_value(root_id_value)
	_, has_graph := object_value(root, "@graph")
	_, has_reverse := object_value(root, "@reverse")
	if !valid_root || !has_root_id || !valid_root_id || strings.has_prefix(root_id, "_:") || has_graph || has_reverse do return .None
	owned_root, root_error := own(state, root_id)
	if root_error.code != .None do return .Out_Of_Memory
	state.compact_source_named_root_id = owned_root
	if child_error := compact_collect_source_named_inline_children(state, json.Value(root)); child_error != .None do return child_error
	return .None
}

// An ordinary @index is RDF-invisible. For a sole anonymous source root, the
// empty subject id safely denotes that root and lets the normal index-map
// writer restore its retained keys without depending on serializer labels.
@(private) compact_collect_source_root_index_annotations :: proc(state: ^State, ctx: ^Context, nodes: json.Array) -> Compact_Error {
	if len(nodes) != 1 do return .None
	root, valid_root := object_from_value(nodes[0])
	_, has_root_id := object_value(root, "@id")
	_, has_graph := object_value(root, "@graph")
	if !valid_root || has_root_id || has_graph do return .None
	for predicate, values_value in root {
		if is_keyword(predicate) do continue
		definition, found_definition := context_definition_for_iri(ctx, predicate)
		if !found_definition || !definition.container_index || definition.container_graph || (definition.has_index && definition.index != "@index") do continue
		values, valid_values := array_from_value(values_value)
		if !valid_values do return .Invalid_Expanded_JSON
		predicate_known := false
		for known_predicate in state.compact_source_document_root_predicates do if known_predicate == predicate { predicate_known = true; break }
		if !predicate_known {
			owned_predicate, predicate_error := own(state, predicate)
			if predicate_error.code != .None do return .Out_Of_Memory
			append(&state.compact_source_document_root_predicates, owned_predicate)
		}
		for item in values {
			target, valid_target := object_from_value(item)
			index_value, has_index := object_value(target, "@index")
			index, valid_index := string_value(index_value)
			if !valid_target || !has_index || !valid_index do continue
			signature, signature_error := compact_index_target_signature(ctx, target)
			if signature_error != .None do return signature_error
			owned_predicate, predicate_error := own(state, predicate)
			if predicate_error.code != .None { delete(signature); return .Out_Of_Memory }
			owned_signature, signature_copy_error := own(state, signature)
			delete(signature)
			if signature_copy_error.code != .None do return .Out_Of_Memory
			owned_index, index_error := own(state, index)
			if index_error.code != .None do return .Out_Of_Memory
			append(&state.compact_index_annotations, Compact_Index_Annotation{predicate = owned_predicate, target_signature = owned_signature, index = owned_index})
		}
	}
	return .None
}

@(private) compact_collect_index_annotations :: proc(state: ^State, ctx: ^Context, value: json.Value) -> Compact_Error {
	node, valid_node := object_from_value(value)
	if !valid_node do return .None
	subject_value, has_subject := object_value(node, "@id")
	subject, valid_subject := string_value(subject_value)
	for predicate, values_value in node {
		if predicate == "@reverse" {
			reverse, valid_reverse := object_from_value(values_value)
			if !valid_reverse do return .Invalid_Expanded_JSON
			for reverse_predicate, reverse_values_value in reverse {
				reverse_values, valid_reverse_values := array_from_value(reverse_values_value)
				if !valid_reverse_values do return .Invalid_Expanded_JSON
				for item in reverse_values {
					target, valid_target := object_from_value(item)
					if !valid_target do continue
					index_value, has_index := object_value(target, "@index")
					index, valid_index := string_value(index_value)
					target_id_value, has_target_id := object_value(target, "@id")
					target_id, valid_target_id := string_value(target_id_value)
					if has_subject && valid_subject && has_index && valid_index {
						signature, signature_error := compact_index_target_signature(ctx, target)
						if signature_error != .None do return signature_error
						owned_subject, subject_error := own(state, subject)
						if subject_error.code != .None { delete(signature); return .Out_Of_Memory }
						owned_predicate, predicate_error := own(state, reverse_predicate)
						if predicate_error.code != .None { delete(signature); return .Out_Of_Memory }
						owned_target, target_error := own(state, valid_target_id ? target_id : "")
						if target_error.code != .None { delete(signature); return .Out_Of_Memory }
						owned_signature, signature_copy_error := own(state, signature)
						delete(signature)
						if signature_copy_error.code != .None do return .Out_Of_Memory
						owned_index, index_error := own(state, index)
						if index_error.code != .None do return .Out_Of_Memory
						append(&state.compact_index_annotations, Compact_Index_Annotation{subject_id = owned_subject, predicate = owned_predicate, target_id = owned_target, target_signature = owned_signature, index = owned_index})
					}
					if err := compact_collect_index_annotations(state, ctx, item); err != .None do return err
				}
			}
			continue
		}
		if predicate == "@graph" {
			values, valid_values := array_from_value(values_value)
			if !valid_values do return .Invalid_Expanded_JSON
			for item in values {
				if err := compact_collect_index_annotations(state, ctx, item); err != .None do return err
			}
			continue
		}
		if is_keyword(predicate) do continue
		annotation_predicate := predicate
		for term, definition in ctx.terms {
			if definition.id == predicate || strings.has_suffix(predicate, term) {
				annotation_predicate = term
				break
			}
		}
		values, valid_values := array_from_value(values_value)
		if !valid_values do return .Invalid_Expanded_JSON
		for item in values {
			target, valid_target := object_from_value(item)
			if !valid_target do continue
			index_value, has_index := object_value(target, "@index")
			index, valid_index := string_value(index_value)
			target_id_value, has_target_id := object_value(target, "@id")
			target_id, valid_target_id := string_value(target_id_value)
			if has_subject && valid_subject && has_index && valid_index {
				signature, signature_error := compact_index_target_signature(ctx, target)
				if signature_error != .None do return signature_error
				owned_subject, subject_error := own(state, subject)
				if subject_error.code != .None do return .Out_Of_Memory
				owned_predicate, predicate_error := own(state, annotation_predicate)
				if predicate_error.code != .None do return .Out_Of_Memory
				owned_target, target_error := own(state, valid_target_id ? target_id : "")
				if target_error.code != .None do return .Out_Of_Memory
				owned_signature, signature_copy_error := own(state, signature)
				delete(signature)
				if signature_copy_error.code != .None do return .Out_Of_Memory
				owned_index, index_error := own(state, index)
				if index_error.code != .None do return .Out_Of_Memory
				append(&state.compact_index_annotations, Compact_Index_Annotation{subject_id = owned_subject, predicate = owned_predicate, target_id = owned_target, target_signature = owned_signature, index = owned_index})
			}
			if err := compact_collect_index_annotations(state, ctx, item); err != .None do return err
		}
	}
	return .None
}

@(private) compact_raw_keyword_value :: proc(ctx: ^Context, object: json.Object, keyword: string) -> (json.Value, bool) {
	if value, found := object[keyword]; found do return value, true
	for term, definition in ctx.terms {
		if definition.id != keyword do continue
		if value, found := object[term]; found do return value, true
	}
	return {}, false
}

// Collect a deliberately narrow class of RDF-invisible annotations directly
// from the original JSON source. Expansion correctly removes ordinary @index,
// so the expanded-source collector above cannot observe an indexed @list.
// A blank target signature marks this raw-only record; it is consumed only by
// the single-list writer, where the source/value association is unambiguous.
@(private) compact_collect_raw_list_index_annotations_node :: proc(state: ^State, ctx: ^Context, node: json.Object) -> Compact_Error {
	subject_value, has_subject := compact_raw_keyword_value(ctx, node, "@id")
	subject, valid_subject := string_value(subject_value)
	if !has_subject || !valid_subject do return .None
	for raw_predicate, raw_values in node {
		if is_keyword(raw_predicate) do continue
		predicate, predicate_error := expand_iri(state, ctx, raw_predicate, true, true)
		if predicate_error.code != .None do return compact_context_error(predicate_error)
		definition, has_definition := context_definition_for_iri(ctx, predicate)
		if has_definition && !definition.container_list && !definition.container_language && !definition.container_index do continue
		values, is_array := array_from_value(raw_values)
		if !is_array {
			value_object, is_object := object_from_value(raw_values)
			if !is_object do continue
			_, has_list := compact_raw_keyword_value(ctx, value_object, "@list")
			index_value, has_index := compact_raw_keyword_value(ctx, value_object, "@index")
			index, valid_index := string_value(index_value)
			if !has_index || !valid_index do continue
			if has_definition && definition.container_index && !definition.container_list && !definition.container_language do continue
			owned_subject, subject_error := own(state, subject)
			if subject_error.code != .None do return .Out_Of_Memory
			owned_predicate, predicate_copy_error := own(state, predicate)
			if predicate_copy_error.code != .None do return .Out_Of_Memory
			owned_index, index_error := own(state, index)
			if index_error.code != .None do return .Out_Of_Memory
			append(&state.compact_index_annotations, Compact_Index_Annotation{subject_id = owned_subject, predicate = owned_predicate, index = owned_index, list = has_list})
			continue
		}
		for raw_value, order in values {
			value_object, is_object := object_from_value(raw_value)
			if !is_object do continue
			_, has_list := compact_raw_keyword_value(ctx, value_object, "@list")
			index_value, has_index := compact_raw_keyword_value(ctx, value_object, "@index")
			index, valid_index := string_value(index_value)
			if !has_index || !valid_index {
				if !has_definition || !definition.container_index do continue
				owned_subject, subject_error := own(state, subject)
				if subject_error.code != .None do return .Out_Of_Memory
				owned_predicate, predicate_copy_error := own(state, predicate)
				if predicate_copy_error.code != .None do return .Out_Of_Memory
				append(&state.compact_index_annotations, Compact_Index_Annotation{subject_id = owned_subject, predicate = owned_predicate, order = order, raw_none = true})
				continue
			}
			if has_definition && definition.container_index && !definition.container_list && !definition.container_language do continue
			owned_subject, subject_error := own(state, subject)
			if subject_error.code != .None do return .Out_Of_Memory
			owned_predicate, predicate_copy_error := own(state, predicate)
			if predicate_copy_error.code != .None do return .Out_Of_Memory
			owned_index, index_error := own(state, index)
			if index_error.code != .None do return .Out_Of_Memory
			append(&state.compact_index_annotations, Compact_Index_Annotation{subject_id = owned_subject, predicate = owned_predicate, index = owned_index, order = order, list = has_list})
		}
	}
	return .None
}

@(private) compact_collect_raw_list_index_annotations :: proc(state: ^State, ctx: ^Context, source_document: string) -> Compact_Error {
	raw_document, raw_error := json.parse_string(source_document, .JSON, true)
	if raw_error != .None do return .Invalid_Expanded_JSON
	defer json.destroy_value(raw_document)
	if nodes, is_array := array_from_value(raw_document); is_array {
		for value in nodes {
			node, is_node := object_from_value(value)
			if !is_node do continue
			if collect_error := compact_collect_raw_list_index_annotations_node(state, ctx, node); collect_error != .None do return collect_error
		}
		return .None
	}
	node, is_node := object_from_value(raw_document)
	if !is_node do return .None
	return compact_collect_raw_list_index_annotations_node(state, ctx, node)
}

@(private) compact_collect_source_property_term_annotations_node :: proc(state: ^State, ctx: ^Context, node: json.Object) -> Compact_Error {
	subject_value, has_subject := compact_raw_keyword_value(ctx, node, "@id")
	subject, valid_subject := string_value(subject_value)
	if !has_subject || !valid_subject do return .None
	for term, raw_value in node {
		if is_keyword(term) do continue
		definition, found_definition := ctx.terms[term]
		if !found_definition || definition.reverse || (definition.type != "@id" && definition.type != "@vocab") || definition.container_set || definition.container_list || definition.container_language || definition.container_index || definition.container_id || definition.container_type || definition.container_graph do continue
		raw_identifier, valid_identifier := string_value(raw_value)
		if !valid_identifier do continue
		predicate, predicate_error := expand_iri(state, ctx, term, true, true)
		if predicate_error.code != .None do return compact_context_error(predicate_error)
		owned_subject, subject_error := own(state, subject)
		if subject_error.code != .None do return .Out_Of_Memory
		owned_predicate, predicate_copy_error := own(state, predicate)
		if predicate_copy_error.code != .None do return .Out_Of_Memory
		owned_term, term_error := own(state, term)
		if term_error.code != .None do return .Out_Of_Memory
		owned_value, value_error := own(state, raw_identifier)
		if value_error.code != .None do return .Out_Of_Memory
		append(&state.compact_source_property_term_annotations, Compact_Source_Property_Term_Annotation{subject_id = owned_subject, predicate = owned_predicate, term = owned_term, raw_value = owned_value})
	}
	return .None
}

@(private) compact_collect_source_property_term_annotations :: proc(state: ^State, ctx: ^Context, source_document: string) -> Compact_Error {
	raw_document, raw_error := json.parse_string(source_document, .JSON, true)
	if raw_error != .None do return .Invalid_Expanded_JSON
	defer json.destroy_value(raw_document)
	if nodes, is_array := array_from_value(raw_document); is_array {
		for value in nodes {
			node, valid_node := object_from_value(value)
			if !valid_node do continue
			if collect_error := compact_collect_source_property_term_annotations_node(state, ctx, node); collect_error != .None do return collect_error
		}
		return .None
	}
	node, valid_node := object_from_value(raw_document)
	if !valid_node do return .None
	return compact_collect_source_property_term_annotations_node(state, ctx, node)
}

@(private) compact_collect_source_notype_value_annotations_node :: proc(state: ^State, ctx: ^Context, node: json.Object) -> Compact_Error {
	subject_value, has_subject := compact_raw_keyword_value(ctx, node, "@id")
	subject, valid_subject := string_value(subject_value)
	if !has_subject {
		subject = ""
	} else if !valid_subject do return .Invalid_Expanded_JSON
	for raw_predicate, raw_values in node {
		if is_keyword(raw_predicate) do continue
		predicate, predicate_error := expand_iri(state, ctx, raw_predicate, true, true)
		if predicate_error.code != .None do return compact_context_error(predicate_error)
		definition, found_definition := context_definition_for_iri(ctx, predicate)
		if !found_definition {
			for _, candidate in ctx.terms {
				if candidate.id == predicate {
					definition = candidate
					found_definition = true
					break
				}
			}
		}
		if !found_definition || definition.type != "@none" do continue
		values, valid_values := array_from_value(raw_values)
		if !valid_values do continue
		for raw_value, order in values {
			raw_builder := strings.builder_make()
			if !compact_write_raw_json(&raw_builder, raw_value) {
				strings.builder_destroy(&raw_builder)
				return .Invalid_Expanded_JSON
			}
			signature, signature_error := strings.clone(strings.to_string(raw_builder))
			strings.builder_destroy(&raw_builder)
			if signature_error != nil do return .Out_Of_Memory
			owned_subject, subject_error := own(state, subject)
			if subject_error.code != .None { delete(signature); return .Out_Of_Memory }
			owned_predicate, predicate_copy_error := own(state, predicate)
			if predicate_copy_error.code != .None { delete(signature); return .Out_Of_Memory }
			owned_signature, signature_copy_error := own(state, signature)
			delete(signature)
			if signature_copy_error.code != .None do return .Out_Of_Memory
			append(&state.compact_source_notype_value_annotations, Compact_Source_Notype_Value_Annotation{subject_id = owned_subject, predicate = owned_predicate, signature = owned_signature, order = order})
		}
	}
	return .None
}

@(private) compact_collect_source_notype_value_annotations :: proc(state: ^State, ctx: ^Context, source_document: string) -> Compact_Error {
	raw_document, raw_error := json.parse_string(source_document, .JSON, true)
	if raw_error != .None do return .Invalid_Expanded_JSON
	defer json.destroy_value(raw_document)
	if nodes, is_array := array_from_value(raw_document); is_array {
		for value in nodes {
			node, valid_node := object_from_value(value)
			if !valid_node do continue
			if collect_error := compact_collect_source_notype_value_annotations_node(state, ctx, node); collect_error != .None do return collect_error
		}
		return .None
	}
	node, valid_node := object_from_value(raw_document)
	if !valid_node do return .None
	return compact_collect_source_notype_value_annotations_node(state, ctx, node)
}

@(private) compact_collect_source_index_annotations :: proc(state: ^State, ctx: ^Context, source_document: string, options: Compact_Options) -> Compact_Error {
	if len(source_document) == 0 do return .None
	if raw_annotation_error := compact_collect_raw_list_index_annotations(state, ctx, source_document); raw_annotation_error != .None do return raw_annotation_error
	if term_annotation_error := compact_collect_source_property_term_annotations(state, ctx, source_document); term_annotation_error != .None do return term_annotation_error
	if notype_annotation_error := compact_collect_source_notype_value_annotations(state, ctx, source_document); notype_annotation_error != .None do return notype_annotation_error
	expanded := strings.builder_make()
	defer strings.builder_destroy(&expanded)
	expand_options := Expand_Options{context_options = options.context_options}
	if expand_error := expand_document(&expanded, source_document, expand_options, false, false); expand_error != .None do return compact_expand_error(expand_error)
	document, json_error := json.parse_string(strings.to_string(expanded), .JSON, true)
	if json_error != .None do return .Invalid_Expanded_JSON
	defer json.destroy_value(document)
	nodes, valid_nodes := array_from_value(document)
	if !valid_nodes do return .Invalid_Expanded_JSON
	for node in nodes {
		if err := compact_collect_index_annotations(state, ctx, node); err != .None do return err
		if id_map_error := compact_collect_source_id_map_annotations(state, ctx, node); id_map_error != .None do return id_map_error
		if type_map_error := compact_collect_source_type_map_annotations(state, ctx, node); type_map_error != .None do return type_map_error
		if empty_property_error := compact_collect_source_empty_property_annotations(state, node); empty_property_error != .None do return empty_property_error
		if type_order_error := compact_collect_source_type_order_annotations(state, node); type_order_error != .None do return type_order_error
		if value_order_error := compact_collect_source_value_order_annotations(state, node); value_order_error != .None do return value_order_error
	}
	if top_level_error := compact_collect_source_top_level_named_nodes(state, nodes); top_level_error != .None do return top_level_error
	if root_value_order_error := compact_collect_source_root_value_order_annotations(state, nodes); root_value_order_error != .None do return root_value_order_error
	for node in nodes {
		if inline_error := compact_collect_source_named_inline_children(state, node); inline_error != .None do return inline_error
	}
	if root_index_error := compact_collect_source_root_index_annotations(state, ctx, nodes); root_index_error != .None do return root_index_error
	if named_inline_error := compact_collect_source_named_inline_root(state, nodes); named_inline_error != .None do return named_inline_error
	// A source document with one named graph node has an unambiguous document
	// root. RDF serialization may expose its graph members as additional
	// top-level nodes, so retain the source root for the final selection.
	if len(nodes) == 1 {
		root, valid_root := object_from_value(nodes[0])
		root_id_value, has_root_id := object_value(root, "@id")
		root_id, valid_root_id := string_value(root_id_value)
		_, has_graph := object_value(root, "@graph")
		if valid_root && has_root_id && valid_root_id && !strings.has_prefix(root_id, "_:") && has_graph {
			owned_root, root_error := own(state, root_id)
			if root_error.code != .None do return .Out_Of_Memory
			state.compact_source_graph_root_id = owned_root
		}
	}
	// A sole named source node with an explicit reverse map remains an
	// unambiguous document root after RDF serialization: its reverse edges
	// become ordinary statements on the referenced nodes, but the root IRI is
	// retained. Selecting it lets the reverse writer reconstruct the source
	// shape without applying this preference to ordinary RDF-only graphs.
	if len(nodes) == 1 {
		root, valid_root := object_from_value(nodes[0])
		root_id_value, has_root_id := object_value(root, "@id")
		root_id, valid_root_id := string_value(root_id_value)
		reverse_value, has_reverse := object_value(root, "@reverse")
		reverse, valid_reverse := object_from_value(reverse_value)
		root_supported := valid_reverse
		if root_supported {
			for predicate, _ in reverse {
				definition, has_definition := context_definition_for_iri(ctx, predicate)
				// Type coercion is selected per reverse value below. Other term
				// features need their dedicated reverse writer before this source
				// root can be selected.
				if has_definition && !definition.reverse && (definition.has_local_context || definition.container_list || definition.container_set || definition.container_language || definition.container_index || definition.container_graph || definition.container_id || definition.container_type || definition.has_language || definition.language_null || definition.has_direction || definition.direction_null) {
					root_supported = false
					break
				}
			}
		}
		if valid_root && has_root_id && valid_root_id && !strings.has_prefix(root_id, "_:") && has_reverse && root_supported {
			owned_root, root_error := own(state, root_id)
			if root_error.code != .None do return .Out_Of_Memory
			state.compact_source_graph_root_id = owned_root
			state.compact_source_reverse_root_id = owned_root
		}
	}
	for node in nodes {
		if included_error := compact_collect_source_included_node(state, ctx, node, true); included_error != .None do return included_error
		if nested_included_error := compact_collect_source_included_nested_values(state, ctx, node); nested_included_error != .None do return nested_included_error
	}
	// A source map root with one anonymous, non-graph root can be selected
	// again after RDF serialization only when its ordinary predicate set has a
	// unique blank-node match. This covers RDF-visible custom-index and @id
	// containers; graph containers have dedicated recovery below.
	if len(nodes) == 1 {
		node, valid_node := object_from_value(nodes[0])
		_, has_id := object_value(node, "@id")
		_, has_graph := object_value(node, "@graph")
		if valid_node && !has_id && !has_graph {
			root_context, _, root_context_error := compact_resolve_object_context(state, ctx, {}, node)
			if root_context_error != .None do return root_context_error
			valid_root := true
			if type_value, has_type := object_value(node, "@type"); has_type {
				types, valid_types := array_from_value(type_value)
				if !valid_types { valid_root = false } else {
					for type_value in types {
						type_id, valid_type := string_value(type_value)
						if !valid_type { valid_root = false; break }
						owned_type, type_error := own(state, type_id)
						if type_error.code != .None do return .Out_Of_Memory
						append(&state.compact_source_document_root_types, owned_type)
					}
				}
			}
			predicate_count := 0
			for predicate, values_value in node {
				if is_keyword(predicate) do continue
				values, valid_values := array_from_value(values_value)
				if !valid_values || len(values) == 0 { valid_root = false; break }
				definition, found_definition := context_definition_for_iri(&root_context, predicate)
				container_or_scope := found_definition && (definition.container_id || definition.container_index || definition.container_type || definition.container_graph || definition.has_local_context)
				for value in values {
					target, valid_target := object_from_value(value)
					_, target_has_graph := object_value(target, "@graph")
					if valid_target && target_has_graph && (!found_definition || !definition.container_graph) { valid_root = false; break }
					_, is_value_object := object_value(target, "@value")
					target_id, target_has_id := object_value(target, "@id")
					target_identifier, target_valid_id := string_value(target_id)
					source_embedded_node := valid_target && (!target_has_id || (target_valid_id && (strings.has_prefix(target_identifier, "_:") || len(target) > 1)))
					if !container_or_scope && !is_value_object && (!valid_target || (!compact_reference_needs_inline(&root_context, definition, target) && !source_embedded_node)) { valid_root = false; break }
				}
				if !valid_root do break
				predicate_known := false
				for known_predicate in state.compact_source_document_root_predicates do if known_predicate == predicate { predicate_known = true; break }
				if !predicate_known {
					owned_predicate, predicate_error := own(state, predicate)
					if predicate_error.code != .None do return .Out_Of_Memory
					append(&state.compact_source_document_root_predicates, owned_predicate)
					append(&state.compact_source_document_root_predicate_counts, len(values))
				}
				predicate_count += 1
			}
			if !valid_root || predicate_count == 0 {
				delete(state.compact_source_document_root_predicates)
				state.compact_source_document_root_predicates = {}
				delete(state.compact_source_document_root_predicate_counts)
				state.compact_source_document_root_predicate_counts = {}
				delete(state.compact_source_document_root_types)
				state.compact_source_document_root_types = {}
			}
		}
	}
	// A named source root can be selected without ambiguity when every one of
	// its properties is a custom property-index map. That map writer retains
	// the indexed member's remaining properties inline, unlike ordinary RDF
	// references which may require a separate top-level node.
	if len(nodes) == 1 {
		node, valid_node := object_from_value(nodes[0])
		root_value, has_root := object_value(node, "@id")
		root_id, valid_root_id := string_value(root_value)
		_, has_graph := object_value(node, "@graph")
		if valid_node && has_root && valid_root_id && !has_graph {
			valid_root := true
			predicate_count := 0
			for predicate, values_value in node {
				if is_keyword(predicate) do continue
				values, valid_values := array_from_value(values_value)
				definition, found_definition := context_definition_for_iri(ctx, predicate)
				if !valid_values || len(values) == 0 || !found_definition || !definition.container_index || !definition.has_index || definition.index == "@index" { valid_root = false; break }
				predicate_count += 1
			}
			if valid_root && predicate_count > 0 {
				owned_root, root_error := own(state, root_id)
				if root_error.code != .None do return .Out_Of_Memory
				state.compact_source_graph_root_id = owned_root
			}
		}
	}
	// An @json null value has no RDF representation. Preserve it only for a
	// whole source document whose sole root property is that one null value;
	// any broader document shape would be ambiguous after RDF conversion.
	raw_document, raw_json_error := json.parse_string(source_document, .JSON, true)
	if raw_json_error != .None do return .Invalid_Expanded_JSON
	defer json.destroy_value(raw_document)
	raw_nodes, valid_raw_nodes := array_from_value(raw_document)
	if valid_raw_nodes && len(raw_nodes) == 1 {
		node, valid_node := object_from_value(raw_nodes[0])
		_, has_id := object_value(node, "@id")
		property_count := 0
		json_null_predicate := ""
		if valid_node && !has_id {
			for predicate, values_value in node {
				if is_keyword(predicate) do continue
				property_count += 1
				values, valid_values := array_from_value(values_value)
				definition, found_definition := context_definition_for_iri(ctx, predicate)
				if !valid_values || !found_definition || definition.type != "@json" || len(values) != 1 { json_null_predicate = ""; break }
				value, valid_value := object_from_value(values[0])
				raw_value, has_raw_value := object_value(value, "@value")
				type_value, has_type := object_value(value, "@type")
				type_name, valid_type := string_value(type_value)
				is_null := false
				#partial switch _ in raw_value {
				case json.Null: is_null = true
				}
				if !valid_value || !has_raw_value || !is_null || !has_type || !valid_type || type_name != "@json" { json_null_predicate = ""; break }
				json_null_predicate = predicate
			}
			if property_count == 1 && len(json_null_predicate) > 0 {
				owned_predicate, predicate_error := own(state, json_null_predicate)
				if predicate_error.code != .None do return .Out_Of_Memory
				state.compact_source_json_null_predicate = owned_predicate
			}
		}
	}
	if len(nodes) == 1 {
		node, valid_node := object_from_value(nodes[0])
		root_value, has_root := object_value(node, "@id")
		root_id, valid_root := string_value(root_value)
		reverse_value, has_reverse := object_value(node, "@reverse")
		reverse, valid_reverse := object_from_value(reverse_value)
		if valid_node && has_root && valid_root && has_reverse && valid_reverse {
			for reverse_predicate, values_value in reverse {
				definition: Term_Definition
				term := ""
				for candidate, candidate_definition in ctx.terms {
					if !candidate_definition.reverse || candidate_definition.id != reverse_predicate || !candidate_definition.container_index || !candidate_definition.has_index || candidate_definition.index == "@index" do continue
					if len(term) > 0 { term = ""; break }
					term = candidate
					definition = candidate_definition
				}
				if len(term) == 0 do continue
				values, valid_values := array_from_value(values_value)
				if !valid_values do return .Invalid_Expanded_JSON
				for value in values {
					statement, valid_statement := object_from_value(value)
					if !valid_statement do continue
					index_values_value, has_index_values := object_value(statement, definition.index)
					index_values, valid_index_values := array_from_value(index_values_value)
					if !has_index_values || !valid_index_values || len(index_values) != 1 do continue
					index_object, valid_index_object := object_from_value(index_values[0])
					index_id_value, has_index_id := object_value(index_object, "@id")
					index_id, valid_index_id := string_value(index_id_value)
					if !valid_index_object || !has_index_id || !valid_index_id do continue
					signature, signature_error := compact_graph_fragment_signature(value)
					if signature_error != .None do return signature_error
					owned_root, root_error := own(state, root_id)
					if root_error.code != .None do return .Out_Of_Memory
					owned_term, term_error := own(state, term)
					if term_error.code != .None do return .Out_Of_Memory
					owned_reverse, reverse_error := own(state, reverse_predicate)
					if reverse_error.code != .None do return .Out_Of_Memory
					owned_index_predicate, index_predicate_error := own(state, definition.index)
					if index_predicate_error.code != .None do return .Out_Of_Memory
					owned_index_id, index_id_error := own(state, index_id)
					if index_id_error.code != .None do return .Out_Of_Memory
					owned_signature, signature_copy_error := own(state, signature)
					delete(signature)
					if signature_copy_error.code != .None do return .Out_Of_Memory
					append(&state.compact_source_reverse_index_annotations, Compact_Source_Reverse_Index_Annotation{root_id = owned_root, term = owned_term, reverse_predicate = owned_reverse, index_predicate = owned_index_predicate, index_id = owned_index_id, source_signature = owned_signature})
				}
			}
		}
	}
	if len(nodes) == 1 {
		node, valid_node := object_from_value(nodes[0])
		_, has_id := object_value(node, "@id")
		if valid_node && !has_id {
			for predicate, values_value in node {
				if is_keyword(predicate) do continue
				values, valid_values := array_from_value(values_value)
				if !valid_values do return .Invalid_Expanded_JSON
				definition, found_definition := context_definition_for_iri(ctx, predicate)
				if !found_definition || !definition.container_graph || definition.container_id || definition.container_index || definition.container_set do continue
				for item in values {
					target, valid_target := object_from_value(item)
					if !valid_target do continue
					_, has_graph := object_value(target, "@graph")
					target_id_value, has_target_id := object_value(target, "@id")
					target_id, valid_target_id := string_value(target_id_value)
					if !has_graph || !has_target_id || !valid_target_id do continue
					owned_predicate, predicate_error := own(state, predicate)
					if predicate_error.code != .None do return .Out_Of_Memory
					owned_target_id, target_error := own(state, target_id)
					if target_error.code != .None do return .Out_Of_Memory
					append(&state.compact_source_named_graph_annotations, Compact_Source_Named_Graph_Annotation{predicate = owned_predicate, target_id = owned_target_id})
				}
			}
		}
	}
	if len(nodes) == 1 {
		node, valid_node := object_from_value(nodes[0])
		_, has_id := object_value(node, "@id")
		if valid_node && !has_id {
			for predicate, values_value in node {
				if is_keyword(predicate) do continue
				values, valid_values := array_from_value(values_value)
				if !valid_values do return .Invalid_Expanded_JSON
				definition, found_definition := context_definition_for_iri(ctx, predicate)
				if !found_definition || !definition.container_graph || !definition.container_index || definition.container_id || definition.container_set do continue
				for item in values {
					target, valid_target := object_from_value(item)
					if !valid_target do continue
					_, has_graph := object_value(target, "@graph")
					index_value, has_index := object_value(target, "@index")
					index, valid_index := string_value(index_value)
					target_id_value, has_target_id := object_value(target, "@id")
					target_id, valid_target_id := string_value(target_id_value)
					if !has_graph || !has_index || !valid_index || !has_target_id || !valid_target_id do continue
					owned_predicate, predicate_error := own(state, predicate)
					if predicate_error.code != .None do return .Out_Of_Memory
					owned_target_id, target_error := own(state, target_id)
					if target_error.code != .None do return .Out_Of_Memory
					owned_index, index_error := own(state, index)
					if index_error.code != .None do return .Out_Of_Memory
					append(&state.compact_source_named_graph_index_annotations, Compact_Source_Named_Graph_Index_Annotation{predicate = owned_predicate, target_id = owned_target_id, index = owned_index})
				}
			}
		}
	}
	if len(nodes) == 1 {
		node, valid_node := object_from_value(nodes[0])
		_, has_id := object_value(node, "@id")
		if valid_node && !has_id {
			for predicate, values_value in node {
				if is_keyword(predicate) do continue
				values, valid_values := array_from_value(values_value)
				if !valid_values do return .Invalid_Expanded_JSON
				definition, found_definition := context_definition_for_iri(ctx, predicate)
				if !found_definition || !definition.container_graph || !definition.container_index || definition.container_id do continue
				for item in values {
					target, valid_target := object_from_value(item)
					if !valid_target do continue
					_, has_graph := object_value(target, "@graph")
					index_value, has_index := object_value(target, "@index")
					index, valid_index := string_value(index_value)
					_, target_has_id := object_value(target, "@id")
					if !has_graph || !has_index || !valid_index || target_has_id do continue
					owned_predicate, predicate_error := own(state, predicate)
					if predicate_error.code != .None do return .Out_Of_Memory
					owned_index, index_error := own(state, index)
					if index_error.code != .None do return .Out_Of_Memory
					append(&state.compact_source_graph_index_annotations, Compact_Source_Graph_Index_Annotation{predicate = owned_predicate, index = owned_index})
				}
			}
		}
	}
	if len(nodes) == 1 {
		node, valid_node := object_from_value(nodes[0])
		_, has_id := object_value(node, "@id")
		if valid_node && !has_id {
			for predicate, values_value in node {
				if is_keyword(predicate) do continue
				values, valid_values := array_from_value(values_value)
				if !valid_values do return .Invalid_Expanded_JSON
				definition, found_definition := context_definition_for_iri(ctx, predicate)
				if !found_definition || !definition.container_graph || (!definition.container_id && !definition.container_index) do continue
				for item in values {
					target, valid_target := object_from_value(item)
					if !valid_target do continue
					graph_value, has_graph := object_value(target, "@graph")
					_, has_index := object_value(target, "@index")
					target_id_value, target_has_id := object_value(target, "@id")
					target_id, valid_target_id := string_value(target_id_value)
					if !has_graph || (!definition.container_id && has_index) || (target_has_id && !valid_target_id) do continue
					owned_predicate, predicate_error := own(state, predicate)
					if predicate_error.code != .None do return .Out_Of_Memory
					owned_target_id, target_id_error := own(state, target_has_id ? target_id : "")
					if target_id_error.code != .None do return .Out_Of_Memory
					fragment_signature := ""
					if graph_items, valid_graph_items := array_from_value(graph_value); valid_graph_items && len(graph_items) == 1 {
						signature, signature_error := compact_graph_fragment_signature(graph_items[0])
						if signature_error != .None do return signature_error
						owned_signature, signature_copy_error := own(state, signature)
						delete(signature)
						if signature_copy_error.code != .None do return .Out_Of_Memory
						fragment_signature = owned_signature
					}
					append(&state.compact_source_graph_id_annotations, Compact_Source_Graph_ID_Annotation{predicate = owned_predicate, target_id = owned_target_id, graph_fragment_signature = fragment_signature})
				}
			}
		}
	}
	// The RDF conversion of an anonymous graph container introduces an
	// implementation blank node for both the containing node and the graph
	// name. Preserve only the narrow, unambiguous source shape here; graph
	// index/id maps retain their separate handling below.
	if len(nodes) == 1 {
		node, valid_node := object_from_value(nodes[0])
		_, has_id := object_value(node, "@id")
		if valid_node && !has_id {
			for predicate, values_value in node {
				if is_keyword(predicate) do continue
				values, valid_values := array_from_value(values_value)
				if !valid_values do return .Invalid_Expanded_JSON
				for item in values {
					target, valid_target := object_from_value(item)
					if !valid_target do continue
					_, has_graph := object_value(target, "@graph")
					_, target_has_id := object_value(target, "@id")
					if has_graph && !target_has_id {
						definition, found_definition := context_definition_for_iri(ctx, predicate)
						if !found_definition || !definition.container_graph || definition.container_id || definition.container_index do continue
						// Keep both forms because the serializer uses expanded
						// predicates while the context may choose the compact term.
						state.compact_source_graph_predicates[predicate] = true
						for term, definition in ctx.terms {
							if definition.id == predicate do state.compact_source_graph_predicates[term] = true
						}
					}
				}
			}
		}
	}
	if len(nodes) == 1 {
		node, valid_node := object_from_value(nodes[0])
		_, has_id := object_value(node, "@id")
		if valid_node && !has_id {
			for predicate, values_value in node {
				if is_keyword(predicate) do continue
				definition, found_definition := context_definition_for_iri(ctx, predicate)
				if !found_definition || definition.container_graph do continue
				values, valid_values := array_from_value(values_value)
				if !valid_values || len(values) == 0 do continue
				valid_boundary := true
				for item in values {
					target, valid_target := object_from_value(item)
					_, has_graph := object_value(target, "@graph")
					_, target_has_id := object_value(target, "@id")
					if !valid_target || !has_graph || target_has_id { valid_boundary = false; break }
				}
				if !valid_boundary do continue
				owned_predicate, predicate_error := own(state, predicate)
				if predicate_error.code != .None do return .Out_Of_Memory
				state.compact_source_graph_boundary_predicates[owned_predicate] = true
			}
		}
	}
	return .None
}

@(private) compact_mark_source_graph_boundaries :: proc(state: ^State, nodes: json.Array) -> Compact_Error {
	if len(state.compact_source_graph_boundary_predicates) == 0 do return .None
	root_id := ""
	for node_value in nodes {
		node, valid_node := object_from_value(node_value)
		if !valid_node do return .Invalid_Expanded_JSON
		id_value, has_id := object_value(node, "@id")
		identifier, valid_identifier := string_value(id_value)
		if !has_id || !valid_identifier || !strings.has_prefix(identifier, "_:") do continue
		for predicate, values_value in node {
			matched := false
			for source_predicate in state.compact_source_graph_boundary_predicates {
				if compact_annotation_predicate_matches(source_predicate, predicate, predicate, "") { matched = true; break }
			}
			if !matched do continue
			values, valid_values := array_from_value(values_value)
			if !valid_values || len(values) == 0 do continue
			graph_ids := make([dynamic]string)
			valid_boundary := true
			for value in values {
				reference, valid_reference := object_from_value(value)
				reference_id_value, has_reference_id := object_value(reference, "@id")
				reference_id, valid_reference_id := string_value(reference_id_value)
				if !valid_reference || !has_reference_id || !valid_reference_id { valid_boundary = false; break }
				target, found_target := state.compact_nodes[reference_id]
				_, has_graph := object_value(target, "@graph")
				if !found_target || !has_graph { valid_boundary = false; break }
				append(&graph_ids, reference_id)
			}
			if !valid_boundary { delete(graph_ids); continue }
			if root_id != "" && root_id != identifier { delete(graph_ids); return .None }
			root_id = identifier
			for graph_id in graph_ids do state.compact_source_graph_boundary_nodes[graph_id] = true
			delete(graph_ids)
		}
	}
	if root_id != "" do state.compact_source_graph_root_id = root_id
	return .None
}

@(private) compact_mark_source_graph_container_nodes :: proc(state: ^State, nodes: json.Array) -> Compact_Error {
	if len(state.compact_source_graph_predicates) == 0 do return .None
	root_id := ""
	for node_value in nodes {
		node, valid_node := object_from_value(node_value)
		if !valid_node do return .Invalid_Expanded_JSON
		id_value, has_id := object_value(node, "@id")
		identifier, valid_identifier := string_value(id_value)
		if !has_id || !valid_identifier || !strings.has_prefix(identifier, "_:") do continue
		for predicate, values_value in node {
			matched := false
			for source_predicate in state.compact_source_graph_predicates {
				if compact_annotation_predicate_matches(source_predicate, predicate, predicate, "") { matched = true; break }
			}
			if !matched do continue
			values, valid_values := array_from_value(values_value)
			if !valid_values || len(values) == 0 do continue
			graph_ids := make([dynamic]string)
			valid_container := true
			for value in values {
				reference, valid_reference := object_from_value(value)
				reference_id_value, has_reference_id := object_value(reference, "@id")
				reference_id, valid_reference_id := string_value(reference_id_value)
				if !valid_reference || !has_reference_id || !valid_reference_id { valid_container = false; break }
				target, found_target := state.compact_nodes[reference_id]
				_, has_graph := object_value(target, "@graph")
				if !found_target || !has_graph { valid_container = false; break }
				append(&graph_ids, reference_id)
			}
			if !valid_container { delete(graph_ids); continue }
			if root_id != "" && root_id != identifier { delete(graph_ids); return .None }
			root_id = identifier
			for graph_id in graph_ids do state.compact_source_graph_nodes[graph_id] = true
			delete(graph_ids)
		}
	}
	if root_id != "" do state.compact_source_graph_root_id = root_id
	return .None
}

// compact_mark_source_document_root restores an anonymous source custom-index
// map root when its complete predicate set identifies one RDF blank node.
@(private) compact_mark_source_document_root :: proc(state: ^State, nodes: json.Array) -> Compact_Error {
	if len(state.compact_source_document_root_predicates) == 0 do return .None
	root_id := ""
	for node_value in nodes {
		node, valid_node := object_from_value(node_value)
		if !valid_node do return .Invalid_Expanded_JSON
		id_value, has_id := object_value(node, "@id")
		identifier, valid_identifier := string_value(id_value)
		if !has_id || !valid_identifier || !strings.has_prefix(identifier, "_:") do continue
		if len(state.compact_source_document_root_types) > 0 {
			type_value, has_type := object_value(node, "@type")
			types, valid_types := array_from_value(type_value)
			if !has_type || !valid_types || len(types) != len(state.compact_source_document_root_types) do continue
			matched_types := 0
			for type_value in types {
				type_id, valid_type := string_value(type_value)
				if !valid_type { matched_types = -1; break }
				for source_type in state.compact_source_document_root_types {
					if source_type == type_id { matched_types += 1; break }
				}
			}
			if matched_types != len(state.compact_source_document_root_types) do continue
		}
		matched_count := 0
		valid_match := true
		for predicate, values_value in node {
			if is_keyword(predicate) do continue
			values, valid_values := array_from_value(values_value)
			if !valid_values || len(values) == 0 { valid_match = false; break }
			matched_index := -1
			for source_predicate, source_index in state.compact_source_document_root_predicates {
				if compact_annotation_predicate_matches(source_predicate, predicate, predicate, "") { matched_index = source_index; break }
			}
			if matched_index < 0 { valid_match = false; break }
			if len(state.compact_source_document_root_predicate_counts) == len(state.compact_source_document_root_predicates) && len(values) != state.compact_source_document_root_predicate_counts[matched_index] { valid_match = false; break }
			matched_count += 1
		}
		if !valid_match || matched_count != len(state.compact_source_document_root_predicates) do continue
		if root_id != "" do return .None
		root_id = identifier
	}
	if root_id != "" do state.compact_source_graph_root_id = root_id
	return .None
}

// Once a source root has been uniquely selected, graph references directly
// owned by its graph-container terms are source boundaries rather than
// standalone top-level nodes. Their anonymous graph names are serializer
// details and can compact to graph contents.
@(private) compact_mark_source_root_graph_nodes :: proc(state: ^State, ctx: ^Context) -> Compact_Error {
	if len(state.compact_source_graph_root_id) == 0 do return .None
	root, found_root := state.compact_nodes[state.compact_source_graph_root_id]
	if !found_root do return .None
	root_context, _, context_error := compact_resolve_object_context(state, ctx, {}, root)
	if context_error != .None do return context_error
	for predicate, values_value in root {
		if is_keyword(predicate) do continue
		definition, found_definition := context_definition_for_iri(&root_context, predicate)
		if !found_definition || !definition.container_graph do continue
		values, valid_values := array_from_value(values_value)
		if !valid_values do return .Invalid_Expanded_JSON
		for value in values {
			reference, valid_reference := object_from_value(value)
			identifier_value, has_identifier := object_value(reference, "@id")
			identifier, valid_identifier := string_value(identifier_value)
			if !valid_reference || !has_identifier || !valid_identifier do continue
			target, found_target := state.compact_nodes[identifier]
			_, has_graph := object_value(target, "@graph")
			if found_target && has_graph do state.compact_source_graph_nodes[identifier] = true
		}
	}
	return .None
}

@(private) compact_mark_source_named_graph_root :: proc(state: ^State, nodes: json.Array) -> Compact_Error {
	if len(state.compact_source_named_graph_annotations) != 1 do return .None
	annotation := state.compact_source_named_graph_annotations[0]
	root_id := ""
	for node_value in nodes {
		node, valid_node := object_from_value(node_value)
		if !valid_node do return .Invalid_Expanded_JSON
		id_value, has_id := object_value(node, "@id")
		identifier, valid_identifier := string_value(id_value)
		if !has_id || !valid_identifier || !strings.has_prefix(identifier, "_:") do continue
		for predicate, values_value in node {
			if !compact_annotation_predicate_matches(annotation.predicate, predicate, predicate, "") do continue
			values, valid_values := array_from_value(values_value)
			if !valid_values || len(values) != 1 do continue
			reference, valid_reference := object_from_value(values[0])
			reference_id_value, has_reference_id := object_value(reference, "@id")
			reference_id, valid_reference_id := string_value(reference_id_value)
			if !valid_reference || !has_reference_id || !valid_reference_id || reference_id != annotation.target_id do continue
			target, found_target := state.compact_nodes[reference_id]
			if !found_target do continue
			_, has_graph := object_value(target, "@graph")
			if !has_graph do continue
			if root_id != "" && root_id != identifier do return .None
			root_id = identifier
		}
	}
	if root_id != "" do state.compact_source_graph_root_id = root_id
	return .None
}

@(private) compact_mark_source_named_graph_index_root :: proc(state: ^State, nodes: json.Array) -> Compact_Error {
	if len(state.compact_source_named_graph_index_annotations) != 1 do return .None
	annotation := state.compact_source_named_graph_index_annotations[0]
	root_id := ""
	graph_id := ""
	for node_value in nodes {
		node, valid_node := object_from_value(node_value)
		if !valid_node do return .Invalid_Expanded_JSON
		id_value, has_id := object_value(node, "@id")
		identifier, valid_identifier := string_value(id_value)
		if !has_id || !valid_identifier || !strings.has_prefix(identifier, "_:") do continue
		for predicate, values_value in node {
			if !compact_annotation_predicate_matches(annotation.predicate, predicate, predicate, "") do continue
			values, valid_values := array_from_value(values_value)
			if !valid_values || len(values) != 1 do continue
			reference, valid_reference := object_from_value(values[0])
			reference_id_value, has_reference_id := object_value(reference, "@id")
			reference_id, valid_reference_id := string_value(reference_id_value)
			if !valid_reference || !has_reference_id || !valid_reference_id || reference_id != annotation.target_id do continue
			target, found_target := state.compact_nodes[reference_id]
			if !found_target do continue
			_, has_graph := object_value(target, "@graph")
			if !has_graph do continue
			if root_id != "" && root_id != identifier do return .None
			if graph_id != "" && graph_id != reference_id do return .None
			root_id = identifier
			graph_id = reference_id
		}
	}
	if root_id != "" {
		state.compact_source_graph_root_id = root_id
		append(&state.compact_source_named_graph_index_nodes, Compact_Source_Named_Graph_Index_Node{graph_id = graph_id, index = annotation.index})
	}
	return .None
}

@(private) compact_source_named_graph_index :: proc(state: ^State, graph_id: string) -> (string, bool) {
	for node in state.compact_source_named_graph_index_nodes {
		if node.graph_id == graph_id do return node.index, true
	}
	return "", false
}

// compact_mark_source_graph_index_root reconnects anonymous graph containers
// carrying ordinary @index members. RDF does not retain that association, so
// it is recovered only when a single source property supplies a one-to-one
// sequence of graph references and source annotations.
@(private) compact_mark_source_graph_index_root :: proc(state: ^State, nodes: json.Array) -> Compact_Error {
	if len(state.compact_source_graph_index_annotations) == 0 do return .None
	root_id := ""
	for node_value in nodes {
		node, valid_node := object_from_value(node_value)
		if !valid_node do return .Invalid_Expanded_JSON
		id_value, has_id := object_value(node, "@id")
		identifier, valid_identifier := string_value(id_value)
		if !has_id || !valid_identifier || !strings.has_prefix(identifier, "_:") do continue
		for predicate, values_value in node {
			if is_keyword(predicate) do continue
			values, valid_values := array_from_value(values_value)
			if !valid_values do return .Invalid_Expanded_JSON
			annotations := make([dynamic]Compact_Source_Graph_Index_Annotation)
			defer delete(annotations)
			for annotation in state.compact_source_graph_index_annotations {
				if compact_annotation_predicate_matches(annotation.predicate, predicate, predicate, "") do append(&annotations, annotation)
			}
			if len(annotations) == 0 || len(annotations) != len(values) do continue
			candidates := make([dynamic]Compact_Source_Graph_Index_Node)
			defer delete(candidates)
			valid_candidates := true
			for value, value_index in values {
				reference, valid_reference := object_from_value(value)
				reference_id_value, has_reference_id := object_value(reference, "@id")
				reference_id, valid_reference_id := string_value(reference_id_value)
				if !valid_reference || !has_reference_id || !valid_reference_id {
					valid_candidates = false
					break
				}
				target, found_target := state.compact_nodes[reference_id]
				if !found_target {
					valid_candidates = false
					break
				}
				_, has_graph := object_value(target, "@graph")
				if !has_graph {
					valid_candidates = false
					break
				}
				for candidate in candidates {
					if candidate.graph_id == reference_id {
						valid_candidates = false
						break
					}
				}
				if !valid_candidates do break
				append(&candidates, Compact_Source_Graph_Index_Node{graph_id = reference_id, index = annotations[value_index].index})
			}
			if !valid_candidates do continue
			if root_id != "" && root_id != identifier do return .None
			root_id = identifier
			for candidate in candidates do append(&state.compact_source_graph_index_nodes, candidate)
		}
	}
	if root_id != "" do state.compact_source_graph_root_id = root_id
	return .None
}

// compact_mark_source_graph_id_root restores source graph-ID map keys. A
// graph without an explicit @id uses @none by definition. Associations are
// accepted only when one source property accounts for every graph reference.
@(private) compact_mark_source_graph_id_root :: proc(state: ^State, nodes: json.Array) -> Compact_Error {
	if len(state.compact_source_graph_id_annotations) == 0 do return .None
	root_id := ""
	for node_value in nodes {
		node, valid_node := object_from_value(node_value)
		if !valid_node do return .Invalid_Expanded_JSON
		id_value, has_id := object_value(node, "@id")
		identifier, valid_identifier := string_value(id_value)
		if !has_id || !valid_identifier || !strings.has_prefix(identifier, "_:") do continue
		for predicate, values_value in node {
			if is_keyword(predicate) do continue
			values, valid_values := array_from_value(values_value)
			if !valid_values do return .Invalid_Expanded_JSON
			annotations := make([dynamic]Compact_Source_Graph_ID_Annotation)
			defer delete(annotations)
			for annotation in state.compact_source_graph_id_annotations {
				if compact_annotation_predicate_matches(annotation.predicate, predicate, predicate, "") do append(&annotations, annotation)
			}
			if len(annotations) == 0 || len(annotations) != len(values) do continue
			candidates := make([dynamic]Compact_Source_Graph_Index_Node)
			defer delete(candidates)
			valid_candidates := true
			for value in values {
				reference, valid_reference := object_from_value(value)
				reference_id_value, has_reference_id := object_value(reference, "@id")
				reference_id, valid_reference_id := string_value(reference_id_value)
				if !valid_reference || !has_reference_id || !valid_reference_id {
					valid_candidates = false
					break
				}
				target, found_target := state.compact_nodes[reference_id]
				if !found_target {
					valid_candidates = false
					break
				}
				_, has_graph := object_value(target, "@graph")
				if !has_graph {
					valid_candidates = false
					break
				}
				matched_annotation := -1
				for annotation, annotation_index in annotations {
					if annotation.target_id == reference_id || (len(annotation.target_id) == 0 && len(annotations) == 1 && len(values) == 1) {
						matched_annotation = annotation_index
						break
					}
				}
				if matched_annotation < 0 {
					valid_candidates = false
					break
				}
				for candidate in candidates {
					if candidate.graph_id == reference_id || (len(annotations[matched_annotation].target_id) > 0 && candidate.index == annotations[matched_annotation].target_id) {
						valid_candidates = false
						break
					}
				}
				if !valid_candidates do break
				if len(annotations[matched_annotation].target_id) > 0 {
					append(&candidates, Compact_Source_Graph_Index_Node{graph_id = reference_id, index = annotations[matched_annotation].target_id})
				} else {
					append(&candidates, Compact_Source_Graph_Index_Node{graph_id = reference_id, keyword_none = true})
				}
			}
			if !valid_candidates do continue
			if root_id != "" && root_id != identifier do return .None
			root_id = identifier
			for candidate in candidates do append(&state.compact_source_graph_index_nodes, candidate)
		}
	}
	if root_id != "" do state.compact_source_graph_root_id = root_id
	return .None
}

@(private) compact_source_graph_fragment_count :: proc(state: ^State, predicate, graph_id: string) -> int {
	count := 0
	for annotation in state.compact_source_graph_id_annotations {
		if annotation.predicate == predicate && annotation.target_id == graph_id && len(annotation.graph_fragment_signature) > 0 do count += 1
	}
	return count
}

// compact_source_graph_fragments_match proves that every node in a merged
// serializer graph belongs to exactly one source occurrence of that graph.
@(private) compact_source_graph_fragments_match :: proc(state: ^State, predicate, graph_id: string, graph_value: json.Value) -> (bool, Compact_Error) {
	items, valid_items := array_from_value(graph_value)
	if !valid_items do return false, .Invalid_Expanded_JSON
	fragment_count := compact_source_graph_fragment_count(state, predicate, graph_id)
	if fragment_count == 0 || len(items) != fragment_count do return false, .None
	used := make([dynamic]bool)
	defer delete(used)
	for _ in items do append(&used, false)
	for annotation in state.compact_source_graph_id_annotations {
		if annotation.predicate != predicate || annotation.target_id != graph_id || len(annotation.graph_fragment_signature) == 0 do continue
		matched := false
		for item, item_index in items {
			if used[item_index] do continue
			signature, signature_error := compact_graph_fragment_signature(item)
			if signature_error != .None do return false, signature_error
			equal := signature == annotation.graph_fragment_signature
			delete(signature)
			if !equal do continue
			used[item_index] = true
			matched = true
			break
		}
		if !matched do return false, .None
	}
	return true, .None
}

// compact_mark_source_graph_id_fragments restores repeated named graph
// occurrences only when their source node fragments cover the merged RDF
// graph exactly. That prevents a lossy RDF merge from being guessed apart.
@(private) compact_mark_source_graph_id_fragments :: proc(state: ^State, nodes: json.Array) -> Compact_Error {
	if len(state.compact_source_graph_id_annotations) == 0 do return .None
	root_id := ""
	for node_value in nodes {
		node, valid_node := object_from_value(node_value)
		if !valid_node do return .Invalid_Expanded_JSON
		id_value, has_id := object_value(node, "@id")
		identifier, valid_identifier := string_value(id_value)
		if !has_id || !valid_identifier || !strings.has_prefix(identifier, "_:") do continue
		for predicate, values_value in node {
			if is_keyword(predicate) do continue
			values, valid_values := array_from_value(values_value)
			if !valid_values || len(values) == 0 do continue
			annotation_count := 0
			has_repeated_graph := false
			for annotation in state.compact_source_graph_id_annotations {
				if annotation.predicate != predicate || len(annotation.graph_fragment_signature) == 0 do continue
				annotation_count += 1
				if compact_source_graph_fragment_count(state, predicate, annotation.target_id) > 1 do has_repeated_graph = true
			}
			if annotation_count == 0 || !has_repeated_graph do continue
			graph_ids := make([dynamic]string)
			defer delete(graph_ids)
			matched_annotations := 0
			valid_fragments := true
			for value in values {
				reference, valid_reference := object_from_value(value)
				reference_id_value, has_reference_id := object_value(reference, "@id")
				reference_id, valid_reference_id := string_value(reference_id_value)
				if !valid_reference || !has_reference_id || !valid_reference_id { valid_fragments = false; break }
				for graph_id in graph_ids {
					if graph_id == reference_id { valid_fragments = false; break }
				}
				if !valid_fragments do break
				target, found_target := state.compact_nodes[reference_id]
				graph_value, has_graph := object_value(target, "@graph")
				if !found_target || !has_graph { valid_fragments = false; break }
				matches, match_error := compact_source_graph_fragments_match(state, predicate, reference_id, graph_value)
				if match_error != .None do return match_error
				if !matches { valid_fragments = false; break }
				matched_annotations += compact_source_graph_fragment_count(state, predicate, reference_id)
				append(&graph_ids, reference_id)
			}
			if !valid_fragments || matched_annotations != annotation_count do continue
			if root_id != "" && root_id != identifier do return .None
			root_id = identifier
			for graph_id in graph_ids {
				_, _, already_mapped := compact_source_graph_map_key(state, graph_id)
				if !already_mapped do append(&state.compact_source_graph_index_nodes, Compact_Source_Graph_Index_Node{graph_id = graph_id, index = graph_id, fragment_predicate = predicate})
			}
		}
	}
	if root_id != "" do state.compact_source_graph_root_id = root_id
	return .None
}

@(private) compact_source_graph_map_key :: proc(state: ^State, graph_id: string) -> (string, bool, bool) {
	for node in state.compact_source_graph_index_nodes {
		if node.graph_id == graph_id do return node.index, node.keyword_none, true
	}
	return "", false, false
}

@(private) compact_source_graph_fragment_predicate :: proc(state: ^State, graph_id: string) -> (string, bool) {
	for node in state.compact_source_graph_index_nodes {
		if node.graph_id == graph_id && len(node.fragment_predicate) > 0 do return node.fragment_predicate, true
	}
	return "", false
}

@(private) compact_value_has_source_graph_map_key :: proc(state: ^State, value: json.Value) -> bool {
	object, valid_object := object_from_value(value)
	id_value, has_id := object_value(object, "@id")
	identifier, valid_identifier := string_value(id_value)
	if !valid_object || !has_id || !valid_identifier do return false
	_, _, found := compact_source_graph_map_key(state, identifier)
	return found
}

@(private) compact_value_has_source_graph_recovery :: proc(state: ^State, value: json.Value) -> bool {
	object, valid_object := object_from_value(value)
	id_value, has_id := object_value(object, "@id")
	identifier, valid_identifier := string_value(id_value)
	if !valid_object || !has_id || !valid_identifier do return false
	if state.compact_source_graph_nodes[identifier] do return true
	return compact_value_has_source_graph_map_key(state, value)
}

// compact_mark_source_graph_root reconnects the one anonymous source root
// whose @graph container was split into a property reference plus a graph
// node by RDF serialization. It intentionally refuses multiple candidates:
// in that case the dataset form is retained rather than guessing an order or
// association that RDF cannot represent.
@(private) compact_mark_source_graph_root :: proc(state: ^State, nodes: json.Array) -> Compact_Error {
	if len(state.compact_source_graph_predicates) == 0 && len(state.compact_source_graph_boundary_predicates) == 0 do return .None
	root_id := ""
	graph_id := ""
	for node_value in nodes {
		node, valid_node := object_from_value(node_value)
		if !valid_node do return .Invalid_Expanded_JSON
		id_value, has_id := object_value(node, "@id")
		identifier, valid_identifier := string_value(id_value)
		if !has_id || !valid_identifier || !strings.has_prefix(identifier, "_:") do continue
		for predicate, values_value in node {
			source_predicate_matches := false
			boundary_predicate_matches := false
			for source_predicate in state.compact_source_graph_predicates {
				if compact_annotation_predicate_matches(source_predicate, predicate, predicate, "") {
					source_predicate_matches = true
					break
				}
			}
			for source_predicate in state.compact_source_graph_boundary_predicates {
				if compact_annotation_predicate_matches(source_predicate, predicate, predicate, "") { boundary_predicate_matches = true; break }
			}
			if !source_predicate_matches && !boundary_predicate_matches do continue
			values, valid_values := array_from_value(values_value)
			if !valid_values || len(values) != 1 do continue
			reference, valid_reference := object_from_value(values[0])
			reference_id_value, has_reference_id := object_value(reference, "@id")
			reference_id, valid_reference_id := string_value(reference_id_value)
			if !valid_reference || !has_reference_id || !valid_reference_id do continue
			target, found_target := state.compact_nodes[reference_id]
			if !found_target do continue
			_, has_graph := object_value(target, "@graph")
			if !has_graph do continue
			if root_id != "" && root_id != identifier do return .None
			if graph_id != "" && graph_id != reference_id do return .None
			root_id = identifier
			graph_id = reference_id
		}
	}
	if root_id != "" {
		state.compact_source_graph_root_id = root_id
		state.compact_source_graph_nodes[graph_id] = true
		if len(state.compact_source_graph_boundary_predicates) > 0 do state.compact_source_graph_boundary_nodes[graph_id] = true
	}
	return .None
}

@(private) compact_index_annotation_subject_matches :: proc(state: ^State, annotation_subject, subject_id: string) -> bool {
	if annotation_subject == subject_id do return true
	if len(annotation_subject) != 0 || !strings.has_prefix(subject_id, "_:") do return false
	return len(state.compact_source_graph_root_id) == 0 || subject_id == state.compact_source_graph_root_id
}

@(private) compact_index_annotation :: proc(state: ^State, ctx: ^Context, subject_id, predicate, expanded_predicate, definition_id, target_id: string, target: json.Object) -> (string, bool, Compact_Error) {
	signature, signature_error := compact_index_target_signature(ctx, target)
	if signature_error != .None do return "", false, signature_error
	defer delete(signature)
	for annotation in state.compact_index_annotations {
		if annotation.raw_none do continue
		if !compact_index_annotation_subject_matches(state, annotation.subject_id, subject_id) || !compact_annotation_predicate_matches(annotation.predicate, predicate, expanded_predicate, definition_id) do continue
		if len(annotation.target_id) > 0 && annotation.target_id == target_id do return annotation.index, true, .None
		if len(annotation.target_id) == 0 && annotation.target_signature == signature do return annotation.index, true, .None
	}
	return "", false, .None
}

@(private) compact_raw_list_index_annotation :: proc(state: ^State, subject_id, predicate, expanded_predicate, definition_id: string) -> (string, bool) {
	for annotation in state.compact_index_annotations {
		if annotation.raw_none do continue
		if len(annotation.target_id) != 0 || len(annotation.target_signature) != 0 do continue
		if !annotation.list do continue
		if !compact_index_annotation_subject_matches(state, annotation.subject_id, subject_id) do continue
		if compact_annotation_predicate_matches(annotation.predicate, predicate, expanded_predicate, definition_id) do return annotation.index, true
	}
	return "", false
}

@(private) compact_raw_index_annotation_count :: proc(state: ^State, subject_id, predicate, expanded_predicate, definition_id: string) -> int {
	count := 0
	for annotation in state.compact_index_annotations {
		if annotation.raw_none do continue
		if len(annotation.target_id) != 0 || len(annotation.target_signature) != 0 do continue
		if annotation.list do continue
		if !compact_index_annotation_subject_matches(state, annotation.subject_id, subject_id) do continue
		if compact_annotation_predicate_matches(annotation.predicate, predicate, expanded_predicate, definition_id) do count += 1
	}
	return count
}

@(private) compact_raw_index_annotation_at :: proc(state: ^State, subject_id, predicate, expanded_predicate, definition_id: string, order: int) -> (string, bool) {
	for annotation in state.compact_index_annotations {
		if annotation.raw_none do continue
		if len(annotation.target_id) != 0 || len(annotation.target_signature) != 0 || annotation.order != order do continue
		if annotation.list do continue
		if !compact_index_annotation_subject_matches(state, annotation.subject_id, subject_id) do continue
		if compact_annotation_predicate_matches(annotation.predicate, predicate, expanded_predicate, definition_id) do return annotation.index, true
	}
	return "", false
}

@(private) compact_raw_none_index_annotation_count :: proc(state: ^State, subject_id, predicate, expanded_predicate, definition_id: string) -> int {
	count := 0
	for annotation in state.compact_index_annotations {
		if !annotation.raw_none do continue
		if !compact_index_annotation_subject_matches(state, annotation.subject_id, subject_id) do continue
		if compact_annotation_predicate_matches(annotation.predicate, predicate, expanded_predicate, definition_id) do count += 1
	}
	return count
}

@(private) compact_annotation_predicate_matches :: proc(annotation_predicate, predicate, expanded_predicate, definition_id: string) -> bool {
	return annotation_predicate == predicate || annotation_predicate == expanded_predicate || annotation_predicate == definition_id || strings.has_suffix(expanded_predicate, annotation_predicate)
}

// Compaction and Framing share type-scoped-context selection. Keeping the
// selection at the node boundary lets nested values use the same term rules
// regardless of which document operation writes them.
@(private) compact_write_node :: proc(builder: ^strings.Builder, state: ^State, inherited: ^Context, object: json.Object, policy: Compact_Array_Policy) -> Compact_Error {
	active_context, type_context, context_error := compact_resolve_object_context(state, inherited, {}, object)
	if context_error != .None do return context_error
	return compact_write_node_resolved(builder, state, &active_context, &type_context, object, policy)
}

@(private) compact_property_index_key :: proc(state: ^State, ctx: ^Context, definition: Term_Definition, value: json.Value) -> (string, bool, Compact_Error) {
	index_definition, found_definition := context_definition_for_iri(ctx, definition.index)
	if !found_definition do index_definition = Term_Definition{}
	object, valid := object_from_value(value)
	if !valid do return "", false, .None
	if id_value, has_id := object_value(object, "@id"); has_id {
		identifier, identifier_valid := string_value(id_value)
		if !identifier_valid do return "", false, .Invalid_Expanded_JSON
		if !found_definition || (index_definition.type != "@id" && index_definition.type != "@vocab") do return "", false, .None
		compacted, compact_error := compact_iri(state, ctx, identifier, index_definition.type == "@vocab", index_definition.type != "@id")
		if compact_error != .None do return "", false, compact_error
		return compacted, true, .None
	}
	if literal_value, has_literal := object_value(object, "@value"); has_literal {
		literal, literal_valid := string_value(literal_value)
		_, has_type := object_value(object, "@type")
		_, has_language := object_value(object, "@language")
		if literal_valid && !has_type && !has_language do return literal, true, .None
	}
	return "", false, .None
}

@(private) compact_write_property_index_entry :: proc(builder: ^strings.Builder, state: ^State, ctx: ^Context, entry: Compact_Property_Index_Entry, definition: Term_Definition, policy: Compact_Array_Policy) -> Compact_Error {
	if entry.index_value_index < 0 {
		// A custom index property without its own term coercion cannot become a
		// map key. When an @id-coerced value still has RDF properties, writing
		// only the identifier would lose those properties; retain the node form.
		if definition.type == "@id" {
			identifier_value, has_identifier := object_value(entry.object, "@id")
			identifier, valid_identifier := string_value(identifier_value)
			if has_identifier && valid_identifier && len(entry.object) > 1 do return compact_write_referenced_node(builder, state, ctx, entry.object, policy)
		}
		return compact_write_value(builder, state, ctx, entry.source, definition, true, policy)
	}
	object := entry.object
	index_values_value, found_index_values := object_value(object, definition.index)
	index_values, valid_index_values := array_from_value(index_values_value)
	if !found_index_values || !valid_index_values || entry.index_value_index >= len(index_values) do return .Invalid_Expanded_JSON
	temporary := make(json.Object)
	defer delete(temporary)
	for key, value in object do temporary[key] = value
	remaining := make(json.Array)
	defer delete(remaining)
	for value, index in index_values {
		if index != entry.index_value_index do append(&remaining, value)
	}
	if len(remaining) == 0 {
		delete_key(&temporary, definition.index)
	} else {
		temporary[definition.index] = remaining
	}
	active_context, type_context, context_error := compact_resolve_object_context(state, ctx, definition, temporary)
	if context_error != .None do return context_error
	return compact_write_node_resolved(builder, state, &active_context, &type_context, temporary, policy)
}

// compact_write_id_map folds node identifiers into an @id-container map. The
// node's @id is represented by the map key and therefore must not be repeated
// in the map value. Generated blank-node identifiers have no stable external
// spelling, so they use @none unless a source-specific recovery can prove one.
@(private) compact_source_id_map_key :: proc(state: ^State, predicate: string, target: json.Object) -> (string, bool, Compact_Error) {
	signature, signature_error := compact_graph_fragment_signature(json.Value(target))
	if signature_error != .None do return "", false, signature_error
	defer delete(signature)
	key := ""
	for annotation in state.compact_source_id_map_annotations {
		if !compact_annotation_predicate_matches(annotation.predicate, predicate, predicate, predicate) || annotation.target_signature != signature do continue
		if len(key) > 0 && key != annotation.key do return "", false, .None
		key = annotation.key
	}
	return key, len(key) > 0, .None
}

@(private) compact_write_id_map :: proc(builder: ^strings.Builder, state: ^State, ctx: ^Context, values: json.Array, definition: Term_Definition, policy: Compact_Array_Policy) -> (bool, Compact_Error) {
	if !definition.container_id || definition.container_graph || len(values) == 0 do return false, .None
	groups := make([dynamic]Compact_Annotated_Index_Group)
	defer destroy_compact_annotated_index_groups(&groups)
	for value in values {
		reference, valid_reference := object_from_value(value)
		identifier_value, has_identifier := object_value(reference, "@id")
		identifier, valid_identifier := string_value(identifier_value)
		if !valid_reference || !has_identifier || !valid_identifier do return false, .None
		target := reference
		if indexed, found_target := state.compact_nodes[identifier]; found_target do target = indexed
		key := compact_keyword(ctx, "@none")
		if !strings.has_prefix(identifier, "_:") {
			compacted, compact_error := compact_iri(state, ctx, identifier, false)
			if compact_error != .None do return false, compact_error
			key = compacted
		} else if source_key, found_source_key, source_key_error := compact_source_id_map_key(state, definition.id, target); source_key_error != .None {
			return false, source_key_error
		} else if found_source_key {
			key = source_key
		}
		group_index := -1
		for group, index in groups do if group.key == key { group_index = index; break }
		if group_index < 0 {
			append(&groups, Compact_Annotated_Index_Group{key = key, values = make([dynamic]json.Value)})
			group_index = len(groups) - 1
		}
		append(&groups[group_index].values, value)
	}
	strings.write_byte(builder, '{')
	for group, group_index in groups {
		if group_index > 0 do strings.write_string(builder, ", ")
		write_json_string(builder, group.key)
		strings.write_string(builder, ": ")
		as_array := definition.container_set || len(group.values) > 1
		if as_array do strings.write_byte(builder, '[')
		for value, value_index in group.values {
			if value_index > 0 do strings.write_string(builder, ", ")
			reference, _ := object_from_value(value)
			identifier_value, _ := object_value(reference, "@id")
			identifier, _ := string_value(identifier_value)
			target := reference
			if indexed, found_target := state.compact_nodes[identifier]; found_target do target = indexed
			temporary := make(json.Object)
			for target_key, target_value in target {
				if target_key != "@id" do temporary[target_key] = target_value
			}
			state.compacted_index_nodes[identifier] = true
			write_error := compact_write_referenced_node(builder, state, ctx, temporary, policy)
			delete(temporary)
			if write_error != .None do return false, write_error
		}
		if as_array do strings.write_byte(builder, ']')
	}
	strings.write_byte(builder, '}')
	return true, .None
}

@(private) compact_source_type_map_key :: proc(state: ^State, predicate: string, target: json.Object) -> (string, bool, Compact_Error) {
	signature, signature_error := compact_type_map_target_signature(json.Value(target))
	if signature_error != .None do return "", false, signature_error
	defer delete(signature)
	key := ""
	for annotation in state.compact_source_type_map_annotations {
		if !compact_annotation_predicate_matches(annotation.predicate, predicate, predicate, predicate) || annotation.target_signature != signature do continue
		if len(key) > 0 && key != annotation.key do return "", false, .None
		key = annotation.key
	}
	return key, len(key) > 0, .None
}

@(private) compact_source_type_map_remaining_key :: proc(state: ^State, predicate: string, target: json.Object) -> (string, bool, Compact_Error) {
	signature, signature_error := compact_type_map_target_signature(json.Value(target))
	if signature_error != .None do return "", false, signature_error
	defer delete(signature)
	key := ""
	for annotation in state.compact_source_type_map_annotations {
		if !compact_annotation_predicate_matches(annotation.predicate, predicate, predicate, predicate) || annotation.target_signature != signature || len(annotation.remaining_key) == 0 do continue
		if len(key) > 0 && key != annotation.remaining_key do return "", false, .None
		key = annotation.remaining_key
	}
	return key, len(key) > 0, .None
}

// compact_write_type_map folds a single RDF type into the map key. Blank RDF
// type identifiers are serializer-local, so their source spelling is restored
// only after an id- and type-free target signature has a unique match.
@(private) compact_write_type_map :: proc(builder: ^strings.Builder, state: ^State, ctx: ^Context, values: json.Array, definition: Term_Definition, policy: Compact_Array_Policy) -> (bool, Compact_Error) {
	if !definition.container_type || len(values) == 0 do return false, .None
	groups := make([dynamic]Compact_Annotated_Index_Group)
	defer destroy_compact_annotated_index_groups(&groups)
	for value in values {
		reference, valid_reference := object_from_value(value)
		identifier_value, has_identifier := object_value(reference, "@id")
		identifier, valid_identifier := string_value(identifier_value)
		if !valid_reference || !has_identifier || !valid_identifier do return false, .None
		target := reference
		if indexed, found_target := state.compact_nodes[identifier]; found_target do target = indexed
		type_id, _, found_type, type_error := compact_type_map_type(target)
		if type_error != .None do return false, type_error
		source_key, found_source_key, source_key_error := compact_source_type_map_key(state, definition.id, target)
		if source_key_error != .None do return false, source_key_error
		key := ""
		if found_source_key {
			if strings.has_prefix(source_key, "_:") {
				key = source_key
			} else {
				compacted, compact_error := compact_iri(state, ctx, source_key, true)
				if compact_error != .None do return false, compact_error
				key = compacted
			}
		} else if !found_type {
			key = compact_keyword(ctx, "@none")
		} else if strings.has_prefix(type_id, "_:") {
			return false, .None
		} else {
			compacted, compact_error := compact_iri(state, ctx, type_id, true)
			if compact_error != .None do return false, compact_error
			key = compacted
		}
		group_index := -1
		for group, index in groups do if group.key == key { group_index = index; break }
		if group_index < 0 {
			append(&groups, Compact_Annotated_Index_Group{key = key, values = make([dynamic]json.Value)})
			group_index = len(groups) - 1
		}
		append(&groups[group_index].values, value)
	}
	strings.write_byte(builder, '{')
	for group, group_index in groups {
		if group_index > 0 do strings.write_string(builder, ", ")
		write_json_string(builder, group.key)
		strings.write_string(builder, ": ")
		as_array := definition.container_set || len(group.values) > 1
		if as_array do strings.write_byte(builder, '[')
		for value, value_index in group.values {
			if value_index > 0 do strings.write_string(builder, ", ")
			reference, _ := object_from_value(value)
			identifier_value, _ := object_value(reference, "@id")
			identifier, _ := string_value(identifier_value)
			target := reference
			if indexed, found_target := state.compact_nodes[identifier]; found_target do target = indexed
			_, type_key, found_type, type_error := compact_type_map_type(target)
			if type_error != .None do return false, type_error
			source_key, found_source_key, source_key_error := compact_source_type_map_key(state, definition.id, target)
			if source_key_error != .None do return false, source_key_error
			temporary := make(json.Object)
			remaining_types := make(json.Array)
			for target_key, target_value in target {
				if target_key != "@id" && (!found_type || target_key != type_key) do temporary[target_key] = target_value
			}
			if found_type {
				types_value, has_types := object_value(target, type_key)
				types, valid_types := array_from_value(types_value)
				if !has_types || !valid_types || len(types) == 0 { delete(temporary); delete(remaining_types); return false, .Invalid_Expanded_JSON }
				remove_index := 0
				if found_source_key && !strings.has_prefix(source_key, "_:") {
					matched_source_type := false
					for type_value, type_index in types {
						type_identifier, identifier_error := compact_type_map_value_identifier(type_key, type_value)
						if identifier_error != .None { delete(temporary); delete(remaining_types); return false, identifier_error }
						if type_identifier == source_key {
							remove_index = type_index
							matched_source_type = true
							break
						}
					}
					if !matched_source_type { delete(temporary); delete(remaining_types); return false, .Invalid_Expanded_JSON }
				}
				for type_value, type_index in types {
					if type_index != remove_index do append(&remaining_types, type_value)
				}
				if len(remaining_types) > 0 do temporary[type_key] = remaining_types
			}
			state.compacted_index_nodes[identifier] = true
			entry_context, entry_type_context, context_error := compact_resolve_object_context(state, ctx, {}, target, false)
			if context_error != .None { delete(temporary); delete(remaining_types); return false, context_error }
			remaining_source_key, has_remaining_source_key, remaining_source_key_error := compact_source_type_map_remaining_key(state, definition.id, target)
			if remaining_source_key_error != .None { delete(temporary); delete(remaining_types); return false, remaining_source_key_error }
			remaining_runtime := ""
			if has_remaining_source_key && strings.has_prefix(remaining_source_key, "_:") && len(remaining_types) == 1 {
				remaining_runtime, type_error = compact_type_map_value_identifier(type_key, remaining_types[0])
				if type_error != .None { delete(temporary); delete(remaining_types); return false, type_error }
			}
			previous_remaining_runtime := state.compact_type_map_remaining_runtime
			previous_remaining_source := state.compact_type_map_remaining_source
			state.compact_type_map_remaining_runtime = remaining_runtime
			state.compact_type_map_remaining_source = remaining_source_key
			write_error: Compact_Error
			if len(temporary) == 0 {
				id_value, has_id := object_value(target, "@id")
				if !has_id { delete(temporary); delete(remaining_types); return false, .Invalid_Expanded_JSON }
				write_error = compact_write_identifier(builder, state, &entry_context, id_value, definition.type == "@vocab", definition.type != "@id")
			} else {
				write_error = compact_write_node_resolved(builder, state, &entry_context, &entry_type_context, temporary, policy)
			}
			state.compact_type_map_remaining_runtime = previous_remaining_runtime
			state.compact_type_map_remaining_source = previous_remaining_source
			delete(temporary)
			delete(remaining_types)
			if write_error != .None do return false, write_error
		}
		if as_array do strings.write_byte(builder, ']')
	}
	strings.write_byte(builder, '}')
	return true, .None
}

// compact_write_property_index_map turns a custom @index property's RDF value
// back into a map key, retaining any additional values of that property on the
// compacted node. This mirrors process_index_map without fabricating ordinary
// RDF-invisible @index annotations.
@(private) compact_write_property_index_map :: proc(builder: ^strings.Builder, state: ^State, ctx: ^Context, values: json.Array, definition: Term_Definition, policy: Compact_Array_Policy) -> (bool, Compact_Error) {
	if !definition.has_index || definition.index == "@index" do return false, .None
	groups := make([dynamic]Compact_Property_Index_Group)
	defer destroy_compact_property_index_groups(&groups)
	for value in values {
		object, object_valid := object_from_value(value)
		if !object_valid do return false, .None
		target := object
		if id_value, has_id := object_value(object, "@id"); has_id {
			identifier, identifier_valid := string_value(id_value)
			if !identifier_valid do return false, .Invalid_Expanded_JSON
			if indexed, found := state.compact_nodes[identifier]; found do target = indexed
		}
		index_value_index := -1
		key := compact_keyword(ctx, "@none")
		if index_values_value, found_index_values := object_value(target, definition.index); found_index_values {
			index_values, valid_index_values := array_from_value(index_values_value)
			if !valid_index_values do return false, .Invalid_Expanded_JSON
			for index := len(index_values) - 1; index >= 0; index -= 1 {
				candidate, valid_key, key_error := compact_property_index_key(state, ctx, definition, index_values[index])
				if key_error != .None do return false, key_error
				if valid_key {
					key = candidate
					index_value_index = index
					break
				}
			}
		}
		group_index := -1
		for group, index in groups do if group.key == key { group_index = index; break }
		if group_index < 0 {
			append(&groups, Compact_Property_Index_Group{key = key, entries = make([dynamic]Compact_Property_Index_Entry)})
			group_index = len(groups) - 1
		}
		append(&groups[group_index].entries, Compact_Property_Index_Entry{source = value, object = target, index_value_index = index_value_index})
	}
	strings.write_byte(builder, '{')
	for group, group_index in groups {
		if group_index > 0 do strings.write_string(builder, ", ")
		write_json_string(builder, group.key)
		strings.write_string(builder, ": ")
		if policy == .Compact && len(group.entries) == 1 && !definition.container_set {
			entry := group.entries[0]
			if entry_error := compact_write_property_index_entry(builder, state, ctx, entry, definition, policy); entry_error != .None do return false, entry_error
		} else {
			strings.write_byte(builder, '[')
			for entry, entry_index in group.entries {
				if entry_index > 0 do strings.write_string(builder, ", ")
				if entry_error := compact_write_property_index_entry(builder, state, ctx, entry, definition, policy); entry_error != .None do return false, entry_error
			}
			strings.write_byte(builder, ']')
		}
	}
	strings.write_byte(builder, '}')
	return true, .None
}

// compact_write_annotated_index_map restores ordinary @index keys only when
// they were retained from the optional source document. RDF itself has no
// representation for these annotations, so a dataset-only compaction falls
// back to normal property output.
@(private) compact_write_annotated_index_value :: proc(builder: ^strings.Builder, state: ^State, ctx: ^Context, value: json.Value, definition: Term_Definition, policy: Compact_Array_Policy) -> Compact_Error {
	object, valid_object := object_from_value(value)
	identifier_value, has_identifier := object_value(object, "@id")
	identifier, valid_identifier := string_value(identifier_value)
	if valid_object && has_identifier && valid_identifier {
		if target, found := state.compact_nodes[identifier]; found {
			if strings.has_prefix(identifier, "_:") {
				temporary := make(json.Object)
				defer delete(temporary)
				for key, target_value in target do temporary[key] = target_value
				delete_key(&temporary, "@id")
				state.compacted_index_nodes[identifier] = true
				return compact_write_referenced_node(builder, state, ctx, temporary, policy)
			}
			return compact_write_referenced_node(builder, state, ctx, target, policy)
		}
	}
	return compact_write_value(builder, state, ctx, value, definition, true, policy)
}

@(private) compact_write_annotated_index_map :: proc(builder: ^strings.Builder, state: ^State, ctx: ^Context, subject: json.Object, predicate, expanded_predicate, definition_id: string, values: json.Array, definition: Term_Definition, policy: Compact_Array_Policy) -> (bool, Compact_Error) {
	subject_value, has_subject := object_value(subject, "@id")
	subject_id, valid_subject := string_value(subject_value)
	if has_subject && !valid_subject do return false, .Invalid_Expanded_JSON
	if !has_subject do subject_id = ""
	if len(state.compact_index_annotations) == 0 do return false, .None
	annotation_count := 0
	sole_index := ""
	for annotation in state.compact_index_annotations {
		if annotation.raw_none do continue
		if !compact_index_annotation_subject_matches(state, annotation.subject_id, subject_id) || !compact_annotation_predicate_matches(annotation.predicate, predicate, expanded_predicate, definition_id) do continue
		annotation_count += 1
		sole_index = annotation.index
	}
	// An anonymous indexed value has no RDF identifier. When the source has
	// exactly one annotation and the dataset has one value, its association is
	// unambiguous without relying on a generated blank-node label.
	if len(values) == 1 && annotation_count == 1 && !definition.container_set {
		strings.write_byte(builder, '{')
		write_json_string(builder, sole_index)
		strings.write_string(builder, ": ")
		if err := compact_write_annotated_index_value(builder, state, ctx, values[0], definition, policy); err != .None do return false, err
		strings.write_byte(builder, '}')
		return true, .None
	}
	groups := make([dynamic]Compact_Annotated_Index_Group)
	defer destroy_compact_annotated_index_groups(&groups)
	if compact_raw_none_index_annotation_count(state, subject_id, predicate, expanded_predicate, definition_id) > 0 {
		for value in values {
			object, valid_object := object_from_value(value)
			if !valid_object do return false, .None
			target_value, has_target := object_value(object, "@id")
			target_id, valid_target := string_value(target_value)
			if has_target && !valid_target do return false, .Invalid_Expanded_JSON
			if !has_target do target_id = ""
			target := object
			if has_target {
				if indexed, found := state.compact_nodes[target_id]; found do target = indexed
			}
			index, found_index, index_error := compact_index_annotation(state, ctx, subject_id, predicate, expanded_predicate, definition_id, target_id, target)
			if index_error != .None do return false, index_error
			if !found_index do index = compact_keyword(ctx, "@none")
			group_index := -1
			for group, candidate_index in groups do if group.key == index { group_index = candidate_index; break }
			if group_index < 0 {
				append(&groups, Compact_Annotated_Index_Group{key = index, values = make([dynamic]json.Value)})
				group_index = len(groups) - 1
			}
			append(&groups[group_index].values, value)
		}
		strings.write_byte(builder, '{')
		for group, group_index in groups {
			if group_index > 0 do strings.write_string(builder, ", ")
			write_json_string(builder, group.key)
			strings.write_string(builder, ": ")
			if policy == .Compact && len(group.values) == 1 && !definition.container_set {
				if err := compact_write_annotated_index_value(builder, state, ctx, group.values[0], definition, policy); err != .None do return false, err
			} else {
				strings.write_byte(builder, '[')
				for value, value_index in group.values {
					if value_index > 0 do strings.write_string(builder, ", ")
					if err := compact_write_annotated_index_value(builder, state, ctx, value, definition, policy); err != .None do return false, err
				}
				strings.write_byte(builder, ']')
			}
		}
		strings.write_byte(builder, '}')
		return true, .None
	}
	// Do not fabricate a map for a partially annotated property. Every RDF
	// value must have a corresponding source annotation before it is safe to
	// use the annotation order and multiplicity below.
	for value in values {
		object, valid_object := object_from_value(value)
		if !valid_object do return false, .None
		target_value, has_target := object_value(object, "@id")
		target_id, valid_target := string_value(target_value)
		if has_target && !valid_target do return false, .Invalid_Expanded_JSON
		if !has_target do target_id = ""
		target := object
		if has_target {
			if indexed, found := state.compact_nodes[target_id]; found do target = indexed
		}
		index, found_index, index_error := compact_index_annotation(state, ctx, subject_id, predicate, expanded_predicate, definition_id, target_id, target)
		if index_error != .None do return false, index_error
		if !found_index do return false, .None
	}
	for annotation in state.compact_index_annotations {
		if annotation.raw_none do continue
		if !compact_index_annotation_subject_matches(state, annotation.subject_id, subject_id) || !compact_annotation_predicate_matches(annotation.predicate, predicate, expanded_predicate, definition_id) do continue
		matched := false
		for value in values {
			object, valid_object := object_from_value(value)
			if !valid_object do continue
			identifier_value, has_identifier := object_value(object, "@id")
			identifier, valid_identifier := string_value(identifier_value)
			if has_identifier && !valid_identifier do return false, .Invalid_Expanded_JSON
			if !has_identifier do identifier = ""
			target := object
			if has_identifier {
				if indexed, found := state.compact_nodes[identifier]; found do target = indexed
			}
			signature, signature_error := compact_index_target_signature(ctx, target)
			if signature_error != .None do return false, signature_error
			matches := (len(annotation.target_id) > 0 && has_identifier && annotation.target_id == identifier) || (len(annotation.target_id) == 0 && annotation.target_signature == signature)
			delete(signature)
			if !matches do continue
			group_index := -1
			for group, candidate_index in groups do if group.key == annotation.index { group_index = candidate_index; break }
			if group_index < 0 {
				append(&groups, Compact_Annotated_Index_Group{key = annotation.index, values = make([dynamic]json.Value)})
				group_index = len(groups) - 1
			}
			append(&groups[group_index].values, value)
			matched = true
			break
		}
		if !matched do return false, .None
	}
	strings.write_byte(builder, '{')
	for group, group_index in groups {
		if group_index > 0 do strings.write_string(builder, ", ")
		write_json_string(builder, group.key)
		strings.write_string(builder, ": ")
		if policy == .Compact && len(group.values) == 1 && !definition.container_set {
			if err := compact_write_annotated_index_value(builder, state, ctx, group.values[0], definition, policy); err != .None do return false, err
		} else {
			strings.write_byte(builder, '[')
			for value, value_index in group.values {
				if value_index > 0 do strings.write_string(builder, ", ")
				if err := compact_write_annotated_index_value(builder, state, ctx, value, definition, policy); err != .None do return false, err
			}
			strings.write_byte(builder, ']')
		}
	}
	strings.write_byte(builder, '}')
	return true, .None
}

// compact_write_source_graph_index_map joins graph values into their source
// map only after every graph reference has a recovered key. Repeated source
// keys are retained as grouped arrays; RDF-only input cannot gain this shape.
@(private) compact_write_source_graph_index_map :: proc(builder: ^strings.Builder, state: ^State, ctx: ^Context, values: json.Array, definition: Term_Definition, policy: Compact_Array_Policy) -> (bool, Compact_Error) {
	if len(values) == 0 do return false, .None
	groups := make([dynamic]Compact_Annotated_Index_Group)
	defer destroy_compact_annotated_index_groups(&groups)
	for value in values {
		reference, valid_reference := object_from_value(value)
		reference_id_value, has_reference_id := object_value(reference, "@id")
		reference_id, valid_reference_id := string_value(reference_id_value)
		if !valid_reference || !has_reference_id || !valid_reference_id do return false, .None
		key, keyword_none, found_key := compact_source_graph_map_key(state, reference_id)
		if !found_key do return false, .None
		if keyword_none && len(values) > 1 do return false, .None
		target, found_target := state.compact_nodes[reference_id]
		if !found_target do return false, .None
		_, has_graph := object_value(target, "@graph")
		if !has_graph do return false, .None
		group_index := -1
		for group, candidate_index in groups do if group.key == key { group_index = candidate_index; break }
		if group_index < 0 {
			append(&groups, Compact_Annotated_Index_Group{key = key, values = make([dynamic]json.Value)})
			group_index = len(groups) - 1
		}
		append(&groups[group_index].values, value)
	}
	strings.write_byte(builder, '{')
	for group, group_index in groups {
		if group_index > 0 do strings.write_string(builder, ", ")
		first_reference, _ := object_from_value(group.values[0])
		first_identifier_value, _ := object_value(first_reference, "@id")
		first_identifier, _ := string_value(first_identifier_value)
		_, keyword_none, _ := compact_source_graph_map_key(state, first_identifier)
		write_json_string(builder, keyword_none ? compact_keyword(ctx, "@none") : group.key)
		strings.write_string(builder, ": ")
		as_array := definition.container_set || len(group.values) > 1
		if as_array do strings.write_byte(builder, '[')
		for value, value_index in group.values {
			if value_index > 0 do strings.write_string(builder, ", ")
			reference, _ := object_from_value(value)
			reference_id_value, _ := object_value(reference, "@id")
			reference_id, _ := string_value(reference_id_value)
			target := state.compact_nodes[reference_id]
			graph_value, _ := object_value(target, "@graph")
			state.compacted_graph_nodes[reference_id] = true
			fragment_handled, fragment_error := compact_write_source_graph_fragments(builder, state, ctx, reference_id, graph_value, policy)
			if fragment_error != .None do return false, fragment_error
			if fragment_handled do continue
			if graph_error := compact_write_graph_contents(builder, state, ctx, graph_value, policy); graph_error != .None do return false, graph_error
		}
		if as_array do strings.write_byte(builder, ']')
	}
	strings.write_byte(builder, '}')
	return true, .None
}

// compact_write_source_graph_fragments writes the individual source graph
// occurrences that were proven to partition a merged named RDF graph.
@(private) compact_write_source_graph_fragments :: proc(builder: ^strings.Builder, state: ^State, ctx: ^Context, graph_id: string, graph_value: json.Value, policy: Compact_Array_Policy) -> (bool, Compact_Error) {
	predicate, has_predicate := compact_source_graph_fragment_predicate(state, graph_id)
	if !has_predicate || compact_source_graph_fragment_count(state, predicate, graph_id) <= 1 do return false, .None
	matches, match_error := compact_source_graph_fragments_match(state, predicate, graph_id, graph_value)
	if match_error != .None do return false, match_error
	if !matches do return false, .None
	items, valid_items := array_from_value(graph_value)
	if !valid_items do return false, .Invalid_Expanded_JSON
	used := make([dynamic]bool)
	defer delete(used)
	for _ in items do append(&used, false)
	strings.write_byte(builder, '[')
	written := 0
	for annotation in state.compact_source_graph_id_annotations {
		if annotation.predicate != predicate || annotation.target_id != graph_id || len(annotation.graph_fragment_signature) == 0 do continue
		for item, item_index in items {
			if used[item_index] do continue
			signature, signature_error := compact_graph_fragment_signature(item)
			if signature_error != .None do return false, signature_error
			equal := signature == annotation.graph_fragment_signature
			delete(signature)
			if !equal do continue
			if written > 0 do strings.write_string(builder, ", ")
			node, valid_node := object_from_value(item)
			if !valid_node do return false, .Invalid_Expanded_JSON
			if node_error := compact_write_graph_node(builder, state, ctx, node, policy); node_error != .None do return false, node_error
			used[item_index] = true
			written += 1
			break
		}
	}
	strings.write_byte(builder, ']')
	return true, .None
}

@(private) compact_write_graph_node :: proc(builder: ^strings.Builder, state: ^State, ctx: ^Context, node: json.Object, policy: Compact_Array_Policy) -> Compact_Error {
	if id_value, has_id := object_value(node, "@id"); has_id {
		identifier, valid_identifier := string_value(id_value)
		if !valid_identifier do return .Invalid_Expanded_JSON
		if strings.has_prefix(identifier, "_:") {
			temporary := make(json.Object)
			for key, value in node do temporary[key] = value
			delete_key(&temporary, "@id")
			// A graph member's generated blank identifier is not part of the
			// JSON-LD graph value. Keep this marker through the nested write so
			// list/value recovery cannot reintroduce it from the canonical node.
			previous_omitted_id := state.compact_omit_singleton_blank_id
			state.compact_omit_singleton_blank_id = identifier
			write_error := compact_write_node(builder, state, ctx, temporary, policy)
			state.compact_omit_singleton_blank_id = previous_omitted_id
			delete(temporary)
			return write_error
		}
		// Serialization can split a named graph node from the node occurrence
		// that carries its own nested @graph. Resolve that richer canonical node
		// before compacting a graph member so nested graph structure is retained.
		_, has_graph := object_value(node, "@graph")
		if !has_graph {
			if resolved, found := state.compact_nodes[identifier]; found {
				_, resolved_has_graph := object_value(resolved, "@graph")
				if resolved_has_graph {
					// The graph occurrence may hold ordinary properties while the
					// canonical top-level occurrence holds @graph. Merge only these
					// two representations of the same named node before writing it.
					merged := make(json.Object)
					defer delete(merged)
					for key, value in resolved do merged[key] = value
					for key, value in node do merged[key] = value
					return compact_write_node(builder, state, ctx, merged, policy)
				}
			}
		}
	}
	return compact_write_node(builder, state, ctx, node, policy)
}

@(private) compact_value_mentions_identifier :: proc(value: json.Value, identifier: string) -> bool {
	#partial switch actual in value {
	case json.Array:
		for item in actual do if compact_value_mentions_identifier(item, identifier) do return true
	case json.Object:
		id_value, has_id := object_value(actual, "@id")
		id, valid_id := string_value(id_value)
		if has_id && valid_id && id == identifier do return true
		for key, item in actual {
			if key == "@id" do continue
			if compact_value_mentions_identifier(item, identifier) do return true
		}
	}
	return false
}

// A top-level graph member may omit its generated blank identifier only when
// no other top-level member refers to it. Removing an identifier that anchors
// an edge would split the RDF graph during a compact/expand round trip.
@(private) compact_top_level_node_is_referenced :: proc(nodes: json.Array, identifier: string) -> bool {
	for node_value in nodes {
		node, valid_node := object_from_value(node_value)
		if !valid_node do continue
		for key, value in node {
			if key == "@id" do continue
			if compact_value_mentions_identifier(value, identifier) do return true
		}
	}
	return false
}

@(private) compact_value_mentions_top_level_node :: proc(value: json.Value, nodes: json.Array) -> bool {
	#partial switch actual in value {
	case json.Array:
		for item in actual do if compact_value_mentions_top_level_node(item, nodes) do return true
	case json.Object:
		id_value, has_id := object_value(actual, "@id")
		identifier, valid_identifier := string_value(id_value)
		if has_id && valid_identifier {
			for node_value in nodes {
				node, valid_node := object_from_value(node_value)
				node_id_value, node_has_id := object_value(node, "@id")
				node_id, node_valid_id := string_value(node_id_value)
				if valid_node && node_has_id && node_valid_id && node_id == identifier do return true
			}
		}
		for key, item in actual {
			if key == "@id" do continue
			if compact_value_mentions_top_level_node(item, nodes) do return true
		}
	}
	return false
}

@(private) compact_top_level_node_references_top_level_node :: proc(node: json.Object, nodes: json.Array) -> bool {
	for key, value in node {
		if key == "@id" do continue
		if compact_value_mentions_top_level_node(value, nodes) do return true
	}
	return false
}

@(private) compact_write_graph_contents :: proc(builder: ^strings.Builder, state: ^State, ctx: ^Context, graph_value: json.Value, policy: Compact_Array_Policy) -> Compact_Error {
	items, valid_items := array_from_value(graph_value)
	if !valid_items do return .Invalid_Expanded_JSON
	if policy == .Compact && len(items) == 1 {
		node, valid_node := object_from_value(items[0])
		if !valid_node do return .Invalid_Expanded_JSON
		return compact_write_graph_node(builder, state, ctx, node, policy)
	}
	strings.write_byte(builder, '[')
	for item, index in items {
		if index > 0 do strings.write_string(builder, ", ")
		node, valid_node := object_from_value(item)
		if !valid_node do return .Invalid_Expanded_JSON
		if write_error := compact_write_graph_node(builder, state, ctx, node, policy); write_error != .None do return write_error
	}
	strings.write_byte(builder, ']')
	return .None
}

// A graph container owns the graph node referenced by its property. Anonymous
// graph names are an RDF implementation detail and compact directly to their
// contents; named graph identifiers remain visible with an @graph wrapper.
@(private) compact_write_graph_container :: proc(builder: ^strings.Builder, state: ^State, ctx: ^Context, target: json.Object, policy: Compact_Array_Policy, force_set: bool = false) -> Compact_Error {
	graph_value, has_graph := object_value(target, "@graph")
	if !has_graph do return .Invalid_Expanded_JSON
	id_value, has_id := object_value(target, "@id")
	identifier, valid_identifier := string_value(id_value)
	if has_id && valid_identifier do state.compacted_graph_nodes[identifier] = true
	has_named_id := has_id && valid_identifier && !strings.has_prefix(identifier, "_:")
	if index, keyword_none, has_index := compact_source_graph_map_key(state, identifier); has_index {
		strings.write_byte(builder, '{')
		write_json_string(builder, keyword_none ? compact_keyword(ctx, "@none") : index)
		strings.write_string(builder, ": ")
		if force_set do strings.write_byte(builder, '[')
		if graph_error := compact_write_graph_contents(builder, state, ctx, graph_value, policy); graph_error != .None do return graph_error
		if force_set do strings.write_byte(builder, ']')
		strings.write_byte(builder, '}')
		return .None
	}
	if !has_named_id {
		items, valid_items := array_from_value(graph_value)
		if !valid_items do return .Invalid_Expanded_JSON
		// A source-recovered anonymous graph with several node objects is
		// compacted as @included. A bare array would instead denote several
		// property values and loses the graph-container boundary.
		if state.compact_source_graph_nodes[identifier] && policy == .Compact && len(items) > 1 {
			if force_set do strings.write_byte(builder, '[')
			strings.write_byte(builder, '{')
			write_json_string(builder, compact_keyword(ctx, "@included"))
			strings.write_string(builder, ": ")
			if graph_error := compact_write_graph_contents(builder, state, ctx, graph_value, policy); graph_error != .None do return graph_error
			strings.write_byte(builder, '}')
			if force_set do strings.write_byte(builder, ']')
			return .None
		}
		if state.compact_source_graph_nodes[identifier] && force_set {
			strings.write_byte(builder, '[')
			if graph_error := compact_write_graph_contents(builder, state, ctx, graph_value, policy); graph_error != .None do return graph_error
			strings.write_byte(builder, ']')
			return .None
		}
		return compact_write_graph_contents(builder, state, ctx, graph_value, policy)
	}
	if index, has_index := compact_source_named_graph_index(state, identifier); has_index {
		strings.write_byte(builder, '{')
		write_json_string(builder, compact_keyword(ctx, "@id"))
		strings.write_string(builder, ": ")
		if id_error := compact_write_identifier(builder, state, ctx, id_value, false); id_error != .None do return id_error
		strings.write_string(builder, ", ")
		write_json_string(builder, compact_keyword(ctx, "@index"))
		strings.write_string(builder, ": ")
		write_json_string(builder, index)
		strings.write_string(builder, ", ")
		write_json_string(builder, compact_keyword(ctx, "@graph"))
		strings.write_string(builder, ": ")
		if graph_error := compact_write_graph_contents(builder, state, ctx, graph_value, policy); graph_error != .None do return graph_error
		strings.write_byte(builder, '}')
		return .None
	}
	strings.write_byte(builder, '{')
	write_json_string(builder, compact_keyword(ctx, "@id"))
	strings.write_string(builder, ": ")
	if id_error := compact_write_identifier(builder, state, ctx, id_value, false); id_error != .None do return id_error
	strings.write_string(builder, ", ")
	write_json_string(builder, compact_keyword(ctx, "@graph"))
	strings.write_string(builder, ": ")
	if graph_error := compact_write_graph_contents(builder, state, ctx, graph_value, policy); graph_error != .None do return graph_error
	strings.write_byte(builder, '}')
	return .None
}

@(private) compact_definition_needs_context :: proc(definition: Term_Definition) -> bool {
	return definition.has_local_context || len(definition.type) > 0 || definition.has_language || definition.language_null || definition.has_direction || definition.direction_null
}

@(private) compact_reference_needs_inline :: proc(ctx: ^Context, definition: Term_Definition, target: json.Object) -> bool {
	if definition.container_graph do return false
	if definition.has_local_context do return true
	if types, has_types := object_value(target, "@type"); has_types {
		items, is_array := array_from_value(types)
		count := is_array ? len(items) : 1
		for index in 0..<count {
			type_id, valid := string_value(is_array ? items[index] : types)
			if !valid do continue
			for _, type_definition in ctx.terms do if type_definition.id == type_id && type_definition.has_local_context do return true
		}
	}
	for property in target {
		if is_keyword(property) do continue
		for _, property_definition in ctx.terms {
			if property_definition.id == property && compact_definition_needs_context(property_definition) do return true
		}
	}
	return false
}

@(private) compact_write_referenced_node :: proc(builder: ^strings.Builder, state: ^State, inherited: ^Context, object: json.Object, policy: Compact_Array_Policy) -> Compact_Error {
	active_context, type_context, context_error := compact_resolve_object_context(state, inherited, {}, object, false)
	if context_error != .None do return context_error
	return compact_write_node_resolved(builder, state, &active_context, &type_context, object, policy)
}

@(private) compact_write_value_with_inherited_context :: proc(builder: ^strings.Builder, state: ^State, ctx, inline_inherited: ^Context, value: json.Value, definition: Term_Definition, has_definition: bool, policy: Compact_Array_Policy) -> Compact_Error {
	object, is_object := object_from_value(value)
	if !is_object do return .Invalid_Expanded_JSON
	active_context, type_context, context_error := compact_resolve_object_context(state, ctx, definition, object)
	if context_error != .None do return context_error
	resolved := &active_context
	if id, has_id := object_value(object, "@id"); has_id {
		identifier, identifier_valid := string_value(id)
		if !identifier_valid do return .Invalid_Expanded_JSON
		if target, found := state.compact_nodes[identifier]; found && state.compact_source_graph_boundary_nodes[identifier] {
			graph_value, has_graph := object_value(target, "@graph")
			if !has_graph do return .Invalid_Expanded_JSON
			state.compacted_graph_nodes[identifier] = true
			strings.write_byte(builder, '{')
			write_json_string(builder, compact_keyword(resolved, "@graph"))
			strings.write_string(builder, ": ")
			if graph_error := compact_write_graph_contents(builder, state, resolved, graph_value, policy); graph_error != .None do return graph_error
			strings.write_byte(builder, '}')
			return .None
		}
		if has_definition && definition.container_graph {
			if target, found := state.compact_nodes[identifier]; found {
				_, has_graph := object_value(target, "@graph")
				target_id, has_target_id := object_value(target, "@id")
				target_identifier, valid_target_id := string_value(target_id)
				has_named_id := has_target_id && valid_target_id && !strings.has_prefix(target_identifier, "_:")
				_, _, has_source_graph_index := compact_source_graph_map_key(state, identifier)
				has_source_graph_recovery := state.compact_source_graph_nodes[identifier] || has_source_graph_index
				if has_graph && (!definition.container_set || has_source_graph_recovery) && (!definition.container_id || has_source_graph_index) && (has_named_id || definition.has_local_context || has_source_graph_recovery) do return compact_write_graph_container(builder, state, resolved, target, policy, state.compact_source_graph_set_value && has_source_graph_recovery)
			}
		}
		source_named_inline := state.compact_source_inline_named_nodes[identifier] && !state.compact_source_top_level_named_nodes[identifier]
		source_embedded_blank := state.compact_writing_source_root && strings.has_prefix(identifier, "_:")
		source_embedded_named := state.compact_writing_source_root && !strings.has_prefix(identifier, "_:")
		if target, found := state.compact_nodes[identifier]; found && !state.compacting_nodes[identifier] && (compact_reference_needs_inline(resolved, definition, target) || source_named_inline || source_embedded_blank || (source_embedded_named && len(target) > 1)) {
			state.compacting_nodes[identifier] = true
			defer delete_key(&state.compacting_nodes, identifier)
			inherited := resolved
			previous_inherited: Context
			if inline_inherited != nil && !definition.has_local_context && !resolved.explicit_propagating do inherited = inline_inherited
			if !definition.has_local_context && resolved.explicit_non_propagating {
				previous_inherited = previous_context(resolved)
				inherited = &previous_inherited
			}
			if strings.has_prefix(identifier, "_:") && state.compact_writing_source_root {
				temporary := make(json.Object)
				for target_key, target_value in target do temporary[target_key] = target_value
				previous_omitted_id := state.compact_omit_singleton_blank_id
				state.compact_omit_singleton_blank_id = identifier
				write_error := compact_write_referenced_node(builder, state, inherited, temporary, policy)
				state.compact_omit_singleton_blank_id = previous_omitted_id
				delete(temporary)
				return write_error
			}
			return compact_write_referenced_node(builder, state, inherited, target, policy)
		}
		if len(object) == 1 && has_definition && !definition.container_graph && (definition.type == "@id" || definition.type == "@vocab") do return compact_write_identifier(builder, state, resolved, id, definition.type == "@vocab", definition.type != "@id")
		strings.write_byte(builder, '{')
		write_json_string(builder, compact_keyword(resolved, "@id"))
		strings.write_string(builder, ": ")
		if err := compact_write_identifier(builder, state, resolved, id, false); err != .None do return err
		strings.write_byte(builder, '}')
		return .None
	}
	if list, has_list := object_value(object, "@list"); has_list {
		strings.write_byte(builder, '{')
		write_json_string(builder, compact_keyword(resolved, "@list"))
		strings.write_string(builder, ": ")
		if err := compact_write_list(builder, state, resolved, list, definition, has_definition, policy); err != .None do return err
		strings.write_byte(builder, '}')
		return .None
	}
	if _, has_value := object_value(object, "@value"); has_value do return compact_write_value_object(builder, state, resolved, object, definition, has_definition)
	return compact_write_node_resolved(builder, state, resolved, &type_context, object, policy)
}

@(private) compact_write_value :: proc(builder: ^strings.Builder, state: ^State, ctx: ^Context, value: json.Value, definition: Term_Definition, has_definition: bool, policy: Compact_Array_Policy) -> Compact_Error {
	return compact_write_value_with_inherited_context(builder, state, ctx, nil, value, definition, has_definition, policy)
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
		allow_document_containers = context_options.processing_mode != .Json_LD_1_0,
		allow_direction = context_options.processing_mode != .Json_LD_1_0,
		legacy_prefixes = context_options.processing_mode == .Json_LD_1_0,
		compact_source_graph_predicates = make(map[string]bool),
		compact_source_graph_boundary_predicates = make(map[string]bool),
		compact_source_inline_named_nodes = make(map[string]bool),
		compact_source_top_level_named_nodes = make(map[string]bool),
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
	if annotation_error := compact_collect_source_index_annotations(&state, &ctx, options.source_document, options); annotation_error != .None do return annotation_error
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
	if len(nodes) == 0 {
		empty_context, is_empty_context := object_from_value(active_context)
		if is_empty_context && len(empty_context) == 0 {
			strings.write_string(builder, "{}\n")
			return .None
		}
	}
	state.compact_nodes = make(map[string]json.Object)
	state.compacting_nodes = make(map[string]bool)
	state.compacted_graph_nodes = make(map[string]bool)
	state.compacted_index_nodes = make(map[string]bool)
	state.compact_source_graph_nodes = make(map[string]bool)
	state.compact_source_graph_boundary_nodes = make(map[string]bool)
	for node_value in nodes {
		node, node_valid := object_from_value(node_value)
		if !node_valid do return .Invalid_Expanded_JSON
		id_value, has_id := object_value(node, "@id")
		id, id_valid := string_value(id_value)
		if has_id && id_valid do state.compact_nodes[id] = node
	}
	if named_graph_root_error := compact_mark_source_named_graph_root(&state, nodes); named_graph_root_error != .None do return named_graph_root_error
	if document_root_error := compact_mark_source_document_root(&state, nodes); document_root_error != .None do return document_root_error
	if root_graph_nodes_error := compact_mark_source_root_graph_nodes(&state, &ctx); root_graph_nodes_error != .None do return root_graph_nodes_error
	if graph_boundaries_error := compact_mark_source_graph_boundaries(&state, nodes); graph_boundaries_error != .None do return graph_boundaries_error
	if graph_container_nodes_error := compact_mark_source_graph_container_nodes(&state, nodes); graph_container_nodes_error != .None do return graph_container_nodes_error
	if named_graph_index_root_error := compact_mark_source_named_graph_index_root(&state, nodes); named_graph_index_root_error != .None do return named_graph_index_root_error
	if graph_id_fragment_error := compact_mark_source_graph_id_fragments(&state, nodes); graph_id_fragment_error != .None do return graph_id_fragment_error
	if graph_id_root_error := compact_mark_source_graph_id_root(&state, nodes); graph_id_root_error != .None do return graph_id_root_error
	if graph_index_root_error := compact_mark_source_graph_index_root(&state, nodes); graph_index_root_error != .None do return graph_index_root_error
	if graph_root_error := compact_mark_source_graph_root(&state, nodes); graph_root_error != .None do return graph_root_error
	if len(state.compact_source_named_root_id) > 0 {
		if _, found_root := state.compact_nodes[state.compact_source_named_root_id]; found_root do state.compact_source_graph_root_id = state.compact_source_named_root_id
	}
	if reverse_error := compact_build_reverse_reference_index(&state, nodes); reverse_error != .None do return reverse_error
	if reverse_index_error := compact_mark_source_reverse_index_nodes(&state, nodes); reverse_index_error != .None do return reverse_index_error
	if included_error := compact_mark_source_included_nodes(&state, nodes); included_error != .None do return included_error
	temporary := strings.builder_make()
	defer strings.builder_destroy(&temporary)
	included_parent := strings.builder_make()
	defer strings.builder_destroy(&included_parent)
	included_parent_handled, included_parent_error := compact_write_source_included_parent(&included_parent, &state, &ctx, options.array_policy)
	if included_parent_error != .None do return included_parent_error
	if included_parent_handled {
		strings.write_string(&temporary, "{\n  \"@context\": ")
		if !compact_write_raw_json(&temporary, active_context) do return .Invalid_Context
		strings.write_string(&temporary, ",\n  ")
		included_parent_text := strings.to_string(included_parent)
		strings.write_string(&temporary, included_parent_text[1:len(included_parent_text) - 1])
		strings.write_string(&temporary, "\n}\n")
		strings.write_string(builder, strings.to_string(temporary))
		return .None
	}
	included_root := strings.builder_make()
	defer strings.builder_destroy(&included_root)
	included_handled, included_write_error := compact_write_source_included_root(&included_root, &state, &ctx, options.array_policy)
	if included_write_error != .None do return included_write_error
	if included_handled {
		strings.write_string(&temporary, "{\n  \"@context\": ")
		if !compact_write_raw_json(&temporary, active_context) do return .Invalid_Context
		strings.write_string(&temporary, ",\n  ")
		included_text := strings.to_string(included_root)
		strings.write_string(&temporary, included_text[1:len(included_text) - 1])
		strings.write_string(&temporary, "\n}\n")
		strings.write_string(builder, strings.to_string(temporary))
		return .None
	}
	json_null_root := strings.builder_make()
	defer strings.builder_destroy(&json_null_root)
	json_null_handled, json_null_error := compact_write_source_json_null_document(&json_null_root, &state, &ctx, nodes)
	if json_null_error != .None do return json_null_error
	if json_null_handled {
		strings.write_string(&temporary, "{\n  \"@context\": ")
		if !compact_write_raw_json(&temporary, active_context) do return .Invalid_Context
		strings.write_string(&temporary, ",\n  ")
		json_null_text := strings.to_string(json_null_root)
		strings.write_string(&temporary, json_null_text[1:len(json_null_text) - 1])
		strings.write_string(&temporary, "\n}\n")
		strings.write_string(builder, strings.to_string(temporary))
		return .None
	}
	reverse_root := strings.builder_make()
	defer strings.builder_destroy(&reverse_root)
	reverse_root_handled, reverse_root_error := compact_write_source_reverse_index_root(&reverse_root, &state, &ctx, options.array_policy)
	if reverse_root_error != .None do return reverse_root_error
	if reverse_root_handled {
		strings.write_string(&temporary, "{\n  \"@context\": ")
		if !compact_write_raw_json(&temporary, active_context) do return .Invalid_Context
		strings.write_string(&temporary, ",\n  ")
		reverse_root_text := strings.to_string(reverse_root)
		strings.write_string(&temporary, reverse_root_text[1:len(reverse_root_text) - 1])
		strings.write_string(&temporary, "\n}\n")
		strings.write_string(builder, strings.to_string(temporary))
		return .None
	}
	single_default_index := -1
	if len(state.compact_source_graph_root_id) > 0 && options.array_policy != .Preserve {
		for node_value, index in nodes {
			node, node_valid := object_from_value(node_value)
			if !node_valid do return .Invalid_Expanded_JSON
			id_value, has_id := object_value(node, "@id")
			identifier, valid_identifier := string_value(id_value)
			if has_id && valid_identifier && identifier == state.compact_source_graph_root_id {
				single_default_index = index
				break
			}
		}
	} else if len(nodes) == 1 && options.array_policy != .Preserve {
		node, node_valid := object_from_value(nodes[0])
		if !node_valid do return .Invalid_Expanded_JSON
		_, has_graph := object_value(node, "@graph")
		if !has_graph do single_default_index = 0
	}
	if single_default_index >= 0 {
		node_builder := strings.builder_make()
		defer strings.builder_destroy(&node_builder)
		node, _ := object_from_value(nodes[single_default_index])
		id_value, has_id := object_value(node, "@id")
		identifier, valid_identifier := string_value(id_value)
		state.compact_writing_source_root = has_id && valid_identifier && identifier == state.compact_source_graph_root_id
		// The selected document root is already being written. Mark it exactly
		// like an inline node so a child that references its parent emits an
		// @id reference instead of recursively embedding the whole root again.
		root_is_compacting := has_id && valid_identifier
		if root_is_compacting do state.compacting_nodes[identifier] = true
		omits_singleton_blank_id := false
		if has_id {
			if valid_identifier && strings.has_prefix(identifier, "_:") {
				state.compact_omit_singleton_blank_id = identifier
				omits_singleton_blank_id = true
			}
		}
		compact_error := compact_write_node(&node_builder, &state, &ctx, node, options.array_policy)
		state.compact_writing_source_root = false
		if root_is_compacting do delete_key(&state.compacting_nodes, identifier)
		if omits_singleton_blank_id do compact_clear_omitted_singleton_blank_id(&state)
		if compact_error != .None do return compact_error
		compacted_node := strings.to_string(node_builder)
		empty_context, is_empty_context := object_from_value(active_context)
		if is_empty_context && len(empty_context) == 0 {
			strings.write_string(builder, compacted_node)
			strings.write_byte(builder, '\n')
			return .None
		}
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
	empty_context, is_empty_context := object_from_value(active_context)
	strings.write_string(&temporary, "{")
	if is_empty_context && len(empty_context) == 0 {
		strings.write_string(&temporary, "\n  ")
	} else {
		strings.write_string(&temporary, "\n  \"@context\": ")
		if !compact_write_raw_json(&temporary, active_context) do return .Invalid_Context
		strings.write_string(&temporary, ",\n  ")
	}
	write_json_string(&temporary, compact_keyword(&ctx, "@graph"))
	strings.write_string(&temporary, ": [")
	written := 0
	ordered_indices := compact_source_ordered_node_indices(&state, nodes)
	defer delete(ordered_indices)
	for node_index in ordered_indices {
		node_value := nodes[node_index]
		node, node_valid := object_from_value(node_value)
		if !node_valid do return .Invalid_Expanded_JSON
		omits_preserved_root_blank_id := false
		if id_value, has_id := object_value(node, "@id"); has_id {
			identifier, valid_identifier := string_value(id_value)
			if valid_identifier && (state.compacted_graph_nodes[identifier] || state.compacted_index_nodes[identifier]) do continue
			if valid_identifier && state.compact_source_inline_named_nodes[identifier] && !state.compact_source_top_level_named_nodes[identifier] do continue
			if valid_identifier && options.array_policy == .Preserve && identifier == state.compact_source_graph_root_id && strings.has_prefix(identifier, "_:") {
				state.compact_omit_singleton_blank_id = identifier
				omits_preserved_root_blank_id = true
			}
		}
		if written > 0 do strings.write_string(&temporary, ",\n")
		strings.write_string(&temporary, "\n    ")
		write_as_graph_member := true
		if id_value, has_id := object_value(node, "@id"); has_id {
			identifier, valid_identifier := string_value(id_value)
			if valid_identifier && strings.has_prefix(identifier, "_:") && (compact_top_level_node_is_referenced(nodes, identifier) || compact_top_level_node_references_top_level_node(node, nodes)) do write_as_graph_member = false
		}
		compact_error := write_as_graph_member ? compact_write_graph_node(&temporary, &state, &ctx, node, options.array_policy) : compact_write_node(&temporary, &state, &ctx, node, options.array_policy)
		if omits_preserved_root_blank_id do compact_clear_omitted_singleton_blank_id(&state)
		if compact_error != .None do return compact_error
		written += 1
	}
	if written > 0 do strings.write_byte(&temporary, '\n')
	strings.write_string(&temporary, "  ]\n}\n")
	strings.write_string(builder, strings.to_string(temporary))
	return .None
}
