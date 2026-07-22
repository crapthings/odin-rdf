package main

import "core:fmt"
import "core:strings"
import rdf "../../rdf"
import jsonld "../../rdf/jsonld"
import nquads "../../rdf/nquads"

// load_document is deliberately local and deterministic. Production callers
// provide their own HTTP client, including timeout, redirect, cache,
// authentication, and allow-list policy.
load_document :: proc(url: string, _: rawptr) -> (jsonld.Remote_Document, bool) {
	if url != "https://example.test/profile.html" do return {}, false
	return {
		document_url = url,
		content_type = "text/html",
		body = `<html><head><base href="https://example.test/people/"></head><body><script type="application/ld+json">{"@id":"ada","@context":{"name":"https://schema.org/name"},"name":"Ada Lovelace"}</script></body></html>`,
	}, true
}

write_quad :: proc(quad: rdf.Quad, user_data: rawptr) -> bool {
	output := cast(^strings.Builder)user_data
	return nquads.write_quad(output, quad) == .None
}

main :: proc() {
	output := strings.builder_make()
	defer strings.builder_destroy(&output)

	err := jsonld.parse_url(
		"https://example.test/profile.html",
		write_quad,
		{
			document_options = {
				document_loader = load_document,
				max_document_bytes = 4 * 1024,
				max_documents = 1,
			},
		},
		&output,
	)
	if err.code != .None {
		fmt.eprintln(jsonld.parse_error_message(err.code))
		return
	}

	fmt.print(strings.to_string(output))
}
