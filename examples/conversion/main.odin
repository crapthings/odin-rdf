package main

import "core:fmt"
import "core:strings"
import convert "../../rdf/convert"

main :: proc() {
	input_state: strings.Reader
	input := strings.to_reader(&input_state, "<https://example.com/alice> <https://example.com/name> \"Alice\" .\n")
	output := strings.builder_make()
	defer strings.builder_destroy(&output)
	result := convert.convert(input, strings.to_writer(&output), convert.Options{
		input = .N_Triples,
		output = .N_Quads,
		reader_limits = {
			max_records = 1_000,
			max_line_bytes = 64 * 1024,
		},
	})
	if result.error.code != .None {
		fmt.eprintln(convert.error_message(result.error.code), result.error.detail)
		return
	}
	fmt.print(strings.to_string(output))
}
