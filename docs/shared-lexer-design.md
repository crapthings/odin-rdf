# Shared term lexer design

## Motivation

N-Triples currently owns the proven RDF term scanner. N-Quads first tokenizes a
physical record, builds a synthetic N-Triples statement for its first three
terms, and builds another synthetic statement for a graph name. This preserves
correctness and blank-node identity, but repeats record scanning, allocates
temporary builders per quad, and couples one syntax package to another.

The refactor will extract a syntax-internal term lexer, migrate N-Triples without
observable change, then let N-Quads parse its four positions directly. Turtle is
not part of this refactor; its relative IRIs, prefixes, and richer grammar need a
separate layer above the shared lexical primitives.

## Boundary

The internal lexer will own:

- UTF-8 decoding and one-based source-position advancement;
- `UCHAR` and ECHAR decoding;
- absolute `IRIREF` parsing;
- blank-node label parsing with a caller-provided document scope;
- literal lexical forms, language tags, and datatype IRIs; and
- zero-copy slices for unescaped values plus caller-owned builders for decoded
  values.

Document and record grammars remain in their syntax packages. They own whitespace,
comments, line endings, triple/quad positions, terminating dots, sink control,
reader limits, and public error/result types. The internal lexer returns a small
syntax-neutral error enum and source position; each package maps it explicitly to
its existing public error code.

The package should live below both syntaxes (provisionally
`rdf/internal/termlex`) and must not become part of the documented public API.

## Compatibility invariants

The migration is accepted only when all of these remain true:

1. Public types, procedure signatures, enum values, and allocation-free messages
   do not change.
2. Every existing valid input emits the same RDF values and document-local
   blank-node scopes.
3. Every existing invalid input returns the same public error code, line, and
   column through memory and bounded-reader entry points.
4. Callback-scoped string lifetimes and zero-copy behavior remain unchanged.
5. Sink cancellation, reader limits, preserved I/O errors, and atomic writers
   retain their current semantics.
6. W3C N-Triples remains 72/72 and N-Quads remains 87/87; deterministic property
   tests, vet, AddressSanitizer, and all three operating systems remain green.

## Delivery sequence

1. Extract the scanner and term primitives, then migrate only N-Triples. This
   should be a mechanical change with no intended performance regression.
2. Replace N-Quads tokenization and synthetic statements with one direct scanner
   over each record. Remove its dependency on `rdf/ntriples` parsing.
3. Compare both stages with the frozen benchmark command and document results.
   Investigate an N-Triples regression above 5%. Require a material N-Quads
   improvement before removing the old implementation.

No public shared-lexer API, Turtle feature, or writer redesign belongs in these
steps.

## Implementation status

Both migration stages are complete. The syntax-internal lexer lives in
`rdf/internal/termlex`; N-Triples and N-Quads map its syntax-neutral errors
explicitly to their existing public error codes. Their document grammars,
reader behavior, public APIs, callback lifetimes, and blank-node scoping remain
owned by their syntax packages and are unchanged.

The post-extraction benchmark used the frozen protocol below and measured a
2.84 M triples/s median of process-best rounds (197.69 MiB/s). This is within
measurement noise of the 2.82 M triples/s baseline. Stage 2, direct N-Quads
parsing over the shared lexer, measured 1.42 M quads/s (135.66 MiB/s) with the
same protocol. The immediately preceding synthetic implementation measured
0.53 M quads/s on the same checkout and machine.

## Before-refactor synthetic baseline

Measured on 2026-07-17 with Odin `dev-2026-07:819fdc7a8`, Darwin x86_64,
`-o:speed`, 250,000 records, three timed rounds, and three independent processes.
The table reports the median of each process's best round.

| Syntax | Records/s | Input throughput | Input size |
| --- | ---: | ---: | ---: |
| N-Triples | 2.82 M | 196.42 MiB/s | 17.40 MiB |
| N-Quads | 0.49 M | 47.14 MiB/s | 23.84 MiB |

The workload repeats one language-literal statement, with a named IRI graph in
N-Quads. It intentionally isolates the parser hot path and synthetic-statement
overhead; it is not representative of mixed IRIs, blank nodes, escaped literals,
or reader I/O. Add a separate mixed-term workload before making broader parser
performance claims.

These numbers compare implementations on one machine and are not cross-machine
performance claims. Reproduce the protocol with `./scripts/run-benchmarks.sh`,
which records the source revision, and retain the full output when reporting a
change.
