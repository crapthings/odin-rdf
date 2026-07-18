package main

import "core:fmt"
import "core:os"
import "core:strings"
import rdf "../../rdf"
import nquads "../../rdf/nquads"
import ntriples "../../rdf/ntriples"
import rdfxml "../../rdf/rdfxml"
import trig "../../rdf/trig"
import turtle "../../rdf/turtle"

CASES     :: #config(FUZZ_CASES, 50_000)
MAX_BYTES :: #config(FUZZ_MAX_BYTES, 512)
SEED      :: u64(#config(FUZZ_SEED, 0x4f64696e52444631))

SEEDS := [13]string{
	`<urn:s> <urn:p> <urn:o> .`,
	`_:s <urn:p> "literal"@en .`,
	`<urn:s> <urn:p> "42"^^<http://www.w3.org/2001/XMLSchema#integer> .`,
	`<urn:\u2603> <urn:p> "escaped\n\u2603" .`,
	`<urn:s> <urn:p> <urn:o> <urn:g> .`,
	`_:s <urn:p> _:o _:g .`,
	`# comment\r\n<urn:s><urn:p>"value".`,
	`"bad subject" <relative> "unterminated`,
	`@prefix : <urn:v:> . :s :p (1 true [ :q "x" ]) .`,
	`BASE <https://example.test/a/> PREFIX : <v/> :s :p <o> .`,
	`<urn:s> <urn:p> '''long
literal''' .`,
	`<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description rdf:about="urn:s"/></rdf:RDF>`,
	`@prefix : <urn:v:> . { :s :p :o } :g { :s :p (1 true) . }`,
}

check_turtle :: proc(input: string, chunk_size: int, case_index: int) -> bool {
	memory_state: Parse_State
	memory := turtle.parse(input, accept_triple, {}, &memory_state)
	reader_state: Parse_State
	input_state: strings.Reader
	reader := strings.to_reader(&input_state, input)
	stream := turtle.parse_reader(reader, accept_triple, turtle.Reader_Options{chunk_size = chunk_size}, &reader_state)
	locations_differ := memory.code != .None && (memory.line != stream.error.line || memory.column != stream.error.column)
	if memory.code != stream.error.code || locations_differ || memory_state.count != reader_state.count {
		fmt.eprintf("Turtle mismatch at case %d chunk %d input=%q: memory=(%v %d:%d %d) reader=(%v %d:%d %d)\n", case_index, chunk_size, input, memory.code, memory.line, memory.column, memory_state.count, stream.error.code, stream.error.line, stream.error.column, reader_state.count)
		return false
	}
	return true
}

Parse_State :: struct {
	count: u64,
}

accept_triple :: proc(_: rdf.Triple, data: rawptr) -> bool {
	(cast(^Parse_State)data).count += 1
	return true
}

accept_quad :: proc(_: rdf.Quad, data: rawptr) -> bool {
	(cast(^Parse_State)data).count += 1
	return true
}

next_random :: proc(state: ^u64) -> u64 {
	x := state^
	x ~= x << 13
	x ~= x >> 7
	x ~= x << 17
	state^ = x
	return x
}

generate_case :: proc(buffer: []byte, index: int, random: ^u64) -> string {
	length := int(next_random(random) % u64(len(buffer) + 1))
	if index % 3 == 0 {
		seed := SEEDS[int(next_random(random) % u64(len(SEEDS)))]
		length = min(len(seed), len(buffer))
		copy(buffer[:length], transmute([]byte)seed[:length])
		mutations := 1 + int(next_random(random) % 8)
		for _ in 0..<mutations {
			if length == 0 do break
			at := int(next_random(random) % u64(length))
			buffer[at] = byte(next_random(random) >> 56)
		}
	} else {
		for i in 0..<length do buffer[i] = byte(next_random(random) >> 56)
	}
	return string(buffer[:length])
}

check_ntriples :: proc(input: string, chunk_size: int, case_index: int) -> bool {
	memory_state: Parse_State
	memory := ntriples.parse(input, accept_triple, &memory_state)
	reader_state: Parse_State
	input_state: strings.Reader
	reader := strings.to_reader(&input_state, input)
	stream := ntriples.parse_reader(reader, accept_triple, ntriples.Reader_Options{chunk_size = chunk_size}, &reader_state)
	locations_differ := memory.code != .None && (memory.line != stream.error.line || memory.column != stream.error.column)
	if memory.code != stream.error.code || locations_differ || memory_state.count != reader_state.count {
		fmt.eprintf("N-Triples mismatch at case %d chunk %d input=%q: memory=(%v %d:%d %d) reader=(%v %d:%d %d)\n", case_index, chunk_size, input, memory.code, memory.line, memory.column, memory_state.count, stream.error.code, stream.error.line, stream.error.column, reader_state.count)
		return false
	}
	return true
}

check_nquads :: proc(input: string, chunk_size: int, case_index: int) -> bool {
	memory_state: Parse_State
	memory := nquads.parse(input, accept_quad, &memory_state)
	reader_state: Parse_State
	input_state: strings.Reader
	reader := strings.to_reader(&input_state, input)
	stream := nquads.parse_reader(reader, accept_quad, nquads.Reader_Options{chunk_size = chunk_size}, &reader_state)
	locations_differ := memory.code != .None && (memory.line != stream.error.line || memory.column != stream.error.column)
	if memory.code != stream.error.code || locations_differ || memory_state.count != reader_state.count {
		fmt.eprintf("N-Quads mismatch at case %d chunk %d input=%q: memory=(%v %d:%d %d) reader=(%v %d:%d %d)\n", case_index, chunk_size, input, memory.code, memory.line, memory.column, memory_state.count, stream.error.code, stream.error.line, stream.error.column, reader_state.count)
		return false
	}
	return true
}

check_rdfxml :: proc(input: string, chunk_size: int, case_index: int) -> bool {
	memory_state: Parse_State
	memory := rdfxml.parse(input, accept_quad, {}, &memory_state)
	reader_state: Parse_State
	input_state: strings.Reader
	reader := strings.to_reader(&input_state, input)
	stream := rdfxml.parse_reader(reader, accept_quad, rdfxml.Reader_Options{chunk_size = chunk_size}, &reader_state)
	locations_differ := memory.code != .None && (memory.line != stream.error.line || memory.column != stream.error.column)
	if memory.code != stream.error.code || locations_differ || memory_state.count != reader_state.count {
		fmt.eprintf("RDF/XML mismatch at case %d chunk %d input=%q: memory=(%v %d:%d %d) reader=(%v %d:%d %d)\n", case_index, chunk_size, input, memory.code, memory.line, memory.column, memory_state.count, stream.error.code, stream.error.line, stream.error.column, reader_state.count)
		return false
	}
	return true
}

check_trig :: proc(input: string, chunk_size: int, case_index: int) -> bool {
	memory_state: Parse_State
	memory := trig.parse(input, accept_quad, {}, &memory_state)
	reader_state: Parse_State
	input_state: strings.Reader
	reader := strings.to_reader(&input_state, input)
	stream := trig.parse_reader(reader, accept_quad, trig.Reader_Options{chunk_size = chunk_size}, &reader_state)
	locations_differ := memory.code != .None && (memory.line != stream.error.line || memory.column != stream.error.column)
	if memory.code != stream.error.code || locations_differ || memory_state.count != reader_state.count {
		fmt.eprintf("TriG mismatch at case %d chunk %d input=%q: memory=(%v %d:%d %d) reader=(%v %d:%d %d)\n", case_index, chunk_size, input, memory.code, memory.line, memory.column, memory_state.count, stream.error.code, stream.error.line, stream.error.column, reader_state.count)
		return false
	}
	return true
}

main :: proc() {
	if CASES <= 0 || MAX_BYTES <= 0 {
		fmt.eprintln("FUZZ_CASES and FUZZ_MAX_BYTES must be positive")
		os.exit(2)
	}
	buffer := make([]byte, MAX_BYTES)
	defer delete(buffer)
	random := SEED
	for case_index in 0..<CASES {
		input := generate_case(buffer, case_index, &random)
		chunk_size := 1 + int(next_random(&random) % 64)
		if !check_ntriples(input, chunk_size, case_index) || !check_nquads(input, chunk_size, case_index) || !check_turtle(input, chunk_size, case_index) || !check_rdfxml(input, chunk_size, case_index) || !check_trig(input, chunk_size, case_index) do os.exit(1)
	}
	fmt.printf("fuzz differential: %d cases, seed=0x%x, max_bytes=%d, 0 mismatches\n", CASES, SEED, MAX_BYTES)
}
