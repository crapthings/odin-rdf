package ntriples

import "core:strings"
import "core:unicode/utf8"
import rdf ".."
import termlex "../internal/termlex"

// Write_Error identifies why a term or triple cannot be serialized as N-Triples.
Write_Error :: enum {
	None,
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
}

// write_error_message returns a stable, allocation-free description.
write_error_message :: proc(code: Write_Error) -> string {
	switch code {
	case .None:                      return "no error"
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
	case .Invalid_Language_Datatype: return "language-tagged literal must use rdf:langString"
	}
	return "unknown error"
}

@(private) term_structure_write_error :: proc(code: rdf.Term_Structure_Error) -> Write_Error {
	switch code {
	case .None:                      return .None
	case .Invalid_Term_Kind:         return .Invalid_Term_Kind
	case .Unexpected_Language:       return .Unexpected_Language
	case .Unexpected_Datatype:       return .Unexpected_Datatype
	case .Missing_Datatype:          return .Missing_Literal_Datatype
	case .Invalid_Language_Datatype: return .Invalid_Language_Datatype
	}
	return .Invalid_Term_Kind
}

@(private) write_hex4 :: proc(builder: ^strings.Builder, value: u32) {
	hex := "0123456789ABCDEF"
	strings.write_string(builder, "\\u")
	for shift := 12; shift >= 0; shift -= 4 do strings.write_byte(builder, hex[(value >> u32(shift)) & 0xf])
}

@(private) write_iri_value_unchecked :: proc(builder: ^strings.Builder, value: string) {
	for r in value {
		u := u32(r)
		if u <= 0x20 || r == '<' || r == '>' || r == '"' || r == '{' || r == '}' || r == '|' || r == '^' || r == '`' || r == '\\' {
			if u <= 0xffff {
				write_hex4(builder, u)
			} else {
				strings.write_string(builder, "\\U")
				hex := "0123456789ABCDEF"
				for shift := 28; shift >= 0; shift -= 4 do strings.write_byte(builder, hex[(u >> u32(shift)) & 0xf])
			}
		} else {
			strings.write_rune(builder, r)
		}
	}
}

@(private) valid_language :: proc(value: string) -> bool {
	if len(value) == 0 do return false
	s := termlex.Scanner{input = value, line = 1, column = 1}
	letters := 0
	for s.pos < len(s.input) && ((s.input[s.pos] >= 'a' && s.input[s.pos] <= 'z') || (s.input[s.pos] >= 'A' && s.input[s.pos] <= 'Z')) {
		termlex.advance_ascii(&s); letters += 1
	}
	if letters == 0 do return false
	for s.pos < len(s.input) {
		if s.input[s.pos] != '-' do return false
		termlex.advance_ascii(&s)
		part := 0
		for s.pos < len(s.input) {
			c := s.input[s.pos]
			if !((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')) do break
			termlex.advance_ascii(&s); part += 1
		}
		if part == 0 do return false
	}
	return true
}

@(private) valid_blank_node :: proc(value: string) -> bool {
	if len(value) == 0 do return false
	r, width := utf8.decode_rune_in_string(value)
	if r == utf8.RUNE_ERROR && width == 1 do return false
	if !(termlex.is_pn_chars_u(r) || (r >= '0' && r <= '9')) do return false
	last_dot := false
	for pos := width; pos < len(value); {
		r, width = utf8.decode_rune_in_string(value[pos:])
		if r == utf8.RUNE_ERROR && width == 1 do return false
		if r == '.' {
			last_dot = true
		} else if termlex.is_pn_chars(r) {
			last_dot = false
		} else {
			return false
		}
		pos += width
	}
	return !last_dot
}

@(private) write_literal_value_unchecked :: proc(builder: ^strings.Builder, value: string) {
	for r in value {
		switch r {
		case '\t': strings.write_string(builder, "\\t")
		case '\b': strings.write_string(builder, "\\b")
		case '\n': strings.write_string(builder, "\\n")
		case '\r': strings.write_string(builder, "\\r")
		case '\f': strings.write_string(builder, "\\f")
		case '"': strings.write_string(builder, "\\\"")
		case '\\': strings.write_string(builder, "\\\\")
		case:
			if u32(r) < 0x20 {
				write_hex4(builder, u32(r))
			} else {
				strings.write_rune(builder, r)
			}
		}
	}
}

@(private) validate_term :: proc(term: rdf.Term) -> Write_Error {
	if structure_error := term_structure_write_error(rdf.validate_term_structure(term)); structure_error != .None do return structure_error
	switch term.kind {
	case .IRI:
		if !termlex.is_absolute_iri(term.value) do return .Invalid_IRI
		if !utf8.valid_string(term.value) do return .Invalid_UTF8
	case .Blank_Node:
		if !valid_blank_node(term.value) do return .Invalid_Blank_Node
	case .Literal:
		if !utf8.valid_string(term.value) do return .Invalid_UTF8
		if len(term.language) > 0 {
			if !valid_language(term.language) do return .Invalid_Language_Tag
		} else {
			if !termlex.is_absolute_iri(term.datatype) do return .Invalid_IRI
			if !utf8.valid_string(term.datatype) do return .Invalid_UTF8
		}
	case: return .Invalid_Term_Kind
	}
	return .None
}

@(private) write_term_unchecked :: proc(builder: ^strings.Builder, term: rdf.Term) {
	switch term.kind {
	case .IRI:
		strings.write_byte(builder, '<')
		write_iri_value_unchecked(builder, term.value)
		strings.write_byte(builder, '>')
	case .Blank_Node:
		strings.write_string(builder, "_:")
		strings.write_string(builder, term.value)
	case .Literal:
		strings.write_byte(builder, '"')
		write_literal_value_unchecked(builder, term.value)
		strings.write_byte(builder, '"')
		if len(term.language) > 0 {
			strings.write_byte(builder, '@')
			strings.write_string(builder, term.language)
		} else if len(term.datatype) > 0 && term.datatype != rdf.XSD_STRING {
			strings.write_string(builder, "^^<")
			write_iri_value_unchecked(builder, term.datatype)
			strings.write_byte(builder, '>')
		}
	}

}

// write_term appends one validated N-Triples term. The builder remains unchanged
// when validation fails.
write_term :: proc(builder: ^strings.Builder, term: rdf.Term) -> Write_Error {
	if err := validate_term(term); err != .None do return err
	write_term_unchecked(builder, term)
	return .None
}

// write_triple atomically appends one canonical-layout N-Triples record.
// The builder remains unchanged when validation fails.
write_triple :: proc(builder: ^strings.Builder, triple: rdf.Triple) -> Write_Error {
	if triple.subject.kind == .Literal do return .Invalid_Subject
	if triple.predicate.kind != .IRI do return .Invalid_Predicate
	if err := validate_term(triple.subject); err != .None do return err
	if err := validate_term(triple.predicate); err != .None do return err
	if err := validate_term(triple.object); err != .None do return err
	write_term_unchecked(builder, triple.subject)
	strings.write_byte(builder, ' ')
	write_term_unchecked(builder, triple.predicate)
	strings.write_byte(builder, ' ')
	write_term_unchecked(builder, triple.object)
	strings.write_string(builder, " .\n")
	return .None
}
