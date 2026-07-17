package turtle

import "core:strings"
import "core:testing"
import rdf ".."

@(test)
test_reader_matches_memory_across_tiny_chunks :: proc(t: ^testing.T) {
	input := `@base <http://example/> .
@prefix : <vocab/> .
<s> :items (1 [ :name '''multi
line''' ] true) .`
	memory := make([dynamic]rdf.Triple)
	defer delete(memory)
	memory_err := parse(input, collect, {}, &memory)
	testing.expect_value(t, memory_err.code, Error_Code.None)
	chunk_sizes := [3]int{1, 7, 0}
	for chunk_size in chunk_sizes {
		actual := make([dynamic]rdf.Triple)
		reader_state: strings.Reader
		reader := strings.to_reader(&reader_state, input)
		result := parse_reader(reader, collect, Reader_Options{chunk_size = chunk_size}, &actual)
		testing.expect_value(t, result.error.code, Error_Code.None)
		testing.expect_value(t, len(actual), len(memory))
		delete(actual)
	}
}

@(test)
test_reader_statement_limit_and_invalid_options :: proc(t: ^testing.T) {
	reader_state: strings.Reader
	reader := strings.to_reader(&reader_state, `<urn:s> <urn:p> <urn:o> .`)
	too_long := parse_reader(reader, proc(_: rdf.Triple, _: rawptr) -> bool { return true }, Reader_Options{chunk_size = 4, max_statement_bytes = 8})
	testing.expect_value(t, too_long.error.code, Error_Code.Statement_Too_Long)

	invalid_state: strings.Reader
	invalid_reader := strings.to_reader(&invalid_state, "")
	invalid := parse_reader(invalid_reader, proc(_: rdf.Triple, _: rawptr) -> bool { return true }, Reader_Options{chunk_size = -1})
	testing.expect_value(t, invalid.error.code, Error_Code.Invalid_Chunk_Size)

	many_state: strings.Reader
	many_input := `<urn:s> <urn:p> <urn:a> . <urn:s> <urn:p> <urn:b> .`
	many_reader := strings.to_reader(&many_state, many_input)
	count := 0
	many := parse_reader(many_reader, proc(_: rdf.Triple, data: rawptr) -> bool { (cast(^int)data)^ += 1; return true }, Reader_Options{chunk_size = 128, max_statement_bytes = 32}, &count)
	testing.expect_value(t, many.error.code, Error_Code.None)
	testing.expect_value(t, count, 2)
}

@(test)
test_reader_does_not_confuse_keyword_prefixes_or_escaped_punctuation :: proc(t: ^testing.T) {
	input := `@prefix base: <urn:base:> . @prefix : <urn:v:> . base:s :p :local\#name .<urn:s> :p :local\.name .`
	count := 0
	state: strings.Reader
	reader := strings.to_reader(&state, input)
	result := parse_reader(reader, proc(_: rdf.Triple, data: rawptr) -> bool { (cast(^int)data)^ += 1; return true }, Reader_Options{chunk_size = 1}, &count)
	testing.expect_value(t, result.error.code, Error_Code.None)
	testing.expect_value(t, count, 2)
}
