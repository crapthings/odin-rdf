package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import rdf "../../rdf"
import turtle "../../rdf/turtle"

RECORDS :: #config(BENCH_RECORDS, 250_000)
ROUNDS  :: #config(BENCH_ROUNDS, 3)
TRIPLES_PER_RECORD :: 2

NAME_PREDICATE :: "https://example.test/name"
TAG_PREDICATE  :: "https://example.test/tag"
TAG_OBJECT     :: "https://example.test/benchmark"

make_graph :: proc() -> ([dynamic]rdf.Triple, [dynamic]string) {
	triples := make([dynamic]rdf.Triple, 0, RECORDS * TRIPLES_PER_RECORD)
	owned := make([dynamic]string, 0, RECORDS)
	label := strings.builder_make()
	defer strings.builder_destroy(&label)
	for i in 0..<RECORDS {
		strings.write_string(&label, "https://example.test/item/")
		strings.write_int(&label, i)
		subject_value := strings.clone(strings.to_string(label)) or_else ""
		append(&owned, subject_value)
		subject := rdf.iri(subject_value)
		append(&triples, rdf.Triple{subject, rdf.iri(NAME_PREDICATE), rdf.literal("benchmark")})
		append(&triples, rdf.Triple{subject, rdf.iri(TAG_PREDICATE), rdf.iri(TAG_OBJECT)})
		strings.builder_reset(&label)
	}
	return triples, owned
}

main :: proc() {
	if RECORDS <= 0 || ROUNDS <= 0 {
		fmt.eprintln("BENCH_RECORDS and BENCH_ROUNDS must be positive")
		os.exit(2)
	}
	triples, owned := make_graph()
	defer {
		for value in owned do delete(value)
		delete(owned)
		delete(triples)
	}

	prefixes := []turtle.Prefix{{label = "ex", namespace = "https://example.test/"}}
	options := turtle.Format_Options{prefixes = prefixes, prefix_policy = .Explicit_Only}
	output := strings.builder_make()
	defer strings.builder_destroy(&output)
	best_seconds := f64(1e30)
	output_bytes := 0
	for round in 1..=ROUNDS {
		strings.builder_reset(&output)
		started := time.now()
		err := turtle.format_triples(&output, triples[:], options)
		seconds := time.duration_seconds(time.since(started))
		output_bytes = len(strings.to_string(output))
		if err != .None || output_bytes == 0 {
			fmt.eprintf("formatter benchmark failed: %v, output bytes %d\n", err, output_bytes)
			os.exit(1)
		}
		best_seconds = min(best_seconds, seconds)
		formatted := f64(len(triples)) / seconds / 1e6
		throughput := f64(output_bytes) / seconds / 1024 / 1024
		fmt.printf("round %d: %.2f M triples/s, %.2f MiB/s output\n", round, formatted, throughput)
	}
	fmt.printf(
		"best: %.2f M triples/s, %.2f MiB/s output (%.2f MiB output, %d triples)\n",
		f64(len(triples)) / best_seconds / 1e6,
		f64(output_bytes) / best_seconds / 1024 / 1024,
		f64(output_bytes) / 1024 / 1024,
		len(triples),
	)
}
