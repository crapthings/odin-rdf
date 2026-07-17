package main

import "core:fmt"
import "core:os"
import "core:strings"
import rdf "../../../rdf"
import ntriples "../../../rdf/ntriples"

accept :: proc(_: rdf.Triple, _: rawptr) -> bool { return true }

Roundtrip_State :: struct {
	builder: ^strings.Builder,
	write_error: ntriples.Write_Error,
	triples: u64,
}

roundtrip_sink :: proc(triple: rdf.Triple, data: rawptr) -> bool {
	state := cast(^Roundtrip_State)data
	state.write_error = ntriples.write_triple(state.builder, triple)
	if state.write_error != .None do return false
	state.triples += 1
	return true
}

count_sink :: proc(_: rdf.Triple, data: rawptr) -> bool {
	(cast(^u64)data)^ += 1
	return true
}

verify_reader_variants :: proc(input, path: string, want_valid: bool, expected_triples: u64 = 0) -> bool {
	chunk_sizes := [3]int{1, 7, 0}
	for chunk_size in chunk_sizes {
		string_reader: strings.Reader
		reader := strings.to_reader(&string_reader, input)
		result := ntriples.parse_reader(reader, accept, ntriples.Reader_Options{chunk_size = chunk_size})
		is_valid := result.error.code == .None
		if is_valid != want_valid {
			fmt.eprintf("%s: reader chunk=%d expected valid=%v, got %s (%v) at %d:%d\n", path, chunk_size, want_valid, ntriples.parse_error_message(result.error.code), result.error.code, result.error.line, result.error.column)
			return false
		}
		if want_valid && result.triples != expected_triples {
			fmt.eprintf("%s: reader chunk=%d expected %d triples, got %d\n", path, chunk_size, expected_triples, result.triples)
			return false
		}
	}
	return true
}

main :: proc() {
	if len(os.args) != 3 {
		fmt.eprintln("usage: runner <positive|negative> <test.nt>")
		os.exit(2)
	}
	data, read_err := os.read_entire_file(os.args[2], context.allocator)
	if read_err != nil {
		fmt.eprintf("cannot read %s: %v\n", os.args[2], read_err)
		os.exit(2)
	}
	defer delete(data)
	want_valid := os.args[1] == "positive"
	if !want_valid {
		err := ntriples.parse(string(data), accept)
		if err.code == .None {
			fmt.eprintf("%s: expected negative, got valid input\n", os.args[2])
			os.exit(1)
		}
		if !verify_reader_variants(string(data), os.args[2], false) do os.exit(1)
		return
	}

	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	state := Roundtrip_State{builder = &builder}
	err := ntriples.parse(string(data), roundtrip_sink, &state)
	if (err.code == .None) != want_valid {
		fmt.eprintf("%s: expected %s, got %s (%v) at %d:%d\n", os.args[2], os.args[1], ntriples.parse_error_message(err.code), err.code, err.line, err.column)
		os.exit(1)
	}
	if state.write_error != .None {
		fmt.eprintf("%s: writer rejected parsed triple: %s (%v)\n", os.args[2], ntriples.write_error_message(state.write_error), state.write_error)
		os.exit(1)
	}
	if !verify_reader_variants(string(data), os.args[2], true, state.triples) do os.exit(1)
	roundtrip_count: u64
	roundtrip_err := ntriples.parse(strings.to_string(builder), count_sink, &roundtrip_count)
	if roundtrip_err.code != .None || roundtrip_count != state.triples {
		fmt.eprintf("%s: round-trip failed: %s (%v), expected %d triples, got %d\n", os.args[2], ntriples.parse_error_message(roundtrip_err.code), roundtrip_err.code, state.triples, roundtrip_count)
		os.exit(1)
	}
}
