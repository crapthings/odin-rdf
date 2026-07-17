# Parser benchmark baseline

This baseline is an orientation point for detecting performance regressions,
not a portable performance guarantee. Results vary with the compiler, CPU,
thermal state, and background load.

## v0.4.0 reference

- Revision: `4ca83810c1aa4b1ab8b869087dedf8d1c94dccec`
- Date: 2026-07-17
- Odin: `dev-2026-07:819fdc7a8`
- Platform: Darwin x86_64
- Configuration: 3 processes, 250,000 records, 3 rounds, `-o:speed`

The table reports the range and median of each process's best round.

| Workload | Unit | Best-rate range | Median best rate | Median throughput |
| --- | --- | ---: | ---: | ---: |
| Compact Turtle | triples/s | 1.33–1.69 M | 1.64 M | 12.29 MiB/s |
| Repeated N-Triples | triples/s | 1.63–2.27 M | 1.73 M | 120.62 MiB/s |
| Repeated N-Quads | quads/s | 0.74–1.11 M | 0.92 M | 87.48 MiB/s |
| Mixed N-Triples | triples/s | 3.37–3.87 M | 3.81 M | 210.28 MiB/s |
| Mixed N-Quads | quads/s | 1.61–1.88 M | 1.84 M | 124.08 MiB/s |

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
