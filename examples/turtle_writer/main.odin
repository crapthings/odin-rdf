package main

import "core:fmt"
import "core:strings"
import rdf "../../rdf"
import turtle "../../rdf/turtle"

Serialize_State :: struct {
	builder: ^strings.Builder,
	options: turtle.Writer_Options,
	error:   turtle.Write_Error,
}

serialize :: proc(triple: rdf.Triple, data: rawptr) -> bool {
	state := cast(^Serialize_State)data
	state.error = turtle.write_triple(state.builder, triple, state.options)
	return state.error == .None
}

main :: proc() {
	prefixes := []turtle.Prefix{
		{label = "ex", namespace = "https://example.com/"},
		{label = "v", namespace = "https://example.com/vocab/"},
	}
	options := turtle.Writer_Options{prefixes = prefixes}
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	if err := turtle.write_prefixes(&builder, prefixes); err != .None {
		fmt.eprintln(turtle.write_error_message(err))
		return
	}

	input := `@prefix ex: <https://example.com/> .
@prefix v: <https://example.com/vocab/> .
ex:alice v:name "Alice"@en .`
	state := Serialize_State{builder = &builder, options = options}
	if err := turtle.parse(input, serialize, {}, &state); err.code != .None {
		fmt.eprintf("line %d, column %d: %s\n", err.line, err.column, turtle.parse_error_message(err.code))
		return
	}
	if state.error != .None {
		fmt.eprintln(turtle.write_error_message(state.error))
		return
	}
	fmt.print(strings.to_string(builder))
}
