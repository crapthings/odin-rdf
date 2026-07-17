package property

import "core:strings"
import "core:testing"
import rdf "../../rdf"
import nquads "../../rdf/nquads"
import ntriples "../../rdf/ntriples"

CASE_COUNT :: 512

next_random :: proc(state: ^u64) -> u64 {
	x := state^
	x ~= x << 13
	x ~= x >> 7
	x ~= x << 17
	state^ = x
	return x
}

random_iri :: proc(state: ^u64) -> rdf.Term {
	values := [5]string{
		"urn:odin-rdf:plain",
		"https://example.test/resource",
		"urn:odin-rdf:space path",
		"urn:odin-rdf:snowman:☃",
		"tag:example.test,2026:value",
	}
	return rdf.iri(values[next_random(state) % u64(len(values))])
}

random_blank_node :: proc(state: ^u64) -> rdf.Term {
	values := [5]string{"node", "node.1", "café", "n_23", "Δelta"}
	return rdf.blank_node(values[next_random(state) % u64(len(values))])
}

random_literal :: proc(state: ^u64) -> rdf.Term {
	values := [5]string{
		"plain",
		"line\nquote\" slash\\ tab\t",
		"Δημήτρης",
		"☃ 😀",
		"",
	}
	switch next_random(state) % 3 {
	case 0:
		return rdf.literal(values[next_random(state) % u64(len(values))])
	case 1:
		languages := [4]string{"en", "en-GB", "el", "zh-Hant"}
		return rdf.language_literal(
			values[next_random(state) % u64(len(values))],
			languages[next_random(state) % u64(len(languages))],
		)
	case:
		datatypes := [3]string{
			"http://www.w3.org/2001/XMLSchema#integer",
			"http://www.w3.org/2001/XMLSchema#dateTime",
			"urn:odin-rdf:datatype",
		}
		return rdf.typed_literal(
			values[next_random(state) % u64(len(values))],
			datatypes[next_random(state) % u64(len(datatypes))],
		)
	}
}

random_subject :: proc(state: ^u64) -> rdf.Term {
	if next_random(state) & 1 == 0 do return random_iri(state)
	return random_blank_node(state)
}

random_object :: proc(state: ^u64) -> rdf.Term {
	switch next_random(state) % 3 {
	case 0: return random_iri(state)
	case 1: return random_blank_node(state)
	case:   return random_literal(state)
	}
}

Triple_Write_State :: struct {
	builder:     ^strings.Builder,
	write_error: ntriples.Write_Error,
	count:       u64,
}

write_triple_sink :: proc(triple: rdf.Triple, data: rawptr) -> bool {
	state := cast(^Triple_Write_State)data
	state.write_error = ntriples.write_triple(state.builder, triple)
	if state.write_error != .None do return false
	state.count += 1
	return true
}

Quad_Write_State :: struct {
	builder:     ^strings.Builder,
	write_error: nquads.Write_Error,
	count:       u64,
}

write_quad_sink :: proc(quad: rdf.Quad, data: rawptr) -> bool {
	state := cast(^Quad_Write_State)data
	state.write_error = nquads.write_quad(state.builder, quad)
	if state.write_error != .None do return false
	state.count += 1
	return true
}

accept_triple :: proc(_: rdf.Triple, _: rawptr) -> bool { return true }
accept_quad :: proc(_: rdf.Quad, _: rawptr) -> bool { return true }

@(test)
test_ntriples_memory_reader_and_writer_property :: proc(t: ^testing.T) {
	seed := u64(0x4e2d547269706c65)
	source := strings.builder_make()
	defer strings.builder_destroy(&source)
	for _ in 0..<CASE_COUNT {
		triple := rdf.Triple{
			subject = random_subject(&seed),
			predicate = random_iri(&seed),
			object = random_object(&seed),
		}
		testing.expect_value(t, ntriples.write_triple(&source, triple), ntriples.Write_Error.None)
	}
	input := strings.to_string(source)

	memory := strings.builder_make()
	defer strings.builder_destroy(&memory)
	memory_state := Triple_Write_State{builder = &memory}
	parse_error := ntriples.parse(input, write_triple_sink, &memory_state)
	testing.expect_value(t, parse_error.code, ntriples.Error_Code.None)
	testing.expect_value(t, memory_state.write_error, ntriples.Write_Error.None)
	testing.expect_value(t, memory_state.count, u64(CASE_COUNT))
	testing.expect_value(t, strings.to_string(memory), input)

	chunk_sizes := [5]int{1, 2, 7, 64, 0}
	for chunk_size in chunk_sizes {
		reader_output := strings.builder_make()
		reader_state := Triple_Write_State{builder = &reader_output}
		input_reader_state: strings.Reader
		reader := strings.to_reader(&input_reader_state, input)
		result := ntriples.parse_reader(
			reader,
			write_triple_sink,
			ntriples.Reader_Options{chunk_size = chunk_size},
			&reader_state,
		)
		testing.expect_value(t, result.error.code, ntriples.Error_Code.None)
		testing.expect_value(t, reader_state.write_error, ntriples.Write_Error.None)
		testing.expect_value(t, reader_state.count, u64(CASE_COUNT))
		testing.expect_value(t, strings.to_string(reader_output), strings.to_string(memory))
		strings.builder_destroy(&reader_output)
	}
}

@(test)
test_nquads_memory_reader_and_writer_property :: proc(t: ^testing.T) {
	seed := u64(0x4e2d517561647321)
	source := strings.builder_make()
	defer strings.builder_destroy(&source)
	for _ in 0..<CASE_COUNT {
		triple := rdf.Triple{
			subject = random_subject(&seed),
			predicate = random_iri(&seed),
			object = random_object(&seed),
		}
		quad := rdf.default_graph_quad(triple)
		if next_random(&seed) & 1 != 0 {
			graph := next_random(&seed) & 1 == 0 ? random_iri(&seed) : random_blank_node(&seed)
			quad = rdf.named_graph_quad(triple, graph)
		}
		testing.expect_value(t, nquads.write_quad(&source, quad), nquads.Write_Error.None)
	}
	input := strings.to_string(source)

	memory := strings.builder_make()
	defer strings.builder_destroy(&memory)
	memory_state := Quad_Write_State{builder = &memory}
	parse_error := nquads.parse(input, write_quad_sink, &memory_state)
	testing.expect_value(t, parse_error.code, nquads.Error_Code.None)
	testing.expect_value(t, memory_state.write_error, nquads.Write_Error.None)
	testing.expect_value(t, memory_state.count, u64(CASE_COUNT))
	testing.expect_value(t, strings.to_string(memory), input)

	chunk_sizes := [5]int{1, 2, 7, 64, 0}
	for chunk_size in chunk_sizes {
		reader_output := strings.builder_make()
		reader_state := Quad_Write_State{builder = &reader_output}
		input_reader_state: strings.Reader
		reader := strings.to_reader(&input_reader_state, input)
		result := nquads.parse_reader(
			reader,
			write_quad_sink,
			nquads.Reader_Options{chunk_size = chunk_size},
			&reader_state,
		)
		testing.expect_value(t, result.error.code, nquads.Error_Code.None)
		testing.expect_value(t, reader_state.write_error, nquads.Write_Error.None)
		testing.expect_value(t, reader_state.count, u64(CASE_COUNT))
		testing.expect_value(t, strings.to_string(reader_output), strings.to_string(memory))
		strings.builder_destroy(&reader_output)
	}
}

@(test)
test_ntriples_random_bytes_memory_reader_differential :: proc(t: ^testing.T) {
	seed := u64(0x4e542d6279746573)
	buffer: [128]byte
	for _ in 0..<CASE_COUNT {
		length := int(next_random(&seed) % u64(len(buffer) + 1))
		for i in 0..<length do buffer[i] = byte(next_random(&seed) >> 56)
		input := string(buffer[:length])
		memory_error := ntriples.parse(input, accept_triple)
		chunk_sizes := [2]int{1, 7}
		for chunk_size in chunk_sizes {
			input_reader_state: strings.Reader
			reader := strings.to_reader(&input_reader_state, input)
			result := ntriples.parse_reader(reader, accept_triple, ntriples.Reader_Options{chunk_size = chunk_size})
			testing.expect_value(t, result.error.code, memory_error.code)
			testing.expect_value(t, result.error.line, memory_error.line)
			testing.expect_value(t, result.error.column, memory_error.column)
		}
	}
}

@(test)
test_nquads_random_bytes_memory_reader_differential :: proc(t: ^testing.T) {
	seed := u64(0x4e512d6279746573)
	buffer: [128]byte
	for _ in 0..<CASE_COUNT {
		length := int(next_random(&seed) % u64(len(buffer) + 1))
		for i in 0..<length do buffer[i] = byte(next_random(&seed) >> 56)
		input := string(buffer[:length])
		memory_error := nquads.parse(input, accept_quad)
		chunk_sizes := [2]int{1, 7}
		for chunk_size in chunk_sizes {
			input_reader_state: strings.Reader
			reader := strings.to_reader(&input_reader_state, input)
			result := nquads.parse_reader(reader, accept_quad, nquads.Reader_Options{chunk_size = chunk_size})
			testing.expect_value(t, result.error.code, memory_error.code)
			testing.expect_value(t, result.error.line, memory_error.line)
			testing.expect_value(t, result.error.column, memory_error.column)
		}
	}
}
