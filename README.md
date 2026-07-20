![Abstract RDF graph flowing through a bounded streaming pipeline](docs/assets/odin-rdf-banner.jpg)

# odin-rdf

[![RDF 1.1](https://img.shields.io/badge/RDF-1.1-2563eb)](https://www.w3.org/TR/n-triples/)
![W3C syntax tests](https://img.shields.io/badge/W3C_syntax_tests-72%2F72-16a34a)
![W3C N-Quads tests](https://img.shields.io/badge/W3C_N--Quads-87%2F87-65a30d)
![W3C Turtle tests](https://img.shields.io/badge/W3C_Turtle-313%2F313-4d7c0f)
![W3C JSON-LD core](https://img.shields.io/badge/W3C_JSON--LD_to--RDF_core-65%2F65-0f766e)
![W3C JSON-LD expansion core](https://img.shields.io/badge/W3C_JSON--LD_expansion_core-93%2F93-0f766e)
![W3C JSON-LD flattening core](https://img.shields.io/badge/W3C_JSON--LD_flattening_core-35%2F35-0f766e)
![W3C JSON-LD framing core](https://img.shields.io/badge/W3C_JSON--LD_framing_core-87%2F87-0f766e)
![W3C JSON-LD FromRDF core](https://img.shields.io/badge/W3C_JSON--LD_RDF--to--JSON--LD_core-30%2F30-0f766e)
![W3C JSON-LD compaction core](https://img.shields.io/badge/W3C_JSON--LD_compaction_core-66%2F66-0f766e)
![W3C RDF/XML core](https://img.shields.io/badge/W3C_RDF%2FXML_core-173%2F173-b45309)
![W3C TriG tests](https://img.shields.io/badge/W3C_TriG-355%2F355-15803d)
![W3C RDFC-1.0](https://img.shields.io/badge/W3C_RDFC--1.0-65%2F65-7c3aed)
![Platforms](https://img.shields.io/badge/platforms-Linux_%7C_macOS_%7C_Windows-475569)
[![License: MIT](https://img.shields.io/badge/license-MIT-f59e0b)](LICENSE)

A small, streaming-first RDF toolkit for Odin, built around standards compliance and explicit memory ownership.

> The API may still evolve. The RDF 1.1 N-Triples, N-Quads, Turtle, and TriG parsers pass the pinned W3C suites used by this repository; JSON-LD has documented Expansion, Flattening, to-RDF, expanded RDF-to-JSON-LD, and context-driven compaction cores, while RDF/XML has a documented to-RDF core profile.

## Status and scope

**Current release: `0.27.0`** — bounded, deterministic JSON-LD Expansion,
Flattening, and Framing, each backed by pinned W3C core gates. It adds both
standard JSON-LD 1.1 RDF direction mappings: `i18n-datatype` and
`compound-literal`.

It also supports sourced-context `@import` and enforced `@protected` terms
through the existing explicit document loader. JSON-LD direction mapping is
opt-in; the default RDF conversion deliberately omits `@direction`. Its gates
run 106 Expansion, 147 to-RDF, 46 RDF-to-JSON-LD, and 81 compaction vectors.

| Area | Available now | Important boundary |
| --- | --- | --- |
| RDF syntax | N-Triples, N-Quads, Turtle, TriG, RDF/XML | Parsers and record writers are designed for bounded pipelines. |
| JSON-LD | to-RDF, Expansion, Flattening, RDF-to-JSON-LD, context compaction, and Framing | Directional RDF round trips use opt-in `i18n-datatype` or `compound-literal`; the rest of the API remains out of scope. |
| Dataset tools | RDFC-1.0 canonicalization, hashing, comparison, and diff | Complete-dataset operations require an explicit admission bound. |
| CLI | Conversion, formatting, canonicalization, hashing, comparison, and diff | RDF/XML and JSON-LD output are explicit bounded batch targets. |

JSON-LD Framing supports recursive embedding, standard embed modes, defaults,
`@requireAll`, value/list patterns, basic reverse framing, bounded
`@included` selection, and bounded named-graph subframes / `@graph`
containers. Scoped graph storage, SPARQL, and the remaining Framing policy
matrix are outside the current scope. See the [JSON-LD processing profile](docs/jsonld-design.md)
for exact limits and supported behavior.

For version-by-version changes, see the [changelog](CHANGELOG.md).

The project is tested with Odin `dev-2026-07` and CI tracks the current Odin toolchain on Linux, macOS, and Windows.

## Why odin-rdf?

- **Verified syntax compliance.** The pinned W3C RDF 1.1 suites cover all 72 N-Triples, 87 N-Quads, 313 Turtle, and 355 TriG cases through memory and streaming entry points. JSON-LD runs 106 Expansion, 35 Flattening, 147 to-RDF, 46 RDF-to-JSON-LD, and 81 compaction core vectors; RDF/XML runs 173 core cases. RDFC-1.0 runs all 65 official canonicalization and resource-limit cases.
- **Predictable memory use.** `io.Reader` parsing is bounded by configurable chunk and line limits; callers can also cap emitted triples.
- **Bounded documents.** JSON-LD, RDF/XML, and TriG retain one explicitly limited document; neither performs implicit network I/O.
- **Designed for pipelines.** Sink callbacks let converters, database importers, and command-line tools process triples without materializing a graph.
- **Explicit lifetimes.** Public APIs document exactly how long input-backed and decoded strings remain valid.
- **Release gates that match library risk.** CI covers three operating systems, compiler vetting, memory tracking, and AddressSanitizer.

## How it fits

```mermaid
flowchart LR
    Memory[UTF-8 string] --> Parser[N-Triples / N-Quads / Turtle / TriG / JSON-LD / RDF/XML parser]
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
rdf/turtle/          Turtle parser, writer, formatter, IRI resolution, and bounded reader
rdf/jsonld/          Bounded JSON-LD document and dataset processor
rdf/rdfxml/          Bounded RDF/XML processor with batch and stateful writers
rdf/trig/            Bounded RDF 1.1 TriG parser and streaming-safe writer
rdf/canon/           Resource-bounded W3C RDFC-1.0 dataset canonicalization
rdf/dataset/         Owned, capacity-bounded dataset collector
rdf/convert/         Streaming syntax-to-syntax conversion adapter
cmd/odin-rdf/        Command-line converter built on the adapter
examples/minimal/    Tiny educational example with no library dependency
examples/basic/      Streaming parser API example
examples/turtle/     Turtle directives and compact graph example
examples/turtle_writer/ Streaming Turtle-to-Turtle conversion example
examples/turtle_formatter/ Batch Turtle formatting example
examples/rdfxml_writer/ Stateful RDF/XML document writer example
examples/conversion/  Conversion with explicit reader limits
tests/w3c/           Pinned W3C conformance test runner
tests/property/      Deterministic parser/reader/writer property tests
tests/fuzz/          Reproducible differential parser fuzzing harness
benchmarks/          Reproducible parser and formatter benchmarks
```

## API overview

The complete public surface, defaults, ownership rules, error conventions, and
reader behavior are collected in the [API reference](docs/api-reference.md).

- `ntriples.parse(input, sink)` parses a complete UTF-8 document already held in memory.
- `ntriples.parse_scoped(input, sink, scope)` is an advanced syntax-integration adapter. Callers must provide a non-zero scope when parsed blank nodes need document identity.
- `ntriples.parse_reader(reader, sink, options)` parses incrementally with bounded memory. Defaults are a 64 KiB read buffer and a 16 MiB maximum line length.
- `ntriples.write_triple(builder, triple)` validates a triple and atomically appends canonical-layout N-Triples.
- `nquads.parse`, `nquads.parse_reader`, and `nquads.write_quad` provide the corresponding RDF dataset pipeline.
- `turtle.parse(input, sink, options)` covers RDF 1.1 Turtle directives, relative IRIs, compact predicate/object lists, literal shorthands, property lists, and collections.
- `turtle.parse_reader(reader, sink, options)` preserves document state across bounded chunks with configurable statement, token, prefix-count/bytes, nesting, pending-triple, and emitted-triple limits.
- `jsonld.expand(builder, input, options)` atomically writes deterministic expanded JSON-LD before RDF conversion can discard document metadata such as ordinary `@index`; `jsonld.flatten(builder, input, options)` builds a bounded node-map from that expansion; and `jsonld.frame(builder, input, frame, options)` selects `@id`/`@type`/property matches and recursively embeds nested property frames into a context-directed `@graph` result. `jsonld.parse(input, sink, options)` and `jsonld.parse_reader(reader, sink, options)` transform a bounded JSON-LD document into RDF quads. It accepts `@language` and `@index` containers, including their `@set` combinations; ordinary `@index` annotations are intentionally discarded by RDF conversion, while custom index properties remain RDF statements. `jsonld.serialize(builder, quads, options)` atomically writes deterministic expanded JSON-LD for a complete bounded dataset, including named graphs, safe RDF list collapse, `rdf:JSON`, and optional native scalar output. `jsonld.compact(builder, quads, context, options)` produces deterministic, context-directed JSON-LD with language maps, round-trip-safe arrays, and native JSON scalar defaults. Remote contexts require an explicit loader callback.
- `rdfxml.parse(input, sink, options)` and `rdfxml.parse_reader(reader, sink, options)` transform a bounded RDF/XML document into default-graph RDF quads. They do not fetch external resources and preserve markup-bearing `rdf:parseType="Literal"` content as `rdf:XMLLiteral`.
- `rdfxml.write_triples(builder, triples)` atomically appends a deterministic RDF/XML document for a complete default graph. `rdfxml.init_document_writer`, `write_document_triple`, and `finish_document_writer` provide the separate stateful path for large streams with explicit root-level namespaces and a bounded blank-node map.
- `trig.parse(input, sink, options)` and `trig.parse_reader(reader, sink, options)` transform bounded RDF 1.1 TriG into default- and named-graph quads. They support directives, graph blocks, collections, and property lists.
- `trig.write_prefixes` and `trig.write_quad` atomically serialize explicit prefixes and individual dataset quads. Each named graph quad is emitted as an independent graph block, so output preserves order and stays streaming-safe without retaining a dataset.
- `trig.format_quads(builder, quads, options)` is the explicit batch path: it groups a complete dataset by graph, sorts and deduplicates quads, and can infer safe prefixes for terms and graph names.
- `canon.canonicalize(builder, quads, options)` atomically writes the W3C RDFC-1.0 canonical N-Quads form of a complete dataset. `canon.canonical_hash` produces its SHA-256 or SHA-384 hexadecimal digest, and `canon.isomorphic` compares canonical forms without relying on a digest. All three remove exact duplicate quads and enforce resource limits on input size, recursive work, and permutations.
- `dataset.Collector` copies transient quads and term strings into caller-owned storage with an optional quad admission limit. `dataset.triple_sink` adapts N-Triples and Turtle output to default-graph quads. It preserves order and duplicates; it is not a graph store.
- `turtle.write_prefixes`, `turtle.write_term`, and `turtle.write_triple` provide stable, atomic Turtle serialization with explicit prefix selection and IRIREF fallback.
- `turtle.format_triples(builder, triples, options)` produces a deterministic, grouped Turtle document from a complete triple collection. Its default policy infers safe prefixes; use `Prefix_Policy.Explicit_Only` when declarations must be caller-controlled.
- `convert.convert(reader, output, options)` connects the bounded readers and writers without retaining a graph; it rejects a named N-Quads graph when the selected output cannot represent it.
- `convert.Reader_Limits` provides one explicit source-resource policy across all conversions: record count for every syntax, physical-line bytes for N-Triples/N-Quads, top-level statement bytes for Turtle, and retained document bytes for JSON-LD/RDF/XML/TriG.
- `rdf.literal`, `rdf.language_literal`, and `rdf.typed_literal` construct literals without ambiguous language/datatype combinations.
- `rdf.validate_term_structure` and `rdf.validate_triple_structure` check syntax-independent RDF data-model invariants.
- Every public error enum has a matching stable, allocation-free message function across `rdf` and all syntax packages.

Strings passed to a sink may point into the caller's input or a temporary parser buffer. They are valid only for the duration of that callback. Copy values or encode them into application-owned IDs before returning if they need to outlive the callback.

Use `dataset.Collector` when retaining parser output is appropriate. It owns all
stored strings until `dataset.destroy` and makes the retention bound explicit:

```odin
import dataset "path/to/odin-rdf/rdf/dataset"
import trig "path/to/odin-rdf/rdf/trig"

collector: dataset.Collector
if dataset.init(&collector, {max_quads = 10_000}) != .None do return
defer dataset.destroy(&collector)

parse_error := trig.parse(input, dataset.sink, {}, &collector)
if parse_error.code == .Stopped && collector.last_error == .Quad_Limit {
    // The dataset admission limit was reached; no extra quad was retained.
}
```

RDF term constructors establish datatype invariants but intentionally leave lexical validation to format parsers and writers. Parsed blank nodes carry a non-zero document scope: repeated labels within one parse identify the same node, while equal labels from independent parser invocations do not. Manually constructed blank nodes use scope zero unless a scope is supplied.

Canonicalization is intentionally a complete-dataset operation, not a streaming
writer. It is useful for stable dataset comparison, signing pipelines, and test
fixtures. Its built-in limits reject adversarially complex blank-node graphs;
raise a specific limit only after setting an application-level admission policy.

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

Turtle accepts an optional initial base IRI and emits a statement only after it
has been completely validated:

```odin
import turtle "path/to/odin-rdf/rdf/turtle"

input := `@prefix ex: <https://example.com/> .
ex:alice a ex:Person ; ex:name "Alice"@en .`

err := turtle.parse(input, print_triple)
```

See [`examples/turtle`](examples/turtle/main.odin) for a complete example.

Turtle writing is streaming-safe: declare an explicit prefix table once, then
write every parsed triple directly to the destination. The writer chooses the
longest safe namespace match and otherwise preserves the IRI as `<...>`:

```odin
prefixes := []turtle.Prefix{{label = "ex", namespace = "https://example.com/"}}
options := turtle.Writer_Options{prefixes = prefixes}
turtle.write_prefixes(&builder, prefixes)
turtle.write_triple(&builder, triple, options)
```

See [`examples/turtle_writer`](examples/turtle_writer/main.odin) for a runnable
Turtle-to-Turtle streaming conversion example. It deliberately does not group
triples, infer prefixes, or reformat property lists and collections.

For a complete graph already retained by your application, use the batch
formatter instead. It sorts terms, groups repeated subjects and predicates,
uses `a` for `rdf:type`, removes exact duplicate triples, and writes only after
the entire document is valid. It does not preserve source ordering or comments:

```odin
options := turtle.Format_Options{
    prefixes = []turtle.Prefix{{label = "ex", namespace = "https://example.com/"}},
    prefix_policy = .Explicit_Only,
}
err := turtle.format_triples(&builder, triples, options)
```

See [`examples/turtle_formatter`](examples/turtle_formatter/main.odin) for a
runnable batch-formatting example.

## Command-line conversion

Build the repository command when you want a small, dependency-free conversion
tool:

```sh
odin build cmd/odin-rdf -out:odin-rdf

./odin-rdf convert input.ttl --output output.nt
./odin-rdf convert input.nt --to turtle \
  --prefix ex=https://example.com/ --output output.ttl
./odin-rdf convert input.trig --to jsonld --max-records 100000 --output output.jsonld
./odin-rdf convert input.nt --to jsonld --context context.jsonld --max-records 100000 --output compact.jsonld
cat input.nq | ./odin-rdf convert - --from nquads --to nquads > output.nq
./odin-rdf format input.ttl --output formatted.ttl
./odin-rdf format input.trig --output formatted.trig --max-quads 100000
./odin-rdf canon input.trig --output canonical.nq --max-quads 100000
./odin-rdf hash input.ttl --algorithm sha384
./odin-rdf compare previous.trig current.trig
./odin-rdf diff before.trig after.trig --output changes.nqdiff
```

Supported spellings are `ntriples`/`nt`, `nquads`/`nq`, `turtle`/`ttl`,
`jsonld`/`json-ld`/`json`, and
`rdfxml`/`rdf-xml`/`rdf/xml`/`rdf`/`xml`, plus `trig`. RDF/XML output is a
bounded batch target and requires `--max-records N`. For file paths, `convert` infers the
corresponding syntax from `.nt`, `.nq`, `.ttl`, `.jsonld`, `.json`, `.rdfxml`,
`.rdf`, `.xml`, or `.trig`; explicit `--from` and `--to` override that inference. `-` denotes
standard input or output and always requires the corresponding explicit format,
as do unrecognized extensions. File targets are streamed into a
same-directory temporary file and replace the destination only after the
conversion succeeds and the temporary file closes successfully. Standard output
is intentionally streaming for N-Triples, N-Quads, Turtle, and TriG, so a later
input error can leave earlier valid records on the pipe. RDF/XML and expanded
JSON-LD are the explicit batch exceptions: standard output remains empty until
their bounded dataset parses and serializes successfully. Add `--context PATH`
to a JSON-LD conversion for context-directed compaction; it requires a positive
`--max-records` bound and does not fetch remote contexts. Turtle and TriG prefixes are always explicit and repeatable;
use `--prefix =https://example.com/` for the default prefix.

N-Quads default-graph records convert to every available target, including
bounded RDF/XML and JSON-LD. Named graphs can target N-Quads, TriG, or JSON-LD;
the command rejects every lossy target rather than dropping the graph name.

`convert` can bound untrusted input with `--max-records N` for all source
syntaxes, `--max-line-bytes N` for N-Triples/N-Quads,
`--max-statement-bytes N` for Turtle, and `--max-document-bytes N` for JSON-LD,
RDF/XML, and TriG. RDF/XML and JSON-LD output require a positive `--max-records`
value as their retained-dataset admission bound. These are positive decimal values. A
file target is still replaced only after the whole conversion succeeds.

`format` accepts Turtle and TriG input. It infers `.ttl` or `.trig` for file
inputs; standard input requires `--from turtle` or `--from trig`. It parses the
complete graph or dataset before writing, so neither standard output nor a
target file receives partial formatted output on a parse or serialization
error. It infers safe prefixes by default; repeat `--prefix LABEL=NAMESPACE`
to provide declarations, and pass `--no-infer-prefixes` to use only those
explicit declarations. Use `--max-triples N` for Turtle or `--max-quads N` for
TriG to enforce an explicit retention bound; `N` must be a positive decimal
integer. Peak memory also includes a sorted index and, during atomic commit,
both temporary and destination formatted output. Treat the bound as a
graph-size admission policy rather than a byte-precise memory cap. Reproduce the formatter workload in
[`benchmarks`](benchmarks/README.md) on the target machine before choosing a
production value.

`canon`, `hash`, `compare`, and `diff` are the dataset-integrity commands. They accept
every supported input syntax and retain a complete owned dataset before doing
any work, so their standard output and file targets remain untouched on source
or canonicalization failure. `canon` writes canonical N-Quads, while `hash`
writes its lowercase hexadecimal SHA-256 digest by default (or SHA-384 with
`--algorithm sha384`). `compare` accepts two file paths, prints `equal` or
`different`, and exits 0, 1, or 2 for equality, difference, or an error.
`diff` accepts two file paths and emits a deterministic canonical N-Quads line
diff (`- ` for removed, `+ ` for added), returning 0 when equal, 1 when changed,
or 2 on error. It is not a minimum blank-node edit script: a structural change
can change canonical blank-node identifiers. Both commands accept independently
inferred input formats; `diff --output` is atomically replaced only after both
datasets canonicalize successfully.
`--max-quads N` bounds both collection and canonicalization and defaults to
100,000; source-side `--max-records`, `--max-line-bytes`,
`--max-statement-bytes`, and `--max-document-bytes` retain their normal
syntax-specific meanings. These commands supply integrity and
signing-protocol inputs, not a signature scheme, graph store, or query engine.

The [conversion design](docs/conversion-design.md) records the conversion
matrix, error behavior, and file-output safety policy.

Error helpers follow one stable naming convention: parsers expose
`parse_error_message`, writers expose `write_error_message`, and the core model
uses a descriptive `<operation>_error_message` name. These functions are
allocation-free; callers should branch on the enum code rather than message
text.

## Verification

```sh
odin check rdf -no-entry-point
odin test rdf
odin test rdf/ntriples
odin test rdf/nquads
odin test rdf/turtle
odin test rdf/jsonld
odin test rdf/rdfxml
odin test rdf/trig
odin test rdf/canon
odin test rdf/dataset
odin test rdf/convert
odin test cmd/odin-rdf
odin test tests/property
odin run tests/fuzz -o:speed -sanitize:address
odin run examples/minimal
odin run examples/basic
odin run examples/turtle
odin run examples/turtle_writer
odin run examples/turtle_formatter
odin run examples/conversion
odin run cmd/odin-rdf -- --help
./scripts/run-w3c-tests.sh
./scripts/run-w3c-nquads-tests.sh
./scripts/run-w3c-turtle-tests.sh
./scripts/run-w3c-jsonld-tests.sh
./scripts/run-w3c-jsonld-expand-tests.sh
./scripts/run-w3c-jsonld-flatten-tests.sh
./scripts/run-w3c-jsonld-framing-tests.sh
./scripts/run-w3c-jsonld-fromrdf-tests.sh
./scripts/run-w3c-jsonld-compact-tests.sh
./scripts/run-w3c-rdfxml-tests.sh
./scripts/run-w3c-trig-tests.sh
./scripts/run-w3c-rdf-canon-tests.sh
./scripts/run-benchmarks.sh
```

Maintainers should also follow the [release checklist](docs/releasing.md).
Performance comparisons use the documented [v0.4.0 baseline](benchmarks/baseline.md)
as an orientation point, never as a cross-machine claim or a hard CI threshold.

## Roadmap

1. Extend the JSON-LD Framing profile toward named-graph matching and scoped contexts; keep storage and SPARQL as separate product directions.

## License

The repository is named `odin-rdf`, while the core package is `rdf`. The project is available under the MIT License.
