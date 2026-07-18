// Turtle serialization with explicit, streaming-safe prefix policy.
package turtle

import "core:strings"
import "core:unicode/utf8"
import rdf ".."
import ntriples "../ntriples"
import termlex "../internal/termlex"

// Prefix associates a Turtle prefix label with an absolute IRI namespace.
// An empty label represents Turtle's default prefix.
Prefix :: struct {
	label:     string,
	namespace: string,
}

// Writer_Options selects explicit compact-IRI policy. The writer chooses the
// longest matching namespace, then the first declaration on ties. An IRI that
// cannot be represented as a safe prefixed name is written as an IRIREF.
Writer_Options :: struct {
	prefixes: []Prefix,
}

// Write_Error identifies invalid RDF data or prefix configuration supplied to
// the Turtle writer.
Write_Error :: enum {
	None,
	Invalid_Prefix_Label,
	Invalid_Prefix_Namespace,
	Duplicate_Prefix,
	Invalid_Term_Kind,
	Invalid_Subject,
	Invalid_Predicate,
	Invalid_IRI,
	Invalid_Blank_Node,
	Invalid_Language_Tag,
	Invalid_UTF8,
	Unexpected_Language,
	Unexpected_Datatype,
	Missing_Literal_Datatype,
	Invalid_Language_Datatype,
	Ambiguous_Blank_Node_Label,
}

// write_error_message returns a stable, allocation-free description.
write_error_message :: proc(code: Write_Error) -> string {
	switch code {
	case .None:                      return "no error"
	case .Invalid_Prefix_Label:      return "invalid Turtle prefix label"
	case .Invalid_Prefix_Namespace:  return "prefix namespace must be an absolute IRI"
	case .Duplicate_Prefix:          return "duplicate Turtle prefix label"
	case .Invalid_Term_Kind:         return "invalid RDF term kind"
	case .Invalid_Subject:           return "subject must be an IRI or blank node"
	case .Invalid_Predicate:         return "predicate must be an IRI"
	case .Invalid_IRI:               return "invalid absolute IRI"
	case .Invalid_Blank_Node:        return "invalid blank-node label"
	case .Invalid_Language_Tag:      return "invalid language tag"
	case .Invalid_UTF8:              return "invalid UTF-8"
	case .Unexpected_Language:       return "language tag is only valid on a literal"
	case .Unexpected_Datatype:       return "datatype is only valid on a literal"
	case .Missing_Literal_Datatype:  return "literal datatype is required"
	case .Invalid_Language_Datatype:  return "language-tagged literal must use rdf:langString"
	case .Ambiguous_Blank_Node_Label: return "blank-node label refers to multiple source scopes"
	}
	return "unknown error"
}

@(private) map_ntriples_error :: proc(code: ntriples.Write_Error) -> Write_Error {
	switch code {
	case .None:                      return .None
	case .Invalid_Term_Kind:         return .Invalid_Term_Kind
	case .Invalid_Subject:           return .Invalid_Subject
	case .Invalid_Predicate:         return .Invalid_Predicate
	case .Invalid_IRI:               return .Invalid_IRI
	case .Invalid_Blank_Node:        return .Invalid_Blank_Node
	case .Invalid_Language_Tag:      return .Invalid_Language_Tag
	case .Invalid_UTF8:              return .Invalid_UTF8
	case .Unexpected_Language:       return .Unexpected_Language
	case .Unexpected_Datatype:       return .Unexpected_Datatype
	case .Missing_Literal_Datatype:  return .Missing_Literal_Datatype
	case .Invalid_Language_Datatype: return .Invalid_Language_Datatype
	}
	return .Invalid_Term_Kind
}

@(private) valid_prefix_label :: proc(label: string) -> bool {
	if len(label) == 0 do return true
	if !utf8.valid_string(label) do return false
	r, width := utf8.decode_rune_in_string(label)
	if r == utf8.RUNE_ERROR && width == 1 do return false
	if !termlex.is_pn_chars_base(r) do return false
	trailing_dot := false
	for pos := width; pos < len(label); {
		r, width = utf8.decode_rune_in_string(label[pos:])
		if r == utf8.RUNE_ERROR && width == 1 do return false
		if r == '.' {
			trailing_dot = true
		} else if termlex.is_pn_chars(r) {
			trailing_dot = false
		} else {
			return false
		}
		pos += width
	}
	return !trailing_dot
}

@(private) valid_turtle_iri :: proc(value: string) -> bool {
	if !termlex.is_absolute_iri(value) || !utf8.valid_string(value) do return false
	for r in value {
		if r <= ' ' || r == '<' || r == '>' || r == '"' || r == '{' || r == '}' || r == '|' || r == '^' || r == '`' do return false
	}
	return true
}

// valid_prefixed_local accepts the unescaped subset that can be emitted without
// changing an IRI's value. Unsafe local parts deliberately fall back to IRIREF.
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

@(private) validate_options :: proc(options: Writer_Options) -> Write_Error {
	for prefix, i in options.prefixes {
		if !valid_prefix_label(prefix.label) do return .Invalid_Prefix_Label
		if !valid_turtle_iri(prefix.namespace) do return .Invalid_Prefix_Namespace
		for earlier in options.prefixes[:i] {
			if prefix.label == earlier.label do return .Duplicate_Prefix
		}
	}
	return .None
}

@(private) preferred_prefix :: proc(value: string, prefixes: []Prefix) -> (Prefix, string, bool) {
	best_index := -1
	for prefix, i in prefixes {
		if len(prefix.namespace) > len(value) || value[:len(prefix.namespace)] != prefix.namespace do continue
		local := value[len(prefix.namespace):]
		if !valid_prefixed_local(local) do continue
		if best_index < 0 || len(prefix.namespace) > len(prefixes[best_index].namespace) {
			best_index = i
		}
	}
	if best_index < 0 do return {}, "", false
	best := prefixes[best_index]
	return best, value[len(best.namespace):], true
}

@(private) write_iri_unchecked :: proc(builder: ^strings.Builder, value, canonical: string, options: Writer_Options) {
	if prefix, local, ok := preferred_prefix(value, options.prefixes); ok {
		strings.write_string(builder, prefix.label)
		strings.write_byte(builder, ':')
		strings.write_string(builder, local)
		return
	}
	strings.write_string(builder, canonical)
}

@(private) write_term_unchecked :: proc(builder: ^strings.Builder, term: rdf.Term, options: Writer_Options) -> Write_Error {
	if term.kind == .IRI && !valid_turtle_iri(term.value) do return .Invalid_IRI
	if term.kind == .Literal && len(term.language) == 0 && !valid_turtle_iri(term.datatype) do return .Invalid_IRI
	canonical := strings.builder_make()
	defer strings.builder_destroy(&canonical)
	if err := ntriples.write_term(&canonical, term); err != .None do return map_ntriples_error(err)
	canonical_text := strings.to_string(canonical)
	if term.kind == .IRI {
		write_iri_unchecked(builder, term.value, canonical_text, options)
		return .None
	}
	if term.kind == .Literal && len(term.language) == 0 && term.datatype != rdf.XSD_STRING {
		datatype_canonical := strings.builder_make()
		defer strings.builder_destroy(&datatype_canonical)
		if err := ntriples.write_term(&datatype_canonical, rdf.iri(term.datatype)); err != .None do return map_ntriples_error(err)
		datatype_text := strings.to_string(datatype_canonical)
		if prefix, local, ok := preferred_prefix(term.datatype, options.prefixes); ok {
			literal_end := len(canonical_text) - 2 - len(datatype_text)
			strings.write_string(builder, canonical_text[:literal_end])
			strings.write_string(builder, "^^")
			strings.write_string(builder, prefix.label)
			strings.write_byte(builder, ':')
			strings.write_string(builder, local)
			return .None
		}
	}
	strings.write_string(builder, canonical_text)
	return .None
}

// write_prefixes atomically appends canonical Turtle @prefix directives. Call
// it once before write_triple when the configured prefixes should be declared.
write_prefixes :: proc(builder: ^strings.Builder, prefixes: []Prefix) -> Write_Error {
	options := Writer_Options{prefixes = prefixes}
	if err := validate_options(options); err != .None do return err
	temporary := strings.builder_make()
	defer strings.builder_destroy(&temporary)
	for prefix in prefixes {
		strings.write_string(&temporary, "@prefix ")
		strings.write_string(&temporary, prefix.label)
		strings.write_string(&temporary, ": <")
		// validate_options establishes that this is a valid absolute IRI. Reuse the
		// N-Triples encoder so control characters and forbidden delimiters are escaped.
		iri := rdf.iri(prefix.namespace)
		encoded := strings.builder_make()
		if err := ntriples.write_term(&encoded, iri); err != .None {
			strings.builder_destroy(&encoded)
			return map_ntriples_error(err)
		}
		term := strings.to_string(encoded)
		strings.write_string(&temporary, term[1:len(term) - 1])
		strings.builder_destroy(&encoded)
		strings.write_string(&temporary, "> .\n")
	}
	strings.write_string(builder, strings.to_string(temporary))
	return .None
}

// write_term atomically appends a validated Turtle term. Prefixes are optional;
// terms without a safe compact spelling are written as canonical IRIREFs,
// blank-node labels, or literals.
write_term :: proc(builder: ^strings.Builder, term: rdf.Term, options: Writer_Options = {}) -> Write_Error {
	if err := validate_options(options); err != .None do return err
	temporary := strings.builder_make()
	defer strings.builder_destroy(&temporary)
	if err := write_term_unchecked(&temporary, term, options); err != .None do return err
	strings.write_string(builder, strings.to_string(temporary))
	return .None
}

// write_triple atomically appends one stable Turtle triple. It is streaming-safe:
// it never groups statements, reorders triples, or retains prior output state.
write_triple :: proc(builder: ^strings.Builder, triple: rdf.Triple, options: Writer_Options = {}) -> Write_Error {
	if err := validate_options(options); err != .None do return err
	if triple.subject.kind == .Literal do return .Invalid_Subject
	if triple.predicate.kind != .IRI do return .Invalid_Predicate
	temporary := strings.builder_make()
	defer strings.builder_destroy(&temporary)
	if err := write_term_unchecked(&temporary, triple.subject, options); err != .None do return err
	strings.write_byte(&temporary, ' ')
	if err := write_term_unchecked(&temporary, triple.predicate, options); err != .None do return err
	strings.write_byte(&temporary, ' ')
	if err := write_term_unchecked(&temporary, triple.object, options); err != .None do return err
	strings.write_string(&temporary, " .\n")
	strings.write_string(builder, strings.to_string(temporary))
	return .None
}
