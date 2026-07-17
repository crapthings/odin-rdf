package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import rdf "../../rdf"
import turtle "../../rdf/turtle"

RECORDS :: #config(BENCH_RECORDS, 250_000)
ROUNDS  :: #config(BENCH_ROUNDS, 3)
TRIPLES_PER_RECORD :: 7

STATEMENT :: `:alice :knows [ :name "Bob" ] ; :tags ("rdf" "odin") .
`

count_sink :: proc(_: rdf.Triple, data: rawptr) -> bool {
	(cast(^u64)data)^ += 1
	return true
}

main :: proc() {
	if RECORDS <= 0 || ROUNDS <= 0 {
		fmt.eprintln("BENCH_RECORDS and BENCH_ROUNDS must be positive")
		os.exit(2)
	}
	document := strings.builder_make_len_cap(0, RECORDS * len(STATEMENT) + 40)
	defer strings.builder_destroy(&document)
	strings.write_string(&document, "@prefix : <https://example.test/> .\n")
	for _ in 0..<RECORDS do strings.write_string(&document, STATEMENT)
	input := strings.to_string(document)
	expected := u64(RECORDS * TRIPLES_PER_RECORD)
	best_seconds := f64(1e30)
	for round in 1..=ROUNDS {
		count: u64
		started := time.now()
		err := turtle.parse(input, count_sink, {}, &count)
		seconds := time.duration_seconds(time.since(started))
		if err.code != .None || count != expected {
			fmt.eprintf("Turtle benchmark failed: %v, parsed %d of %d triples\n", err.code, count, expected)
			os.exit(1)
		}
		best_seconds = min(best_seconds, seconds)
		fmt.printf("round %d: %.2f M triples/s, %.2f MiB/s\n", round, f64(count) / seconds / 1e6, f64(len(input)) / seconds / 1024 / 1024)
	}
	fmt.printf("best: %.2f M triples/s, %.2f MiB/s (%.2f MiB compact Turtle, %d triples)\n", f64(expected) / best_seconds / 1e6, f64(len(input)) / best_seconds / 1024 / 1024, f64(len(input)) / 1024 / 1024, expected)
}
