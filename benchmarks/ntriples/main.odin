package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import rdf "../../rdf"
import ntriples "../../rdf/ntriples"

TRIPLES :: #config(BENCH_RECORDS, 250_000)
ROUNDS  :: #config(BENCH_ROUNDS, 3)

count_sink :: proc(_: rdf.Triple, data: rawptr) -> bool {
	(cast(^u64)data)^ += 1
	return true
}

main :: proc() {
	if TRIPLES <= 0 || ROUNDS <= 0 {
		fmt.eprintln("BENCH_RECORDS and BENCH_ROUNDS must be positive")
		os.exit(2)
	}
	document := strings.builder_make_len_cap(0, TRIPLES * 64)
	defer strings.builder_destroy(&document)
	line := `<http://example.org/subject> <http://example.org/predicate> "value"@en .
`
	for _ in 0..<TRIPLES do strings.write_string(&document, line)
	input := strings.to_string(document)

	best_seconds := f64(1e30)
	for round in 1..=ROUNDS {
		count: u64
		started := time.now()
		err := ntriples.parse(input, count_sink, &count)
		seconds := time.duration_seconds(time.since(started))
		if err.code != .None || count != TRIPLES {
			fmt.eprintf("benchmark failed: %v, parsed %d triples\n", err.code, count)
			return
		}
		best_seconds = min(best_seconds, seconds)
		fmt.printf("round %d: %.2f M triples/s, %.2f MiB/s\n", round, f64(count) / seconds / 1e6, f64(len(input)) / seconds / 1024 / 1024)
	}
	fmt.printf(
		"best: %.2f M triples/s, %.2f MiB/s (%.2f MiB input, %d triples)\n",
		f64(TRIPLES) / best_seconds / 1e6,
		f64(len(input)) / best_seconds / 1024 / 1024,
		f64(len(input)) / 1024 / 1024,
		TRIPLES,
	)
}
