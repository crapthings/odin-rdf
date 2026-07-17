package property

import "core:strings"
import "core:testing"
import rdf "../../rdf"
import turtle "../../rdf/turtle"

Turtle_State :: struct { count: int }

turtle_count :: proc(_: rdf.Triple, data: rawptr) -> bool {
	(cast(^Turtle_State)data).count += 1
	return true
}

@(test)
test_turtle_memory_reader_differential_random_bytes :: proc(t: ^testing.T) {
	random := u64(0x547572746c652d31)
	buffer: [256]byte
	chunk_sizes := [3]int{1, 7, 64}
	for _ in 0..<CASE_COUNT {
		length := int(next_random(&random) % u64(len(buffer) + 1))
		for i in 0..<length do buffer[i] = byte(next_random(&random) >> 56)
		input := string(buffer[:length])
		memory_state: Turtle_State
		memory := turtle.parse(input, turtle_count, {}, &memory_state)
		for chunk_size in chunk_sizes {
			reader_state: Turtle_State
			input_state: strings.Reader
			reader := strings.to_reader(&input_state, input)
			stream := turtle.parse_reader(reader, turtle_count, turtle.Reader_Options{chunk_size = chunk_size}, &reader_state)
			testing.expect_value(t, stream.error.code, memory.code)
			testing.expect_value(t, stream.error.line, memory.line)
			testing.expect_value(t, stream.error.column, memory.column)
			testing.expect_value(t, reader_state.count, memory_state.count)
		}
	}
}
