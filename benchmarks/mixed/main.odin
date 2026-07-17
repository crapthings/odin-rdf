package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import rdf "../../rdf"
import nquads "../../rdf/nquads"
import ntriples "../../rdf/ntriples"

RECORDS :: #config(BENCH_RECORDS, 250_000)
ROUNDS  :: #config(BENCH_ROUNDS, 3)

TRIPLE_LINES := [8]string{
	`<https://example.test/alice> <https://schema.test/name> "Alice"@en .
`,
	`_:person.1 <https://schema.test/knows> _:person_2 .
`,
	`<urn:escaped:\u2603> <urn:label> "line\nquote\" slash\\ snowman \u2603" .
`,
	`<urn:item:42> <urn:value> "42"^^<http://www.w3.org/2001/XMLSchema#integer> .
`,
	`<urn:item:empty> <urn:value> "" .
`,
	`_:café <urn:label> "Δημήτρης"@el .
`,
	`<tag:example.test,2026:subject> <urn:link> <https://example.test/resource?q=1> .
`,
	`_:n_23 <urn:emoji> "☃ 😀" .
`,
}

QUAD_LINES := [8]string{
	`<https://example.test/alice> <https://schema.test/name> "Alice"@en <urn:graph:people> .
`,
	`_:person.1 <https://schema.test/knows> _:person_2 _:graph_1 .
`,
	`<urn:escaped:\u2603> <urn:label> "line\nquote\" slash\\ snowman \u2603" <urn:graph:escaped> .
`,
	`<urn:item:42> <urn:value> "42"^^<http://www.w3.org/2001/XMLSchema#integer> .
`,
	`<urn:item:empty> <urn:value> "" <urn:graph:values> .
`,
	`_:café <urn:label> "Δημήτρης"@el _:γράφημα .
`,
	`<tag:example.test,2026:subject> <urn:link> <https://example.test/resource?q=1> <urn:graph:links> .
`,
	`_:n_23 <urn:emoji> "☃ 😀" .
`,
}

count_triple :: proc(_: rdf.Triple, data: rawptr) -> bool {
	(cast(^u64)data)^ += 1
	return true
}

count_quad :: proc(_: rdf.Quad, data: rawptr) -> bool {
	(cast(^u64)data)^ += 1
	return true
}

build_document :: proc(lines: []string) -> strings.Builder {
	document := strings.builder_make_len_cap(0, RECORDS * 80)
	for i in 0..<RECORDS do strings.write_string(&document, lines[i % len(lines)])
	return document
}

benchmark_ntriples :: proc(input: string) {
	best_seconds := f64(1e30)
	for round in 1..=ROUNDS {
		count: u64
		started := time.now()
		err := ntriples.parse(input, count_triple, &count)
		seconds := time.duration_seconds(time.since(started))
		if err.code != .None || count != RECORDS {
			fmt.eprintf("mixed N-Triples benchmark failed: %v, parsed %d records\n", err.code, count)
			os.exit(1)
		}
		best_seconds = min(best_seconds, seconds)
		fmt.printf("round %d: %.2f M triples/s, %.2f MiB/s\n", round, f64(count) / seconds / 1e6, f64(len(input)) / seconds / 1024 / 1024)
	}
	fmt.printf("best: %.2f M triples/s, %.2f MiB/s (%.2f MiB mixed input, %d triples)\n", f64(RECORDS) / best_seconds / 1e6, f64(len(input)) / best_seconds / 1024 / 1024, f64(len(input)) / 1024 / 1024, RECORDS)
}

benchmark_nquads :: proc(input: string) {
	best_seconds := f64(1e30)
	for round in 1..=ROUNDS {
		count: u64
		started := time.now()
		err := nquads.parse(input, count_quad, &count)
		seconds := time.duration_seconds(time.since(started))
		if err.code != .None || count != RECORDS {
			fmt.eprintf("mixed N-Quads benchmark failed: %v, parsed %d records\n", err.code, count)
			os.exit(1)
		}
		best_seconds = min(best_seconds, seconds)
		fmt.printf("round %d: %.2f M quads/s, %.2f MiB/s\n", round, f64(count) / seconds / 1e6, f64(len(input)) / seconds / 1024 / 1024)
	}
	fmt.printf("best: %.2f M quads/s, %.2f MiB/s (%.2f MiB mixed input, %d quads)\n", f64(RECORDS) / best_seconds / 1e6, f64(len(input)) / best_seconds / 1024 / 1024, f64(len(input)) / 1024 / 1024, RECORDS)
}

main :: proc() {
	if RECORDS <= 0 || ROUNDS <= 0 {
		fmt.eprintln("BENCH_RECORDS and BENCH_ROUNDS must be positive")
		os.exit(2)
	}
	triples := build_document(TRIPLE_LINES[:])
	defer strings.builder_destroy(&triples)
	quads := build_document(QUAD_LINES[:])
	defer strings.builder_destroy(&quads)
	fmt.println("Mixed N-Triples")
	benchmark_ntriples(strings.to_string(triples))
	fmt.println("\nMixed N-Quads")
	benchmark_nquads(strings.to_string(quads))
}
