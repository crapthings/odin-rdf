![Abstract RDF graph flowing through a bounded streaming pipeline](docs/assets/odin-rdf-banner.jpg)

# odin-rdf

[![RDF 1.1](https://img.shields.io/badge/RDF-1.1-2563eb)](https://www.w3.org/TR/n-triples/)
![W3C syntax tests](https://img.shields.io/badge/W3C_syntax_tests-72%2F72-16a34a)
![W3C N-Quads tests](https://img.shields.io/badge/W3C_N--Quads-87%2F87-65a30d)
![Platforms](https://img.shields.io/badge/platforms-Linux_%7C_macOS_%7C_Windows-475569)
[![License: MIT](https://img.shields.io/badge/license-MIT-f59e0b)](LICENSE)

A small, streaming-first RDF toolkit for Odin, built around standards compliance and explicit memory ownership.

> The API may still evolve. The RDF 1.1 N-Triples and N-Quads parsers pass the pinned W3C syntax test suites used by this repository.

## Status and scope

Version `0.3.1` provides production-oriented RDF 1.1 N-Triples and N-Quads parsers and writers, plus an RDF dataset model. Both syntax packages share a tested internal term lexer and support complete UTF-8 input, escape decoding, strict syntax validation, bounded-memory streaming, and early termination through sink callbacks.

Turtle, RDF/XML, JSON-LD, graph storage, and SPARQL are not part of the current release. See the roadmap below for planned syntax support.

The project is tested with Odin `dev-2026-07` and CI tracks the current Odin toolchain on Linux, macOS, and Windows.

## Why odin-rdf?

- **Verified syntax compliance.** The pinned W3C RDF 1.1 suites cover all 72 N-Triples and 87 N-Quads syntax cases through memory and streaming entry points, including parser/writer round trips.
- **Predictable memory use.** `io.Reader` parsing is bounded by configurable chunk and line limits; callers can also cap emitted triples.
- **Designed for pipelines.** Sink callbacks let converters, database importers, and command-line tools process triples without materializing a graph.
- **Explicit lifetimes.** Public APIs document exactly how long input-backed and decoded strings remain valid.
- **Release gates that match library risk.** CI covers three operating systems, compiler vetting, memory tracking, and AddressSanitizer.

## How it fits

```mermaid
flowchart LR
    Memory[UTF-8 string] --> Parser[N-Triples / N-Quads parser]
    Reader[io.Reader] -->|bounded chunks| Parser
    Parser -->|sink callback| Converter[Format converter]
    Parser -->|sink callback| Database[Database importer]
    Parser -->|sink callback| Collector[In-memory collector]
```

## Design goals

- Treat RDF 1.1 as the stable baseline and introduce RDF 1.2 features only as explicit, experimental extensions.
- Keep parsers independent of files, in-memory graph implementations, and databases.
- Stream triples to a sink instead of requiring the entire graph to be retained in memory.
- Support chunked `io.Reader` input with configurable line and triple limits.
- Make string and allocator ownership clear at every public API boundary.
- Establish correctness with the official W3C tests before optimizing performance.
- Keep a standalone minimal example for developers who are new to Odin.

## Repository layout

```text
rdf/                 Syntax-independent RDF terms, triples, and quads
rdf/ntriples/        N-Triples parser, writer, and unit tests
rdf/nquads/          N-Quads parser, writer, and unit tests
examples/minimal/    Tiny educational example with no library dependency
examples/basic/      Streaming parser API example
tests/w3c/           Pinned W3C conformance test runner
tests/property/      Deterministic parser/reader/writer property tests
tests/fuzz/          Reproducible differential parser fuzzing harness
benchmarks/          Reproducible parser benchmarks
```

## API overview

- `ntriples.parse(input, sink)` parses a complete UTF-8 document already held in memory.
- `ntriples.parse_scoped(input, sink, scope)` is an advanced syntax-integration adapter. Callers must provide a non-zero scope when parsed blank nodes need document identity.
- `ntriples.parse_reader(reader, sink, options)` parses incrementally with bounded memory. Defaults are a 64 KiB read buffer and a 16 MiB maximum line length.
- `ntriples.write_triple(builder, triple)` validates a triple and atomically appends canonical-layout N-Triples.
- `nquads.parse`, `nquads.parse_reader`, and `nquads.write_quad` provide the corresponding RDF dataset pipeline.
- `rdf.literal`, `rdf.language_literal`, and `rdf.typed_literal` construct literals without ambiguous language/datatype combinations.
- `rdf.validate_term_structure` and `rdf.validate_triple_structure` check syntax-independent RDF data-model invariants.
- Every public error enum has a matching stable, allocation-free message function across `rdf`, `ntriples`, and `nquads`.

Strings passed to a sink may point into the caller's input or a temporary parser buffer. They are valid only for the duration of that callback. Copy values or encode them into application-owned IDs before returning if they need to outlive the callback.

RDF term constructors establish datatype invariants but intentionally leave lexical validation to format parsers and writers. Parsed blank nodes carry a non-zero document scope: repeated labels within one parse identify the same node, while equal labels from independent parser invocations do not. Manually constructed blank nodes use scope zero unless a scope is supplied.

## Getting started

Clone or vendor this repository into your Odin source tree, then import the packages by path. The basic streaming interface looks like this:

```odin
package main

import "core:fmt"
import rdf "path/to/odin-rdf/rdf"
import ntriples "path/to/odin-rdf/rdf/ntriples"

print_triple :: proc(triple: rdf.Triple, _: rawptr) -> bool {
	fmt.println(triple.subject.value, triple.predicate.value, triple.object.value)
	return true
}

main :: proc() {
	input := `<https://example.com/alice> <https://example.com/name> "Alice"@en .`
	if err := ntriples.parse(input, print_triple); err.code != .None {
		fmt.eprintf("line %d, column %d: %s\n", err.line, err.column, ntriples.parse_error_message(err.code))
	}
}
```

See [`examples/basic`](examples/basic/main.odin) for a runnable version and [`rdf/ntriples/reader.odin`](rdf/ntriples/reader.odin) for bounded-memory `io.Reader` parsing options.

For datasets, the callback receives an `rdf.Quad`; `has_graph == false` denotes the default graph without inventing a sentinel RDF term:

```odin
print_quad :: proc(quad: rdf.Quad, _: rawptr) -> bool {
	if quad.has_graph {
		fmt.println(quad.subject.value, quad.predicate.value, quad.object.value, quad.graph.value)
	} else {
		fmt.println(quad.subject.value, quad.predicate.value, quad.object.value, "(default graph)")
	}
	return true
}

err := nquads.parse(`<urn:s> <urn:p> <urn:o> <urn:g> .`, print_quad)
```

See [`examples/nquads`](examples/nquads/main.odin) for the complete runnable example.

## Verification

```sh
odin check rdf -no-entry-point
odin test rdf
odin test rdf/ntriples
odin test rdf/nquads
odin test tests/property
odin run tests/fuzz -o:speed -sanitize:address
odin run examples/minimal
odin run examples/basic
./scripts/run-w3c-tests.sh
./scripts/run-w3c-nquads-tests.sh
./scripts/run-benchmarks.sh
```

## Roadmap

1. Implement Turtle over the shared lexical foundation according to the
   [parser design](docs/turtle-design.md).
2. Add a buffered, batch-oriented writer API after profiling real converter workloads.
3. Evaluate storage and SPARQL APIs after the syntax layer is broader.

## License

The repository is named `odin-rdf`, while the core package is `rdf`. The project is available under the MIT License.
