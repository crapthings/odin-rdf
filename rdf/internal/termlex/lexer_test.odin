package termlex

import "core:strings"
import "core:testing"

@(test)
test_iriref_decoding_is_separate_from_absolute_policy :: proc(t: ^testing.T) {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)

	relative := Scanner{input = `<path/\u0061>`, line = 1, column = 1}
	value, err := read_iriref(&relative, &builder)
	testing.expect_value(t, err.code, Error_Code.None)
	testing.expect_value(t, value, "path/a")
	testing.expect_value(t, relative.pos, len(relative.input))

	strings.builder_reset(&builder)
	absolute_only := Scanner{input = `<path/a>`, line = 1, column = 1}
	_, absolute_err := read_iri(&absolute_only, &builder)
	testing.expect_value(t, absolute_err.code, Error_Code.Invalid_IRI)
	testing.expect_value(t, absolute_err.line, 1)
	testing.expect_value(t, absolute_err.column, 8)
}

@(test)
test_iriref_reuses_existing_lexical_validation :: proc(t: ^testing.T) {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)

	s := Scanner{input = `<bad value>`, line = 3, column = 4}
	_, err := read_iriref(&s, &builder)
	testing.expect_value(t, err.code, Error_Code.Expected_IRI)
	testing.expect_value(t, err.line, 3)
	testing.expect_value(t, err.column, 8)
}
