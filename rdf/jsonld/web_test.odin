package jsonld

import "core:strings"
import "core:testing"

WEB_TEST_CONTEXT_LINKS := []string{`<context.jsonld>; rel="http://www.w3.org/ns/json-ld#context"`}
WEB_TEST_ALTERNATE_LINKS := []string{`<alternate.jsonld>; rel="alternate"; type="application/ld+json"`}
WEB_TEST_MULTIPLE_CONTEXT_LINKS := []string{
	`<one.jsonld>; rel="http://www.w3.org/ns/json-ld#context"`,
	`<two.jsonld>; rel="http://www.w3.org/ns/json-ld#context"`,
}

@(private) web_test_loader :: proc(url: string, _: rawptr) -> (Remote_Document, bool) {
	switch url {
	case "https://example.test/record.json":
		return {
			document_url = url,
			content_type = "application/json",
			link_headers = WEB_TEST_CONTEXT_LINKS,
			body = `[{"@id":"","name":"Ada"}]`,
		}, true
	case "https://example.test/context.jsonld":
		return {document_url = url, content_type = "application/ld+json", body = `{"@context":{"name":"https://schema.example/name"}}`}, true
	case "https://example.test/page.html":
		return {
			document_url = url,
			content_type = "text/html",
			body = `<html><head><base href="https://example.test/base/"><script type="application/ld+json">{"@id":"","https://schema.example/name":"Ada"}</script></head></html>`,
		}, true
	case "https://example.test/alternate.html":
		return {
			document_url = url,
			content_type = "text/html",
			link_headers = WEB_TEST_ALTERNATE_LINKS,
			body = `<html><head><script type="application/ld+json">{"https://schema.example/name":"ignored"}</script></head></html>`,
		}, true
	case "https://example.test/alternate.jsonld":
		return {document_url = url, content_type = "application/ld+json", body = `{"https://schema.example/name":"selected"}`}, true
	case "https://example.test/multiple.json":
		return {
			document_url = url,
			content_type = "application/json",
			link_headers = WEB_TEST_MULTIPLE_CONTEXT_LINKS,
			body = `{}`,
		}, true
	case "https://example.test/empty.html":
		return {document_url = url, content_type = "text/html", body = `<html><head></head><body></body></html>`}, true
	case "https://example.test/unbalanced-comment.html":
		return {document_url = url, content_type = "text/html", body = `<script type="application/ld+json">{"https://schema.example/name":"Ada"} --></script>`}, true
	case "https://example.test/multiple-scripts.html":
		return {
			document_url = url,
			content_type = "text/html",
			body = `<script type="application/ld+json">{"https://schema.example/name":"Ada"}</script><script type="application/ld+json">{"@graph":[{"https://schema.example/name":"Bea"}]}</script>`,
		}, true
	}
	return {}, false
}

@(test)
test_web_document_load_handles_html_base_and_alternate :: proc(t: ^testing.T) {
	options := Web_Document_Options{document_loader = web_test_loader}
	html, html_error := web_document_load("https://example.test/page.html", options)
	defer destroy_web_document(&html)
	testing.expect_value(t, html_error, Web_Document_Error.None)
	testing.expect_value(t, html.base_iri, "https://example.test/base/")
	testing.expect_value(t, html.document, `{"@id":"","https://schema.example/name":"Ada"}`)

	alternate, alternate_error := web_document_load("https://example.test/alternate.html", options)
	defer destroy_web_document(&alternate)
	testing.expect_value(t, alternate_error, Web_Document_Error.None)
	testing.expect_value(t, alternate.document_url, "https://example.test/alternate.jsonld")
	testing.expect(t, strings.contains(alternate.document, `"selected"`))

	_, multiple_error := web_document_load("https://example.test/multiple.json", options)
	testing.expect_value(t, multiple_error, Web_Document_Error.Multiple_Context_Links)
}

@(test)
test_web_document_expand_and_parse_apply_context_link :: proc(t: ^testing.T) {
	options := Web_Document_Options{document_loader = web_test_loader}
	expanded := strings.builder_make()
	defer strings.builder_destroy(&expanded)
	testing.expect_value(t, expand_url(&expanded, "https://example.test/record.json", {document_options = options}), Expand_Error.None)
	testing.expect(t, strings.contains(strings.to_string(expanded), `"https://schema.example/name"`))

	state := Collect_State{builder = strings.builder_make()}
	defer strings.builder_destroy(&state.builder)
	parse_error := parse_url("https://example.test/record.json", collect_quad, {document_options = options}, &state)
	testing.expect_value(t, parse_error.code, Error_Code.None)
	testing.expect(t, strings.contains(strings.to_string(state.builder), `<https://example.test/record.json> <https://schema.example/name> "Ada" .`))
}

@(test)
test_web_html_selection_preserves_algorithm_boundaries :: proc(t: ^testing.T) {
	options := Web_Document_Options{document_loader = web_test_loader}
	_, comment_error := web_document_load("https://example.test/unbalanced-comment.html", options)
	testing.expect_value(t, comment_error, Web_Document_Error.Invalid_HTML)

	expanded := strings.builder_make()
	defer strings.builder_destroy(&expanded)
	testing.expect_value(t, expand_url(&expanded, "https://example.test/empty.html", {document_options = options}), Expand_Error.Loading_Document_Failed)

	empty := Collect_State{builder = strings.builder_make()}
	defer strings.builder_destroy(&empty.builder)
	testing.expect_value(t, parse_url("https://example.test/empty.html", collect_quad, {document_options = options}, &empty).code, Error_Code.None)
	testing.expect_value(t, empty.count, 0)

	multiple := Collect_State{builder = strings.builder_make()}
	defer strings.builder_destroy(&multiple.builder)
	all_options := Web_Document_Options{document_loader = web_test_loader, extract_all_scripts = true}
	testing.expect_value(t, parse_url("https://example.test/multiple-scripts.html", collect_quad, {document_options = all_options}, &multiple).code, Error_Code.None)
	testing.expect_value(t, multiple.count, 2)
	testing.expect(t, strings.contains(strings.to_string(multiple.builder), " <https://schema.example/name> \"Bea\" _:"))
}
