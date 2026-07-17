# Property tests

This package provides deterministic cross-layer checks for all syntax packages.
It generates 512 valid RDF statements from varied IRIs, blank nodes, literals,
languages, datatypes, Unicode, and escaped values, then verifies that:

- in-memory parsing serializes back to the same canonical document;
- bounded readers with chunk sizes 1, 2, 7, 64, and the default produce the
  same records and canonical output;
- N-Triples and N-Quads writers accept every generated model value;
- Turtle memory and bounded-reader parsing agree across deterministic random bytes; and
- 512 deterministic random byte inputs produce identical error codes and source
  locations through memory and reader entry points at chunk sizes 1 and 7.

Run the harness with:

```sh
odin test tests/property
```

The fixed seeds make a failure reproducible. Add focused regression tests to the
affected syntax package when a generated case exposes a bug.
