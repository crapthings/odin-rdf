package turtle

import "core:strings"

@(private) IRI_Parts :: struct {
	scheme:        string,
	authority:     string,
	path:          string,
	query:         string,
	fragment:      string,
	has_authority: bool,
	has_query:     bool,
	has_fragment:  bool,
}

@(private) is_scheme_start :: #force_inline proc(c: byte) -> bool {
	return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')
}

@(private) is_scheme_char :: #force_inline proc(c: byte) -> bool {
	return is_scheme_start(c) || (c >= '0' && c <= '9') || c == '+' || c == '-' || c == '.'
}

@(private) split_reference :: proc(value: string) -> IRI_Parts {
	parts: IRI_Parts
	rest := value
	for c, index in rest {
		if c == ':' {
			valid := index > 0 && is_scheme_start(rest[0])
			if valid {
				for j in 1..<index {
					if !is_scheme_char(rest[j]) { valid = false; break }
				}
			}
			if valid {
				parts.scheme = rest[:index]
				rest = rest[index + 1:]
			}
			break
		}
		if c == '/' || c == '?' || c == '#' do break
	}
	if strings.has_prefix(rest, "//") {
		parts.has_authority = true
		rest = rest[2:]
		end := len(rest)
		for c, index in rest {
			if c == '/' || c == '?' || c == '#' { end = index; break }
		}
		parts.authority = rest[:end]
		rest = rest[end:]
	}
	path_end := len(rest)
	for c, index in rest {
		if c == '?' || c == '#' { path_end = index; break }
	}
	parts.path = rest[:path_end]
	rest = rest[path_end:]
	if len(rest) > 0 && rest[0] == '?' {
		parts.has_query = true
		rest = rest[1:]
		end := strings.index_byte(rest, '#')
		if end < 0 do end = len(rest)
		parts.query = rest[:end]
		rest = rest[end:]
	}
	if len(rest) > 0 && rest[0] == '#' {
		parts.has_fragment = true
		parts.fragment = rest[1:]
	}
	return parts
}

@(private) remove_last_segment :: proc(builder: ^strings.Builder) {
	value := strings.to_string(builder^)
	index := strings.last_index_byte(value, '/')
	if index < 0 { strings.builder_reset(builder); return }
	resize(&builder.buf, index)
}

@(private) remove_dot_segments :: proc(path: string, output: ^strings.Builder) {
	input := path
	for len(input) > 0 {
		switch {
		case strings.has_prefix(input, "../"):
			input = input[3:]
		case strings.has_prefix(input, "./"):
			input = input[2:]
		case strings.has_prefix(input, "/./"):
			input = input[2:]
		case input == "/.":
			input = "/"
		case strings.has_prefix(input, "/../"):
			input = input[3:]
			remove_last_segment(output)
		case input == "/..":
			input = "/"
			remove_last_segment(output)
		case input == "." || input == "..":
			input = ""
		case:
			end := len(input)
			start := 0
			if input[0] == '/' do start = 1
			if next := strings.index_byte(input[start:], '/'); next >= 0 do end = start + next
			strings.write_string(output, input[:end])
			input = input[end:]
		}
	}
}

@(private) write_authority :: proc(builder: ^strings.Builder, parts: IRI_Parts) {
	if parts.has_authority {
		strings.write_string(builder, "//")
		strings.write_string(builder, parts.authority)
	}
}

// resolve_iri_reference resolves a reference against an absolute base according
// to RFC 3986. Syntax packages use it for document-relative RDF identifiers.
resolve_iri_reference :: proc(base, reference: string) -> (string, bool) {
	b := split_reference(base)
	if len(b.scheme) == 0 do return "", false
	r := split_reference(reference)
	t: IRI_Parts
	path_builder := strings.builder_make()
	defer strings.builder_destroy(&path_builder)

	if len(r.scheme) > 0 {
		t = r
		remove_dot_segments(r.path, &path_builder)
		t.path = strings.to_string(path_builder)
	} else {
		t.scheme = b.scheme
		if r.has_authority {
			t.has_authority = true
			t.authority = r.authority
			remove_dot_segments(r.path, &path_builder)
			t.path = strings.to_string(path_builder)
			t.has_query, t.query = r.has_query, r.query
		} else {
			t.has_authority, t.authority = b.has_authority, b.authority
			if len(r.path) == 0 {
				t.path = b.path
				if r.has_query { t.has_query, t.query = true, r.query }
				else { t.has_query, t.query = b.has_query, b.query }
			} else {
				if r.path[0] == '/' {
					remove_dot_segments(r.path, &path_builder)
				} else {
					if b.has_authority && len(b.path) == 0 {
						strings.write_byte(&path_builder, '/')
					} else if slash := strings.last_index_byte(b.path, '/'); slash >= 0 {
						strings.write_string(&path_builder, b.path[:slash + 1])
					}
					strings.write_string(&path_builder, r.path)
					merged := strings.clone(strings.to_string(path_builder)) or_else ""
					strings.builder_reset(&path_builder)
					remove_dot_segments(merged, &path_builder)
					delete(merged)
				}
				t.path = strings.to_string(path_builder)
				t.has_query, t.query = r.has_query, r.query
			}
		}
	}
	t.has_fragment, t.fragment = r.has_fragment, r.fragment

	result := strings.builder_make()
	strings.write_string(&result, t.scheme)
	strings.write_byte(&result, ':')
	write_authority(&result, t)
	strings.write_string(&result, t.path)
	if t.has_query {
		strings.write_byte(&result, '?')
		strings.write_string(&result, t.query)
	}
	if t.has_fragment {
		strings.write_byte(&result, '#')
		strings.write_string(&result, t.fragment)
	}
	return strings.to_string(result), true
}
