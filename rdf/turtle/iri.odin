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

@(private) same_iri_authority :: proc(a, b: IRI_Parts) -> bool {
	return a.has_authority == b.has_authority && (!a.has_authority || a.authority == b.authority)
}

@(private) write_base_directory :: proc(path: string, builder: ^strings.Builder) {
	if len(path) == 0 do return
	if path[len(path) - 1] == '/' {
		strings.write_string(builder, path)
		return
	}
	if slash := strings.last_index_byte(path, '/'); slash >= 0 do strings.write_string(builder, path[:slash + 1])
}

@(private) write_relative_path :: proc(base_path, target_path: string, builder: ^strings.Builder) {
	base_directory_builder := strings.builder_make()
	defer strings.builder_destroy(&base_directory_builder)
	write_base_directory(base_path, &base_directory_builder)
	base_directory := strings.to_string(base_directory_builder)

	common_end := 0
	limit := len(base_directory) < len(target_path) ? len(base_directory) : len(target_path)
	for index in 0..<limit {
		if base_directory[index] != target_path[index] do break
		if base_directory[index] == '/' do common_end = index + 1
	}

	base_tail := base_directory[common_end:]
	segment_start := 0
	for index in 0..<len(base_tail) {
		if base_tail[index] == '/' {
			if index > segment_start do strings.write_string(builder, "../")
			segment_start = index + 1
		}
	}
	if segment_start < len(base_tail) do strings.write_string(builder, "../")

	target_tail := target_path[common_end:]
	if len(target_tail) > 0 {
		strings.write_string(builder, target_tail)
	} else if len(base_tail) == 0 {
		// An empty reference inherits the base document, not its directory.
		strings.write_string(builder, "./")
	}
}

@(private) relative_path_needs_dot_prefix :: proc(value: string) -> bool {
	if len(value) == 0 || strings.has_prefix(value, "./") || strings.has_prefix(value, "../") || value[0] == '/' do return false
	// JSON-LD treats keyword-like values specially. A path segment beginning
	// with @ must therefore be explicitly document-relative.
	if value[0] == '@' do return true
	for character in value {
		if character == ':' do return true
		if character == '/' || character == '?' || character == '#' do break
	}
	return false
}

@(private) write_reference_suffix :: proc(builder: ^strings.Builder, parts: IRI_Parts) {
	if parts.has_query {
		strings.write_byte(builder, '?')
		strings.write_string(builder, parts.query)
	}
	if parts.has_fragment {
		strings.write_byte(builder, '#')
		strings.write_string(builder, parts.fragment)
	}
}

@(private) consider_relative_reference :: proc(base, target, candidate: string, best: ^string) {
	if len(candidate) == 0 do return
	resolved, ok := resolve_iri_reference(base, candidate)
	if !ok do return
	valid := resolved == target
	delete(resolved)
	if !valid || (len(best^) > 0 && (len(candidate) > len(best^) || (len(candidate) == len(best^) && strings.compare(candidate, best^) >= 0))) do return
	copy := strings.clone(candidate) or_else ""
	if len(copy) == 0 do return
	if len(best^) > 0 do delete(best^)
	best^ = copy
}

// relativize_iri_reference returns the shortest safe relative reference from
// base to target when both references share a scheme and authority. The result
// is validated through resolve_iri_reference so query, fragment, dot-segment,
// and keyword-like path edge cases retain RFC 3986 semantics.
relativize_iri_reference :: proc(base, target: string) -> (string, bool) {
	b := split_reference(base)
	t := split_reference(target)
	if len(b.scheme) == 0 || len(t.scheme) == 0 || b.scheme != t.scheme || !same_iri_authority(b, t) do return "", false

	best := ""

	path_builder := strings.builder_make()
	defer strings.builder_destroy(&path_builder)
	write_relative_path(b.path, t.path, &path_builder)
	path := strings.to_string(path_builder)
	candidate_builder := strings.builder_make()
	defer strings.builder_destroy(&candidate_builder)
	if relative_path_needs_dot_prefix(path) do strings.write_string(&candidate_builder, "./")
	strings.write_string(&candidate_builder, path)
	write_reference_suffix(&candidate_builder, t)
	consider_relative_reference(base, target, strings.to_string(candidate_builder), &best)

	// When the path is unchanged, query- and fragment-only references are both
	// shorter and avoid manufacturing a redundant document filename.
	if t.path == b.path && t.has_query {
		strings.builder_reset(&candidate_builder)
		strings.write_byte(&candidate_builder, '?')
		strings.write_string(&candidate_builder, t.query)
		write_reference_suffix(&candidate_builder, IRI_Parts{has_fragment = t.has_fragment, fragment = t.fragment})
		consider_relative_reference(base, target, strings.to_string(candidate_builder), &best)
	}
	if t.path == b.path && t.has_fragment && t.has_query == b.has_query && (!t.has_query || t.query == b.query) {
		strings.builder_reset(&candidate_builder)
		strings.write_byte(&candidate_builder, '#')
		strings.write_string(&candidate_builder, t.fragment)
		consider_relative_reference(base, target, strings.to_string(candidate_builder), &best)
	}
	if len(best) == 0 do return "", false
	return best, true
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
