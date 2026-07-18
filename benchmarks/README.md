# Parser and formatter benchmarks

`run-benchmarks.sh` runs parser and formatter workloads in fresh processes:

- a repeated language-literal N-Triples statement;
- the corresponding named-graph N-Quads statement; and
- compact Turtle with prefixes, a blank-node property list, and a collection;
- mixed N-Triples and N-Quads documents containing IRIs, blank nodes, simple,
  language, typed, Unicode, and escaped literals, plus default and named graphs.
- a complete Turtle graph with two triples per subject, formatted with one
  explicit prefix and grouped predicate lists.

The defaults run 250,000 records for three rounds in three processes. Override
them for a smoke run without changing the benchmark sources:

```sh
BENCH_RUNS=1 BENCH_RECORDS=1000 BENCH_ROUNDS=1 ./scripts/run-benchmarks.sh
```

Results describe one revision, compiler, machine, and workload. Retain the
revision and configuration header when comparing changes; do not present them
as cross-machine performance claims.

The formatter workload builds the complete graph before timing begins. Its peak
memory is necessarily linear in the retained graph and output because
`format_triples` sorts an index, builds a complete temporary document, then
atomically appends it to the destination. Measure peak resident memory with a
platform profiler when setting a production `--max-triples` policy.

The repository keeps a manually reviewed [reference baseline](baseline.md).
Compare the median of the per-process `best` results on the same machine,
compiler, and configuration. A repeatable regression greater than 10% warrants
investigation; it is deliberately not a noisy CI failure threshold.
