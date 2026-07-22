// Explicit Web-document admission for JSON-LD. The package never opens a
// socket: callers provide the loader, including their own timeout, redirect,
// cache, authentication, and allow-list policy.
package jsonld

import "core:strings"
import "core:unicode/utf8"
import turtle "../turtle"

// Remote_Document is one HTTP-like response supplied by a Remote_Document_Loader.
// Every field is borrowed and is consumed before the callback returns. document_url
// must be the final absolute document URL after any redirects followed by the
// caller's transport. link_headers contains complete HTTP Link field values.
Remote_Document :: struct {
	document_url: string,
	content_type: string,
	link_headers: []string,
	body:         string,
}

// Remote_Document_Loader performs explicit I/O for Web documents and remote
// contexts. Returning ok=false represents a transport or admission failure.
// The jsonld package deliberately supplies no default HTTP implementation.
Remote_Document_Loader :: proc(url: string, user_data: rawptr) -> (Remote_Document, bool)

// Web_Document_Options controls one bounded Web-document admission. A zero
// max_document_bytes selects the ordinary JSON-LD document limit. max_documents
// bounds alternate-document following; zero selects four documents.
Web_Document_Options :: struct {
	document_loader:    Remote_Document_Loader,
	loader_data:        rawptr,
	max_document_bytes: int,
	max_documents:      int,
	extract_all_scripts: bool,
}

// Web_Document owns the normalized JSON-LD source, final document URL, effective
// base IRI, and any context URL carried by a JSON HTTP Link header. Call
// destroy_web_document when it is no longer needed.
Web_Document :: struct {
	document:    string,
	document_url: string,
	base_iri:    string,
	context_url: string,
}

destroy_web_document :: proc(document: ^Web_Document) {
	if len(document.document) > 0 do delete(document.document)
	if len(document.document_url) > 0 do delete(document.document_url)
	if len(document.base_iri) > 0 do delete(document.base_iri)
	if len(document.context_url) > 0 do delete(document.context_url)
	document^ = {}
}

Web_Document_Error :: enum {
	None,
	Invalid_Option,
	Invalid_URL,
	Missing_Document_Loader,
	Loading_Document_Failed,
	Document_Too_Large,
	Unsupported_Media_Type,
	Multiple_Context_Links,
	Invalid_HTML,
	No_JSONLD_Script,
	Out_Of_Memory,
}

web_document_error_message :: proc(code: Web_Document_Error) -> string {
	switch code {
	case .None:                    return "no error"
	case .Invalid_Option:          return "web document options are invalid"
	case .Invalid_URL:             return "invalid web document URL"
	case .Missing_Document_Loader: return "web document requires an explicit loader"
	case .Loading_Document_Failed: return "failed to load web document"
	case .Document_Too_Large:      return "web document exceeds configured byte limit"
	case .Unsupported_Media_Type:  return "web document media type is unsupported"
	case .Multiple_Context_Links:  return "web document has multiple JSON-LD context links"
	case .Invalid_HTML:            return "invalid HTML JSON-LD selection"
	case .No_JSONLD_Script:        return "HTML document has no selected JSON-LD script"
	case .Out_Of_Memory:           return "out of memory"
	}
	return "unknown web document error"
}

// Web_Expand_Options combines bounded expansion with explicit Web admission.
Web_Expand_Options :: struct {
	document_options: Web_Document_Options,
	expand_options:   Expand_Options,
}

// Web_Parse_Options combines bounded RDF conversion with explicit Web admission.
Web_Parse_Options :: struct {
	document_options: Web_Document_Options,
	parse_options:    Options,
}

@(private) web_is_space :: proc(value: u8) -> bool {
	return value == ' ' || value == '\t' || value == '\r' || value == '\n' || value == '\f'
}

@(private) web_ascii_lower :: proc(value: u8) -> u8 {
	if value >= 'A' && value <= 'Z' do return value + ('a' - 'A')
	return value
}

@(private) web_equal_fold :: proc(left, right: string) -> bool {
	if len(left) != len(right) do return false
	for index in 0..<len(left) {
		if web_ascii_lower(left[index]) != web_ascii_lower(right[index]) do return false
	}
	return true
}

@(private) web_has_prefix_fold :: proc(value, prefix: string) -> bool {
	if len(value) < len(prefix) do return false
	return web_equal_fold(value[:len(prefix)], prefix)
}

@(private) web_has_suffix_fold :: proc(value, suffix: string) -> bool {
	if len(value) < len(suffix) do return false
	return web_equal_fold(value[len(value) - len(suffix):], suffix)
}

@(private) web_tag_end :: proc(input: string, start: int) -> (int, bool) {
	quote: u8
	for index in start..<len(input) {
		character := input[index]
		if quote != 0 {
			if character == quote do quote = 0
			continue
		}
		if character == '\'' || character == '"' {
			quote = character
			continue
		}
		if character == '>' do return index, true
	}
	return 0, false
}

@(private) web_tag_attribute :: proc(attributes, wanted: string) -> (string, bool) {
	index := 0
	for index < len(attributes) {
		for index < len(attributes) && (web_is_space(attributes[index]) || attributes[index] == '/') do index += 1
		if index >= len(attributes) do break
		name_start := index
		for index < len(attributes) && !web_is_space(attributes[index]) && attributes[index] != '=' && attributes[index] != '/' do index += 1
		name := attributes[name_start:index]
		for index < len(attributes) && web_is_space(attributes[index]) do index += 1
		if index >= len(attributes) || attributes[index] != '=' {
			if web_equal_fold(name, wanted) do return "", true
			continue
		}
		index += 1
		for index < len(attributes) && web_is_space(attributes[index]) do index += 1
		if index >= len(attributes) {
			if web_equal_fold(name, wanted) do return "", true
			break
		}
		value_start := index
		value_end := index
		if attributes[index] == '\'' || attributes[index] == '"' {
			quote := attributes[index]
			value_start += 1
			index += 1
			for index < len(attributes) && attributes[index] != quote do index += 1
			value_end = index
			if index < len(attributes) do index += 1
		} else {
			for index < len(attributes) && !web_is_space(attributes[index]) && attributes[index] != '/' do index += 1
			value_end = index
		}
		if web_equal_fold(name, wanted) do return attributes[value_start:value_end], true
	}
	return "", false
}

@(private) web_find_next_tag :: proc(input, name: string, start: int) -> (tag_start, tag_end: int, attributes: string, found: bool) {
	index := start
	for index < len(input) {
		relative := strings.index_byte(input[index:], '<')
		if relative < 0 do break
		index += relative
		if index + 1 + len(name) <= len(input) && input[index + 1] != '/' && web_equal_fold(input[index + 1:index + 1 + len(name)], name) {
			after_name := index + 1 + len(name)
			if after_name == len(input) || web_is_space(input[after_name]) || input[after_name] == '>' || input[after_name] == '/' {
				end, valid := web_tag_end(input, after_name)
				if !valid do return 0, 0, "", false
				return index, end, input[after_name:end], true
			}
		}
		index += 1
	}
	return 0, 0, "", false
}

@(private) web_find_script_end :: proc(input: string, start: int) -> (content_end, tag_end: int, found: bool) {
	index := start
	for index < len(input) {
		relative := strings.index_byte(input[index:], '<')
		if relative < 0 do break
		index += relative
		if index + 8 <= len(input) && input[index + 1] == '/' && web_equal_fold(input[index + 2:index + 8], "script") {
			after_name := index + 8
			if after_name == len(input) || web_is_space(input[after_name]) || input[after_name] == '>' {
				end, valid := web_tag_end(input, after_name)
				if !valid do return 0, 0, false
				return index, end, true
			}
		}
		index += 1
	}
	return 0, 0, false
}

@(private) web_media_type :: proc(value: string) -> string {
	end := strings.index_byte(value, ';')
	if end < 0 do end = len(value)
	return strings.trim_space(value[:end])
}

@(private) web_is_jsonld_media_type :: proc(value: string) -> bool {
	return web_equal_fold(web_media_type(value), "application/ld+json")
}

@(private) web_is_json_media_type :: proc(value: string) -> bool {
	media_type := web_media_type(value)
	return web_equal_fold(media_type, "application/json") || web_has_suffix_fold(media_type, "+json")
}

@(private) web_is_html_media_type :: proc(value: string) -> bool {
	media_type := web_media_type(value)
	return web_equal_fold(media_type, "text/html") || web_equal_fold(media_type, "application/xhtml+xml")
}

@(private) web_resolve_url :: proc(base, reference: string) -> (string, Web_Document_Error) {
	if len(reference) == 0 {
		cloned, clone_error := strings.clone(base)
		if clone_error != nil do return "", .Out_Of_Memory
		return cloned, .None
	}
	if has_iri_scheme(reference) {
		cloned, clone_error := strings.clone(reference)
		if clone_error != nil do return "", .Out_Of_Memory
		return cloned, .None
	}
	if len(base) == 0 do return "", .Invalid_URL
	resolved, valid := turtle.resolve_iri_reference(base, reference)
	if !valid do return "", .Invalid_URL
	return resolved, .None
}

@(private) web_split_fragment :: proc(url: string) -> (without_fragment, fragment: string) {
	separator := strings.index_byte(url, '#')
	if separator < 0 do return url, ""
	return url[:separator], url[separator + 1:]
}

@(private) web_link_parameter :: proc(value, wanted: string) -> (string, bool) {
	index := 0
	for index < len(value) {
		for index < len(value) && (web_is_space(value[index]) || value[index] == ';') do index += 1
		if index >= len(value) do break
		name_start := index
		for index < len(value) && value[index] != '=' && value[index] != ';' && !web_is_space(value[index]) do index += 1
		name := value[name_start:index]
		for index < len(value) && web_is_space(value[index]) do index += 1
		if index >= len(value) || value[index] != '=' {
			for index < len(value) && value[index] != ';' do index += 1
			continue
		}
		index += 1
		for index < len(value) && web_is_space(value[index]) do index += 1
		value_start := index
		value_end := index
		if index < len(value) && (value[index] == '\'' || value[index] == '"') {
			quote := value[index]
			value_start += 1
			index += 1
			for index < len(value) && value[index] != quote do index += 1
			value_end = index
			if index < len(value) do index += 1
		} else {
			for index < len(value) && value[index] != ';' && !web_is_space(value[index]) do index += 1
			value_end = index
		}
		if web_equal_fold(name, wanted) do return value[value_start:value_end], true
	}
	return "", false
}

@(private) web_relation_contains :: proc(value, wanted: string) -> bool {
	index := 0
	for index < len(value) {
		for index < len(value) && web_is_space(value[index]) do index += 1
		start := index
		for index < len(value) && !web_is_space(value[index]) do index += 1
		if start < index && web_equal_fold(value[start:index], wanted) do return true
	}
	return false
}

@(private) web_find_link :: proc(headers: []string, base, relation, required_type: string) -> (string, int, Web_Document_Error) {
	count := 0
	selected := ""
	for header in headers {
		index := 0
		for index < len(header) {
			for index < len(header) && (web_is_space(header[index]) || header[index] == ',') do index += 1
			if index >= len(header) do break
			if header[index] != '<' {
				for index < len(header) && header[index] != ',' do index += 1
				continue
			}
			index += 1
			target_start := index
			for index < len(header) && header[index] != '>' do index += 1
			if index >= len(header) do break
			target := header[target_start:index]
			index += 1
			parameters_start := index
			quote: u8
			for index < len(header) {
				character := header[index]
				if quote != 0 {
					if character == quote do quote = 0
					index += 1
					continue
				}
				if character == '\'' || character == '"' {
					quote = character
					index += 1
					continue
				}
				if character == ',' do break
				index += 1
			}
			parameters := header[parameters_start:index]
			rel, has_rel := web_link_parameter(parameters, "rel")
			if !has_rel || !web_relation_contains(rel, relation) do continue
			if len(required_type) > 0 {
				kind, has_kind := web_link_parameter(parameters, "type")
				if !has_kind || !web_equal_fold(web_media_type(kind), required_type) do continue
			}
			resolved, resolve_error := web_resolve_url(base, target)
			if resolve_error != .None do return "", 0, resolve_error
			if count == 0 {
				selected = resolved
			} else {
				delete(resolved)
			}
			count += 1
		}
	}
	return selected, count, .None
}

@(private) web_normalize_script :: proc(content: string) -> (string, Web_Document_Error) {
	trimmed := strings.trim_space(content)
	starts_comment := strings.has_prefix(trimmed, "<!--")
	ends_comment := strings.has_suffix(trimmed, "-->")
	if starts_comment != ends_comment do return "", .Invalid_HTML
	if starts_comment {
		trimmed = strings.trim_space(trimmed[len("<!--"):len(trimmed) - len("-->")])
		// JSON-LD script elements allow one legacy HTML comment wrapper only.
		// Further comment markers would otherwise be silently treated as JSON
		// string content instead of an invalid script element.
		if strings.contains(trimmed, "<!--") || strings.contains(trimmed, "-->") do return "", .Invalid_HTML
	}
	if strings.contains(trimmed, "<!--") || strings.contains(trimmed, "-->") do return "", .Invalid_HTML
	return trimmed, .None
}

@(private) web_write_script_value :: proc(builder: ^strings.Builder, content: string, first: ^bool) -> Web_Document_Error {
	trimmed, normalize_error := web_normalize_script(content)
	if normalize_error != .None do return normalize_error
	if len(trimmed) == 0 do return .None
	if len(trimmed) >= 2 && trimmed[0] == '[' && trimmed[len(trimmed) - 1] == ']' {
		trimmed = strings.trim_space(trimmed[1:len(trimmed) - 1])
		if len(trimmed) == 0 do return .None
	}
	if !first^ do strings.write_byte(builder, ',')
	strings.write_string(builder, trimmed)
	first^ = false
	return .None
}

@(private) web_extract_html :: proc(builder: ^strings.Builder, html, fallback_base, fragment: string, extract_all: bool) -> (string, Web_Document_Error) {
	if !utf8.valid_string(html) do return "", .Invalid_HTML
	base_iri, base_error := strings.clone(fallback_base)
	if base_error != nil do return "", .Out_Of_Memory
	defer if len(base_iri) > 0 do delete(base_iri)
	base_start := 0
	if _, _, attributes, found := web_find_next_tag(html, "base", base_start); found {
		if href, has_href := web_tag_attribute(attributes, "href"); has_href && len(href) > 0 {
			resolved, resolve_error := web_resolve_url(base_iri, href)
			if resolve_error != .None do return "", resolve_error
			delete(base_iri)
			base_iri = resolved
		}
	}
	if len(fragment) > 0 {
		index := 0
		for {
			_, tag_end, attributes, found := web_find_next_tag(html, "script", index)
			if !found do break
			content_end, closing_end, closed := web_find_script_end(html, tag_end + 1)
			if !closed do return "", .Invalid_HTML
			identifier, has_id := web_tag_attribute(attributes, "id")
			if has_id && identifier == fragment {
				content_type, has_type := web_tag_attribute(attributes, "type")
				if !has_type || !web_is_jsonld_media_type(content_type) do return "", .Invalid_HTML
				content, normalize_error := web_normalize_script(html[tag_end + 1:content_end])
				if normalize_error != .None do return "", normalize_error
				strings.write_string(builder, content)
				result, clone_error := strings.clone(base_iri)
				if clone_error != nil do return "", .Out_Of_Memory
				return result, .None
			}
			index = closing_end + 1
		}
		return "", .No_JSONLD_Script
	}
	first_script := ""
	first_found := false
	index := 0
	if extract_all do strings.write_byte(builder, '[')
	first := true
	for {
		_, tag_end, attributes, found := web_find_next_tag(html, "script", index)
		if !found do break
		content_end, closing_end, closed := web_find_script_end(html, tag_end + 1)
		if !closed do return "", .Invalid_HTML
		content_type, has_type := web_tag_attribute(attributes, "type")
		if has_type && web_is_jsonld_media_type(content_type) {
			content := html[tag_end + 1:content_end]
			if !extract_all {
				first_script = content
				first_found = true
				break
			}
			if write_error := web_write_script_value(builder, content, &first); write_error != .None do return "", write_error
			first_found = true
		}
		index = closing_end + 1
	}
	if extract_all {
		strings.write_byte(builder, ']')
	} else if first_found {
		content, normalize_error := web_normalize_script(first_script)
		if normalize_error != .None do return "", normalize_error
		strings.write_string(builder, content)
	}
	if !first_found && !extract_all do return "", .No_JSONLD_Script
	result, clone_error := strings.clone(base_iri)
	if clone_error != nil do return "", .Out_Of_Memory
	return result, .None
}

@(private) web_clone_document :: proc(document, document_url, base_iri, context_url: string) -> (Web_Document, Web_Document_Error) {
	result: Web_Document
	result.document, _ = strings.clone(document)
	if len(document) > 0 && len(result.document) == 0 do return {}, .Out_Of_Memory
	result.document_url, _ = strings.clone(document_url)
	if len(document_url) > 0 && len(result.document_url) == 0 {
		destroy_web_document(&result)
		return {}, .Out_Of_Memory
	}
	result.base_iri, _ = strings.clone(base_iri)
	if len(base_iri) > 0 && len(result.base_iri) == 0 {
		destroy_web_document(&result)
		return {}, .Out_Of_Memory
	}
	result.context_url, _ = strings.clone(context_url)
	if len(context_url) > 0 && len(result.context_url) == 0 {
		destroy_web_document(&result)
		return {}, .Out_Of_Memory
	}
	return result, .None
}

// web_document_load obtains one JSON-LD or HTML document through the explicit
// loader, follows a JSON-LD alternate advertised by an HTML response, extracts
// selected JSON-LD script data from HTML, and records a JSON context Link URL.
// It does not perform any network I/O itself.
web_document_load :: proc(url: string, options: Web_Document_Options = {}) -> (Web_Document, Web_Document_Error) {
	if options.document_loader == nil do return {}, .Missing_Document_Loader
	if !utf8.valid_string(url) || !has_iri_scheme(url) do return {}, .Invalid_URL
	max_document_bytes := options.max_document_bytes
	if max_document_bytes == 0 do max_document_bytes = DEFAULT_MAX_DOCUMENT_BYTES
	max_documents := options.max_documents
	if max_documents == 0 do max_documents = 4
	if max_document_bytes < 0 || max_documents < 0 do return {}, .Invalid_Option
	request_url, fragment := web_split_fragment(url)
	if len(request_url) == 0 do return {}, .Invalid_URL
	current, clone_error := strings.clone(request_url)
	if clone_error != nil do return {}, .Out_Of_Memory
	defer delete(current)
	for _ in 0..<max_documents {
		response, loaded := options.document_loader(current, options.loader_data)
		if !loaded do return {}, .Loading_Document_Failed
		if !utf8.valid_string(response.body) || len(response.body) > max_document_bytes do return {}, .Document_Too_Large
		final_url, ignored_fragment := web_split_fragment(response.document_url)
		_ = ignored_fragment
		if len(final_url) == 0 || !has_iri_scheme(final_url) do return {}, .Invalid_URL
		content_type := web_media_type(response.content_type)
		if web_is_html_media_type(content_type) {
			alternate, alternate_count, link_error := web_find_link(response.link_headers, final_url, "alternate", "application/ld+json")
			if link_error != .None do return {}, link_error
			if alternate_count > 0 {
				delete(current)
				current = alternate
				fragment = ""
				continue
			}
			document_builder := strings.builder_make()
			defer strings.builder_destroy(&document_builder)
			base_iri, html_error := web_extract_html(&document_builder, response.body, final_url, fragment, options.extract_all_scripts)
			if html_error != .None do return {}, html_error
			defer delete(base_iri)
			return web_clone_document(strings.to_string(document_builder), final_url, base_iri, "")
		}
		if !web_is_json_media_type(content_type) do return {}, .Unsupported_Media_Type
		context_url := ""
		if !web_is_jsonld_media_type(content_type) {
			context_link, context_count, link_error := web_find_link(response.link_headers, final_url, "http://www.w3.org/ns/json-ld#context", "")
			if link_error != .None do return {}, link_error
			context_url = context_link
			if context_count > 1 {
				if len(context_url) > 0 do delete(context_url)
				return {}, .Multiple_Context_Links
			}
		}
		result, result_error := web_clone_document(response.body, final_url, final_url, context_url)
		if len(context_url) > 0 do delete(context_url)
		return result, result_error
	}
	return {}, .Loading_Document_Failed
}

@(private) Web_Context_State :: struct {
	options:   Web_Document_Options,
	documents: [dynamic]Web_Document,
}

@(private) web_destroy_context_state :: proc(state: ^Web_Context_State) {
	for &document in state.documents do destroy_web_document(&document)
	delete(state.documents)
}

@(private) web_context_loader :: proc(url: string, user_data: rawptr) -> (string, bool) {
	state := cast(^Web_Context_State)user_data
	options := state.options
	options.extract_all_scripts = false
	document, document_error := web_document_load(url, options)
	if document_error != .None do return "", false
	append(&state.documents, document)
	return state.documents[len(state.documents) - 1].document, true
}

@(private) web_initial_context_text :: proc(builder: ^strings.Builder, url: string) {
	write_json_string(builder, url)
}

@(private) web_expand_error :: proc(code: Web_Document_Error) -> Expand_Error {
	#partial switch code {
	case .Document_Too_Large: return .Document_Too_Large
	case .Out_Of_Memory:      return .Out_Of_Memory
	case:                      return .Loading_Document_Failed
	}
}

@(private) web_parse_error :: proc(code: Web_Document_Error) -> Parse_Error {
	#partial switch code {
	case .Document_Too_Large: return Parse_Error{code = .Document_Too_Large}
	case .Out_Of_Memory:      return Parse_Error{code = .Out_Of_Memory}
	case:                      return Parse_Error{code = .Loading_Document_Failed}
	}
}

// expand_url loads and expands one Web JSON-LD document through the caller's
// explicit loader. It adopts the final URL (or HTML base element) as the base
// IRI and honors an HTTP JSON-LD context Link without performing implicit I/O.
expand_url :: proc(builder: ^strings.Builder, url: string, options: Web_Expand_Options = {}) -> Expand_Error {
	document, document_error := web_document_load(url, options.document_options)
	if document_error != .None do return web_expand_error(document_error)
	defer destroy_web_document(&document)
	context_state := Web_Context_State{options = options.document_options}
	defer web_destroy_context_state(&context_state)
	expand_options := options.expand_options
	expand_options.context_options.base_iri = document.base_iri
	expand_options.context_options.document_loader = web_context_loader
	expand_options.context_options.loader_data = &context_state
	if options.document_options.extract_all_scripts do expand_options.preserve_top_level_graph = true
	initial_context := strings.builder_make()
	defer strings.builder_destroy(&initial_context)
	if len(document.context_url) > 0 {
		web_initial_context_text(&initial_context, document.context_url)
		expand_options.context_options.initial_context = strings.to_string(initial_context)
	}
	return expand(builder, document.document, expand_options)
}

// parse_url loads and converts one Web JSON-LD document to RDF through the
// caller's explicit loader. It has the same base and HTTP context-Link policy
// as expand_url.
parse_url :: proc(url: string, sink: Sink, options: Web_Parse_Options = {}, user_data: rawptr = nil) -> Parse_Error {
	document, document_error := web_document_load(url, options.document_options)
	// The To RDF HTML algorithm yields an empty dataset for a page with no
	// selected JSON-LD script. Expansion keeps its distinct loading failure.
	if document_error == .No_JSONLD_Script && strings.index_byte(url, '#') < 0 do return {}
	if document_error != .None do return web_parse_error(document_error)
	defer destroy_web_document(&document)
	context_state := Web_Context_State{options = options.document_options}
	defer web_destroy_context_state(&context_state)
	parse_options := options.parse_options
	parse_options.base_iri = document.base_iri
	parse_options.document_loader = web_context_loader
	parse_options.loader_data = &context_state
	if options.document_options.extract_all_scripts do parse_options.name_top_level_graphs = true
	initial_context := strings.builder_make()
	defer strings.builder_destroy(&initial_context)
	if len(document.context_url) > 0 {
		web_initial_context_text(&initial_context, document.context_url)
		parse_options.initial_context = strings.to_string(initial_context)
	}
	return parse(document.document, sink, parse_options, user_data)
}
