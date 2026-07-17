package main

import "core:fmt"
import "core:os"
import "core:strings"
import rdf "../../../rdf"
import nquads "../../../rdf/nquads"

accept :: proc(_: rdf.Quad, _: rawptr) -> bool { return true }

Roundtrip_State :: struct {
	builder:     ^strings.Builder,
	write_error: nquads.Write_Error,
	quads:       u64,
}

roundtrip_sink :: proc(quad: rdf.Quad, data: rawptr) -> bool {
	state := cast(^Roundtrip_State)data
	state.write_error = nquads.write_quad(state.builder, quad)
	if state.write_error != .None do return false
	state.quads += 1
	return true
}

count_sink :: proc(_: rdf.Quad, data: rawptr) -> bool {
	(cast(^u64)data)^ += 1
	return true
}

verify_reader_variants :: proc(input, path: string, want_valid: bool, expected_quads: u64 = 0) -> bool {
	chunk_sizes := [3]int{1, 7, 0}
	for chunk_size in chunk_sizes {
		string_reader: strings.Reader
		reader := strings.to_reader(&string_reader, input)
		result := nquads.parse_reader(reader, accept, nquads.Reader_Options{chunk_size = chunk_size})
		is_valid := result.error.code == .None
		if is_valid != want_valid {
			fmt.eprintf("%s: reader chunk=%d expected valid=%v, got %s (%v) at %d:%d\n", path, chunk_size, want_valid, nquads.parse_error_message(result.error.code), result.error.code, result.error.line, result.error.column)
			return false
		}
		if want_valid && result.quads != expected_quads {
			fmt.eprintf("%s: reader chunk=%d expected %d quads, got %d\n", path, chunk_size, expected_quads, result.quads)
			return false
		}
	}
	return true
}

main :: proc() {
	if len(os.args) != 3 {
		fmt.eprintln("usage: nquads_runner <positive|negative> <test.nq>")
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
		err := nquads.parse(string(data), accept)
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
	err := nquads.parse(string(data), roundtrip_sink, &state)
	if err.code != .None {
		fmt.eprintf("%s: expected positive, got %s (%v) at %d:%d\n", os.args[2], nquads.parse_error_message(err.code), err.code, err.line, err.column)
		os.exit(1)
	}
	if state.write_error != .None {
		fmt.eprintf("%s: writer rejected parsed quad: %s (%v)\n", os.args[2], nquads.write_error_message(state.write_error), state.write_error)
		os.exit(1)
	}
	if !verify_reader_variants(string(data), os.args[2], true, state.quads) do os.exit(1)
	roundtrip_count: u64
	roundtrip_err := nquads.parse(strings.to_string(builder), count_sink, &roundtrip_count)
	if roundtrip_err.code != .None || roundtrip_count != state.quads {
		fmt.eprintf("%s: round-trip failed: %s (%v), expected %d quads, got %d\n", os.args[2], nquads.parse_error_message(roundtrip_err.code), roundtrip_err.code, state.quads, roundtrip_count)
		os.exit(1)
	}
}
