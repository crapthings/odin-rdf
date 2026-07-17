package nquads

import "core:strings"
import "core:testing"
import rdf ".."

@(private) Count_State :: struct { count: int }

@(private) count_sink :: proc(_: rdf.Quad, data: rawptr) -> bool {
	(cast(^Count_State)data).count += 1
	return true
}

@(test)
test_parse_reader_tiny_chunks_and_scope :: proc(t: ^testing.T) {
	input := "_:s <urn:p> <urn:o> _:g .\r\n_:s <urn:p> <urn:o> _:g .\n"
	reader_state: strings.Reader
	reader := strings.to_reader(&reader_state, input)
	state: Count_State
	result := parse_reader(reader, count_sink, Reader_Options{chunk_size = 1}, &state)
	testing.expect_value(t, result.error.code, Error_Code.None)
	testing.expect_value(t, result.quads, u64(2))
	testing.expect_value(t, state.count, 2)
	testing.expect_value(t, result.bytes_read, u64(len(input)))
}

@(test)
test_parse_reader_limits :: proc(t: ^testing.T) {
	input := "<urn:s> <urn:p> <urn:o> .\n<urn:s> <urn:p> <urn:o> .\n"
	reader_state: strings.Reader
	reader := strings.to_reader(&reader_state, input)
	result := parse_reader(reader, ignore, Reader_Options{chunk_size = 2, max_quads = 1})
	testing.expect_value(t, result.error.code, Error_Code.Quad_Limit)
	testing.expect_value(t, result.quads, u64(1))

	reader = strings.to_reader(&reader_state, "123456")
	result = parse_reader(reader, ignore, Reader_Options{chunk_size = 2, max_line_bytes = 4})
	testing.expect_value(t, result.error.code, Error_Code.Line_Too_Long)
}

@(test)
test_parse_reader_rejects_invalid_options :: proc(t: ^testing.T) {
	reader_state: strings.Reader
	reader := strings.to_reader(&reader_state, "")
	result := parse_reader(reader, ignore, Reader_Options{chunk_size = -1})
	testing.expect_value(t, result.error.code, Error_Code.Invalid_Chunk_Size)
	reader = strings.to_reader(&reader_state, "")
	result = parse_reader(reader, ignore, Reader_Options{max_line_bytes = -1})
	testing.expect_value(t, result.error.code, Error_Code.Invalid_Line_Limit)
}
