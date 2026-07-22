# Compatibility and API stability

`odin-rdf` is currently a pre-1.0 RDF 1.1 library. RDF 1.1 is the stable
semantic baseline; RDF 1.2 and SPARQL are not part of this repository's current
scope.

## Release expectations

Applications should pin a released version and keep integration tests for their
own documents and loader policies. The project follows these expectations:

- Patch releases do not intentionally make source-incompatible changes to public
  APIs.
- Minor releases normally add APIs or conformance fixes. If an API change cannot
  be avoided before 1.0, the changelog will include migration notes.
- Public ownership rules, resource limits, stable error codes, and documented
  no-network boundaries are compatibility commitments. Changes to them require
  explicit release notes.
- `main` is the integration branch, not a substitute for a pinned release.

## Support surface

The supported surface is the public API documented in the
[API reference](api-reference.md), the `odin-rdf` CLI, and the behavior gated
by the pinned W3C suites. Internal package layout and private helpers may change
without notice.

The project tests against the Odin development snapshot named in the README.
Other compiler revisions may work, but are not part of the release matrix until
they are added to CI.

## Upgrade practice

Before upgrading, read the dated changelog entry, run the documented verification
commands against application inputs, and review JSON-LD loader/resource limits.
For parser-facing upgrades, retain tests for accepted input, rejected input, and
expected output serialization.
