# Parser and formatter benchmark baseline

This baseline is an orientation point for detecting performance regressions,
not a portable performance guarantee. Results vary with the compiler, CPU,
thermal state, and background load.

## v0.31.0 reference

- Core revision: `b0e8aace031519e0737b6842b1159f6b1724e2bc`
- Date: 2026-07-22
- Odin: `dev-2026-07:819fdc7a8`
- Platform: Darwin x86_64
- Configuration: 3 processes, 250,000 records, 3 rounds, `-o:speed`

The table reports the range and median of each process's best round.

| Workload | Unit | Best-rate range | Median best rate | Median throughput |
| --- | --- | ---: | ---: | ---: |
| Compact Turtle | triples/s | 2.25–2.30 M | 2.26 M | 16.92 MiB/s |
| Turtle formatter | triples/s | 0.41–0.42 M | 0.41 M | 16.34 MiB/s output |
| Repeated N-Triples | triples/s | 2.76–2.86 M | 2.77 M | 192.76 MiB/s |
| Repeated N-Quads | quads/s | 1.31–1.39 M | 1.33 M | 127.10 MiB/s |
| Mixed N-Triples | triples/s | 3.38–3.82 M | 3.80 M | 209.50 MiB/s |
| Mixed N-Quads | quads/s | 1.65–1.87 M | 1.85 M | 124.86 MiB/s |

## Comparison policy

1. Run `./scripts/run-benchmarks.sh` from a clean checkout on the same machine
   and Odin revision.
2. Compare the median of the three per-process `best` rates, not a single
   round or the fastest observed value.
3. Re-run when the median moves by more than 10% in either direction.
4. Investigate a regression only when it repeats under a quiet, thermally
   stable environment.
5. Update this file intentionally when the compiler, workload, or a justified
   implementation change establishes a new baseline.

## Formatter profiling

The formatter baseline records output throughput. Record a platform-specific
peak-resident-memory measurement separately when making a formatter memory
claim: it retains the graph, sort index, and overlapping temporary/destination
output, so RSS is not portable across machines or allocator implementations.
