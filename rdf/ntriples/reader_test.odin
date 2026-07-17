package ntriples

import "core:strings"
import "core:testing"
import "core:io"
import rdf ".."

@(private) Reader_Test_State :: struct {
	count: int,
	last_object: [64]byte,
	last_len: int,
}

@(private) reader_test_sink :: proc(triple: rdf.Triple, data: rawptr) -> bool {
	state := cast(^Reader_Test_State)data
	state.count += 1
	state.last_len = copy(state.last_object[:], transmute([]byte)triple.object.value)
	return true
}

@(test)
test_parse_reader_across_tiny_chunks :: proc(t: ^testing.T) {
	input := "# header\r\n<urn:s> <urn:p> \"escaped \\u2603\" .\r<urn:s2><urn:p2><urn:o2>.\n"
	string_reader: strings.Reader
	reader := strings.to_reader(&string_reader, input)
	state: Reader_Test_State
	result := parse_reader(reader, reader_test_sink, Reader_Options{chunk_size = 1}, &state)
	testing.expect_value(t, result.error.code, Error_Code.None)
	testing.expect_value(t, result.triples, u64(2))
	testing.expect_value(t, state.count, 2)
	testing.expect_value(t, string(state.last_object[:state.last_len]), "urn:o2")
	testing.expect_value(t, result.bytes_read, u64(len(input)))
}

@(test)
test_parse_reader_reports_global_line :: proc(t: ^testing.T) {
	input := "\n# comment\n<urn:s> <urn:p> <urn:o> .\n<urn:bad> <urn:p>"
	string_reader: strings.Reader
	reader := strings.to_reader(&string_reader, input)
	result := parse_reader(reader, ignore, Reader_Options{chunk_size = 3})
	testing.expect_value(t, result.error.code, Error_Code.Unexpected_End)
	testing.expect_value(t, result.error.line, 4)
}

@(test)
test_parse_reader_preserves_physical_line_error_semantics :: proc(t: ^testing.T) {
	input := "<urn:s> <urn:p> \"broken\r<urn:s> <urn:p> <urn:o> ."
	memory := parse(input, ignore)
	string_reader: strings.Reader
	reader := strings.to_reader(&string_reader, input)
	stream := parse_reader(reader, ignore, Reader_Options{chunk_size = 1})
	testing.expect_value(t, memory.code, Error_Code.Expected_Term)
	testing.expect_value(t, stream.error.code, memory.code)
	testing.expect_value(t, stream.error.line, memory.line)
	testing.expect_value(t, stream.error.column, memory.column)
}

@(test)
test_parse_reader_enforces_line_limit :: proc(t: ^testing.T) {
	input := "# 123456789"
	string_reader: strings.Reader
	reader := strings.to_reader(&string_reader, input)
	result := parse_reader(reader, ignore, Reader_Options{chunk_size = 2, max_line_bytes = 8})
	testing.expect_value(t, result.error.code, Error_Code.Line_Too_Long)
	testing.expect_value(t, result.error.line, 1)
}

@(test)
test_parse_reader_accepts_exact_line_limit :: proc(t: ^testing.T) {
	input := "# 123456"
	string_reader: strings.Reader
	reader := strings.to_reader(&string_reader, input)
	result := parse_reader(reader, ignore, Reader_Options{chunk_size = 3, max_line_bytes = len(input)})
	testing.expect_value(t, result.error.code, Error_Code.None)
	testing.expect_value(t, result.bytes_read, u64(len(input)))
}

@(test)
test_parse_reader_enforces_triple_limit :: proc(t: ^testing.T) {
	input := "<urn:s1> <urn:p> <urn:o> .\n<urn:s2> <urn:p> <urn:o> .\n"
	string_reader: strings.Reader
	reader := strings.to_reader(&string_reader, input)
	state: Reader_Test_State
	result := parse_reader(reader, reader_test_sink, Reader_Options{chunk_size = 7, max_triples = 1}, &state)
	testing.expect_value(t, result.error.code, Error_Code.Triple_Limit)
	testing.expect_value(t, result.error.line, 2)
	testing.expect_value(t, result.triples, u64(1))
	testing.expect_value(t, state.count, 1)
}

@(test)
test_parse_reader_rejects_negative_options :: proc(t: ^testing.T) {
	string_reader: strings.Reader
	reader := strings.to_reader(&string_reader, "")
	result := parse_reader(reader, ignore, Reader_Options{chunk_size = -1})
	testing.expect_value(t, result.error.code, Error_Code.Invalid_Chunk_Size)
	testing.expect_value(t, result.bytes_read, u64(0))

	reader = strings.to_reader(&string_reader, "")
	result = parse_reader(reader, ignore, Reader_Options{max_line_bytes = -1})
	testing.expect_value(t, result.error.code, Error_Code.Invalid_Line_Limit)
	testing.expect_value(t, result.bytes_read, u64(0))
}

@(test)
test_parse_reader_requires_sink_before_reading :: proc(t: ^testing.T) {
	result := parse_reader(io.Reader{}, nil)
	testing.expect_value(t, result.error.code, Error_Code.Missing_Sink)
	testing.expect_value(t, result.bytes_read, u64(0))
}

@(test)
test_invalid_utf8_inside_comment_is_rejected :: proc(t: ^testing.T) {
	bytes := []byte{'#', ' ', 0xff, '\n'}
	err := parse(string(bytes), ignore)
	testing.expect_value(t, err.code, Error_Code.Invalid_UTF8)
}

@(private) broken_reader_proc :: proc(_: rawptr, mode: io.Stream_Mode, _: []byte, _: i64, _: io.Seek_From) -> (i64, io.Error) {
	if mode == .Read do return 0, .Unknown
	if mode == .Query do return io.query_utility({.Read})
	return 0, .Unsupported
}

@(private) stalled_reader_proc :: proc(_: rawptr, mode: io.Stream_Mode, _: []byte, _: i64, _: io.Seek_From) -> (i64, io.Error) {
	if mode == .Read do return 0, .None
	if mode == .Query do return io.query_utility({.Read})
	return 0, .Unsupported
}

@(test)
test_parse_reader_propagates_io_errors :: proc(t: ^testing.T) {
	result := parse_reader(io.Reader{procedure = broken_reader_proc}, ignore)
	testing.expect_value(t, result.error.code, Error_Code.Reader_Error)
	testing.expect_value(t, result.reader_error, io.Error.Unknown)
}

@(test)
test_parse_reader_detects_no_progress :: proc(t: ^testing.T) {
	result := parse_reader(io.Reader{procedure = stalled_reader_proc}, ignore, Reader_Options{chunk_size = 1})
	testing.expect_value(t, result.error.code, Error_Code.No_Progress)
	testing.expect_value(t, result.reader_error, io.Error.No_Progress)
}

@(test)
test_parser_handles_deterministic_random_bytes :: proc(t: ^testing.T) {
	state := u64(0x4d595df4d0f33173)
	buffer: [128]byte
	for length in 0..=len(buffer) {
		for _ in 0..<32 {
			for i in 0..<length {
				state = state * 6364136223846793005 + 1442695040888963407
				buffer[i] = byte(state >> 56)
			}
			_ = parse(string(buffer[:length]), ignore)
		}
	}
	testing.expect(t, true)
}

@(test)
test_parse_reader_preserves_blank_node_scope_across_lines :: proc(t: ^testing.T) {
	input := "_:same <urn:p> <urn:o> .\n_:same <urn:p> <urn:o> .\n"
	string_reader: strings.Reader
	reader := strings.to_reader(&string_reader, input)
	state: Scope_State
	result := parse_reader(reader, scope_sink, Reader_Options{chunk_size = 1}, &state)
	testing.expect_value(t, result.error.code, Error_Code.None)
	testing.expect_value(t, state.calls, 2)
	testing.expect(t, state.first != rdf.Blank_Node_Scope(0))
	testing.expect_value(t, state.first, state.second)
}
