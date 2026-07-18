# Release checklist

Use this checklist for every tagged release. Run commands from a clean checkout
and keep feature work in a pull request until all applicable gates pass.

## Prepare

- [ ] Confirm the release scope and semantic version.
- [ ] Update README status, examples, roadmap, landing page, and API reference.
- [ ] Add a dated changelog entry with compatibility notes.
- [ ] Confirm all repository URLs and examples use `crapthings/odin-rdf`.
- [ ] Run `git diff --check` and verify no generated or local files are staged.

## Verify

```sh
odin check rdf -no-entry-point -vet -warnings-as-errors
odin check rdf/internal/termlex -no-entry-point -vet -warnings-as-errors
odin check rdf/ntriples -no-entry-point -vet -warnings-as-errors
odin check rdf/nquads -no-entry-point -vet -warnings-as-errors
odin check rdf/turtle -no-entry-point -vet -warnings-as-errors
odin test rdf -sanitize:address
odin test rdf/internal/termlex -sanitize:address
odin test rdf/ntriples -sanitize:address
odin test rdf/nquads -sanitize:address
odin test rdf/turtle -sanitize:address
odin test tests/property -sanitize:address
odin test tests/w3c/support -sanitize:address
odin run tests/fuzz -o:speed -sanitize:address
odin run examples/minimal
odin run examples/basic
odin run examples/nquads
odin run examples/turtle
odin run examples/turtle_writer
./scripts/run-w3c-tests.sh
./scripts/run-w3c-nquads-tests.sh
./scripts/run-w3c-turtle-tests.sh
./scripts/run-benchmarks.sh
```

- [ ] Confirm Linux, macOS, and Windows CI succeeds on the pull request.
- [ ] Review benchmark medians against `benchmarks/baseline.md` on comparable
      hardware; investigate repeatable changes greater than 10%.
- [ ] Serve `docs/` locally and inspect desktop and mobile layouts, keyboard
      focus, links, horizontal overflow, and code-block contrast.

## Publish

- [ ] Merge the reviewed pull request into `main`.
- [ ] Confirm post-merge CI and Pages deployment succeed.
- [ ] Create an annotated `vX.Y.Z` tag at the exact `main` commit and push it.
- [ ] Create a non-draft, non-prerelease GitHub Release with concise highlights
      and compatibility notes.
- [ ] Verify the tag, local `HEAD`, `origin/main`, and Release target resolve to
      the same commit.
- [ ] Verify the public landing page and GitHub About metadata are current.

Do not move an existing release tag. If published artifacts are wrong, document
and supersede them with a new patch release.
