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
