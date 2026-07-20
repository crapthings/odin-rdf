package turtle

import "core:testing"

@(test)
test_rfc3986_reference_resolution :: proc(t: ^testing.T) {
	base := "http://a/b/c/d;p?q"
	cases := []struct { reference, expected: string }{
		{"g:h", "g:h"}, {"g", "http://a/b/c/g"}, {"./g", "http://a/b/c/g"},
		{"g/", "http://a/b/c/g/"}, {"/g", "http://a/g"}, {"//g", "http://g"},
		{"?y", "http://a/b/c/d;p?y"}, {"g?y", "http://a/b/c/g?y"},
		{"#s", "http://a/b/c/d;p?q#s"}, {"g#s", "http://a/b/c/g#s"},
		{"", "http://a/b/c/d;p?q"}, {".", "http://a/b/c/"}, {"..", "http://a/b/"},
		{"../g", "http://a/b/g"}, {"../../g", "http://a/g"},
	}
	for item in cases {
		actual, ok := resolve_iri_reference(base, item.reference)
		testing.expect(t, ok)
		testing.expect_value(t, actual, item.expected)
		delete(actual)
	}
}

@(test)
test_rfc3986_reference_relativization :: proc(t: ^testing.T) {
	base := "https://w3c.github.io/json-ld-api/tests/compact/0066-in.jsonld"
	cases := []struct { target, expected: string }{
		{"https://w3c.github.io/json-ld-api/tests/compact/link", "link"},
		{"https://w3c.github.io/json-ld-api/tests/compact/0066-in.jsonld#fragment-works", "#fragment-works"},
		{"https://w3c.github.io/json-ld-api/tests/compact/0066-in.jsonld?query=works", "?query=works"},
		{"https://w3c.github.io/json-ld-api/tests/", "../"},
		{"https://w3c.github.io/json-ld-api/", "../../"},
		{"https://w3c.github.io/json-ld-api/parent#fragment", "../../parent#fragment"},
		{"http://localhost/@special", "./@special"},
	}
	for item in cases {
		actual, ok := relativize_iri_reference(base, item.target)
		// The localhost case deliberately uses a different base to exercise the
		// JSON-LD keyword-like path safeguard.
		if item.target == "http://localhost/@special" {
			delete(actual)
			actual, ok = relativize_iri_reference("http://localhost/", item.target)
		}
		testing.expect(t, ok)
		testing.expect_value(t, actual, item.expected)
		resolved, resolved_ok := resolve_iri_reference(item.target == "http://localhost/@special" ? "http://localhost/" : base, actual)
		testing.expect(t, resolved_ok)
		testing.expect_value(t, resolved, item.target)
		delete(resolved)
		delete(actual)
	}
	foreign_reference, relative := relativize_iri_reference(base, "http://example.org/scheme-relative")
	testing.expect(t, !relative)
	delete(foreign_reference)
}
