// jsonld_web_runner exercises JSON-LD's explicit Web-document entry points
// against the pinned W3C fixtures. It supplies local fixture files through a
// Remote_Document_Loader; the library itself performs no network I/O.
package main

import "core:fmt"
import "core:os"
import "core:strings"
import rdf "../../../rdf"
import dataset "../../../rdf/dataset"
import jsonld "../../../rdf/jsonld"
import nquads "../../../rdf/nquads"

TESTS_BASE :: "https://w3c.github.io/json-ld-api/tests/"

State :: struct {
	tests_root:       string,
	initial_url:      string,
	initial_relative: string,
	initial_final:    string,
	content_type:     string,
	link_headers:     []string,
	loaded:           [dynamic][]byte,
	urls:             [dynamic]string,
}

destroy_state :: proc(state: ^State) {
	for data in state.loaded do delete(data)
	delete(state.loaded)
	for url in state.urls do delete(url)
	delete(state.urls)
}

make_url :: proc(state: ^State, relative: string) -> string {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	strings.write_string(&builder, TESTS_BASE)
	strings.write_string(&builder, relative)
	url := strings.clone(strings.to_string(builder)) or_else ""
	if len(url) == 0 do return ""
	append(&state.urls, url)
	return url
}

content_type_for_path :: proc(path: string) -> string {
	if strings.has_suffix(path, ".html") do return "text/html"
	if strings.has_suffix(path, ".jsonld") do return "application/ld+json"
	if strings.has_suffix(path, ".json") do return "application/json"
	if strings.has_suffix(path, ".jldt") do return "application/jldTest+json"
	return "application/octet-stream"
}

load_relative :: proc(state: ^State, relative: string) -> (string, bool) {
	path := strings.builder_make()
	defer strings.builder_destroy(&path)
	strings.write_string(&path, state.tests_root)
	strings.write_byte(&path, '/')
	strings.write_string(&path, relative)
	data, read_error := os.read_entire_file(strings.to_string(path), context.allocator)
	if read_error != nil do return "", false
	append(&state.loaded, data)
	return string(data), true
}

load_document :: proc(url: string, user_data: rawptr) -> (jsonld.Remote_Document, bool) {
	state := cast(^State)user_data
	if url == state.initial_url {
		relative := state.initial_final
		if relative == "-" do relative = state.initial_relative
		body, loaded := load_relative(state, relative)
		if !loaded do return {}, false
		final_url := state.initial_url
		if state.initial_final != "-" do final_url = make_url(state, relative)
		return {
			document_url = final_url,
			content_type = state.content_type,
			link_headers = state.link_headers,
			body = body,
		}, true
	}
	if !strings.has_prefix(url, TESTS_BASE) do return {}, false
	relative := url[len(TESTS_BASE):]
	body, loaded := load_relative(state, relative)
	if !loaded do return {}, false
	return {
		document_url = url,
		content_type = content_type_for_path(relative),
		body = body,
	}, true
}

Quad_State :: struct {
	builder: strings.Builder,
	write_error: nquads.Write_Error,
}

write_quad :: proc(quad: rdf.Quad, user_data: rawptr) -> bool {
	state := cast(^Quad_State)user_data
	state.write_error = nquads.write_quad(&state.builder, quad)
	return state.write_error == .None
}

html_state :: proc(tests_root, relative, url, content_type: string) -> (State, string, bool) {
	fragment := strings.index_byte(url, '#')
	request_url := fragment < 0 ? url : url[:fragment]
	if len(request_url) == 0 do return {}, "", false
	return State{tests_root = tests_root, initial_url = request_url, initial_relative = relative, initial_final = "-", content_type = content_type}, url, true
}

html_options :: proc(state: ^State, extract_all: bool) -> jsonld.Web_Document_Options {
	return {document_loader = load_document, loader_data = state, extract_all_scripts = extract_all}
}

run_html_expand :: proc() -> int {
	if len(os.args) != 6 && len(os.args) != 7 {
		fmt.eprintln("usage: jsonld_web_runner html-expand <tests-root> <input-relative> <url> <extract-all:true|false> [content-type]")
		return 2
	}
	content_type := "text/html"
	if len(os.args) == 7 do content_type = os.args[6]
	state, url, valid := html_state(os.args[2], os.args[3], os.args[4], content_type)
	if !valid do return 2
	defer destroy_state(&state)
	extract_all := os.args[5] == "true"
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	if err := jsonld.expand_url(&builder, url, {document_options = html_options(&state, extract_all)}); err != .None {
		fmt.eprintln(jsonld.expand_error_message(err))
		return 1
	}
	fmt.print(strings.to_string(builder))
	return 0
}

run_html_tordf :: proc() -> int {
	if len(os.args) != 6 {
		fmt.eprintln("usage: jsonld_web_runner html-tordf <tests-root> <input-relative> <url> <extract-all:true|false>")
		return 2
	}
	state, url, valid := html_state(os.args[2], os.args[3], os.args[4], "text/html")
	if !valid do return 2
	defer destroy_state(&state)
	extract_all := os.args[5] == "true"
	quads := Quad_State{builder = strings.builder_make()}
	defer strings.builder_destroy(&quads.builder)
	if err := jsonld.parse_url(url, write_quad, {document_options = html_options(&state, extract_all)}, &quads); err.code != .None {
		fmt.eprintln(jsonld.parse_error_message(err.code))
		return 1
	}
	if quads.write_error != .None {
		fmt.eprintln(nquads.write_error_message(quads.write_error))
		return 1
	}
	fmt.print(strings.to_string(quads.builder))
	return 0
}

run_html_flatten :: proc() -> int {
	if len(os.args) != 7 {
		fmt.eprintln("usage: jsonld_web_runner html-flatten <tests-root> <input-relative> <url> <extract-all:true|false> <context-path|->")
		return 2
	}
	state, url, valid := html_state(os.args[2], os.args[3], os.args[4], "text/html")
	if !valid do return 2
	defer destroy_state(&state)
	extract_all := os.args[5] == "true"
	document, document_error := jsonld.web_document_load(url, html_options(&state, extract_all))
	if document_error != .None {
		fmt.eprintln(jsonld.web_document_error_message(document_error))
		return 1
	}
	defer jsonld.destroy_web_document(&document)
	options := jsonld.Flatten_Options{context_options = {base_iri = document.base_iri}, force_graph_output = true}
	context_path := os.args[6]
	context_data: []byte
	defer delete(context_data)
	if context_path != "-" {
		data, read_error := os.read_entire_file(context_path, context.allocator)
		if read_error != nil {
			fmt.eprintf("cannot read %s: %v\n", context_path, read_error)
			return 2
		}
		context_data = data
		options.output_context = string(context_data)
	}
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	if err := jsonld.flatten(&builder, document.document, options); err != .None {
		fmt.eprintln(jsonld.flatten_error_message(err))
		return 1
	}
	fmt.print(strings.to_string(builder))
	return 0
}

run_html_compact :: proc() -> int {
	if len(os.args) != 7 {
		fmt.eprintln("usage: jsonld_web_runner html-compact <tests-root> <input-relative> <url> <extract-all:true|false> <context-path>")
		return 2
	}
	state, url, valid := html_state(os.args[2], os.args[3], os.args[4], "text/html")
	if !valid do return 2
	defer destroy_state(&state)
	extract_all := os.args[5] == "true"
	document, document_error := jsonld.web_document_load(url, html_options(&state, extract_all))
	if document_error != .None {
		fmt.eprintln(jsonld.web_document_error_message(document_error))
		return 1
	}
	defer jsonld.destroy_web_document(&document)
	context_data, context_error := os.read_entire_file(os.args[6], context.allocator)
	if context_error != nil {
		fmt.eprintf("cannot read %s: %v\n", os.args[6], context_error)
		return 2
	}
	defer delete(context_data)
	collector: dataset.Collector
	if collector_error := dataset.init(&collector, dataset.Options{max_quads = jsonld.DEFAULT_MAX_SERIALIZE_QUADS}); collector_error != .None {
		fmt.eprintln(dataset.error_message(collector_error))
		return 2
	}
	defer dataset.destroy(&collector)
	if parse_error := jsonld.parse(document.document, dataset.sink, {base_iri = document.base_iri, name_top_level_graphs = extract_all}, &collector); parse_error.code != .None {
		fmt.eprintln(jsonld.parse_error_message(parse_error.code))
		return 1
	}
	if collector.last_error != .None {
		fmt.eprintln(dataset.error_message(collector.last_error))
		return 1
	}
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	if compact_error := jsonld.compact(&builder, collector.quads[:], string(context_data), {context_options = {base_iri = document.base_iri}, source_document = document.document}); compact_error != .None {
		fmt.eprintln(jsonld.compact_error_message(compact_error))
		return 1
	}
	fmt.print(strings.to_string(builder))
	return 0
}

run_remote_expand :: proc() -> int {
	if len(os.args) < 6 {
		fmt.eprintln("usage: jsonld_web_runner remote-expand <tests-root> <input-relative> <content-type> <final-relative|-> [Link-header ...]")
		return 2
	}
	state := State{
		tests_root = os.args[2],
		initial_relative = os.args[3],
		content_type = os.args[4],
		initial_final = os.args[5],
	}
	defer destroy_state(&state)
	state.initial_url = make_url(&state, state.initial_relative)
	if len(state.initial_url) == 0 do return 2
	if len(os.args) > 6 do state.link_headers = os.args[6:]
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	if err := jsonld.expand_url(&builder, state.initial_url, {document_options = {document_loader = load_document, loader_data = &state}}); err != .None {
		fmt.eprintln(jsonld.expand_error_message(err))
		return 1
	}
	fmt.print(strings.to_string(builder))
	return 0
}

main :: proc() {
	if len(os.args) < 2 {
		fmt.eprintln("usage: jsonld_web_runner remote-expand ...")
		os.exit(2)
	}
	switch os.args[1] {
	case "remote-expand":
		os.exit(run_remote_expand())
	case "html-expand":
		os.exit(run_html_expand())
	case "html-tordf":
		os.exit(run_html_tordf())
	case "html-flatten":
		os.exit(run_html_flatten())
	case "html-compact":
		os.exit(run_html_compact())
	case:
		fmt.eprintf("unknown jsonld web runner mode: %s\n", os.args[1])
		os.exit(2)
	}
}
