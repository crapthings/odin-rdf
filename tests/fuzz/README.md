# Differential fuzzing

This harness generates reproducible random byte strings and mutations of valid
and invalid RDF seed statements. Every input is parsed through the in-memory
and bounded-reader N-Triples and N-Quads entry points. Error codes, error
locations, and emitted record counts must agree, and AddressSanitizer must stay
clean.

Run the default local campaign:

```sh
odin run tests/fuzz -o:speed -sanitize:address
```

Use a smaller reproducible campaign while investigating a failure:

```sh
odin run tests/fuzz -define:FUZZ_CASES=1000 -define:FUZZ_MAX_BYTES=256 -define:FUZZ_SEED=5720813349214897713
```

CI runs a smoke campaign on every change. The scheduled `fuzz` workflow runs
100,000 cases under AddressSanitizer each day with a new run-derived seed and
also accepts manual case-count and seed inputs. Preserve the reported seed and
add a focused unit regression when the harness finds a mismatch.
