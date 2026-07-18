# RDF dataset canonicalization design

`rdf/canon` implements [RDF Dataset Canonicalization 1.0](https://www.w3.org/TR/rdf-canon/) (RDFC-1.0) over a complete `[]rdf.Quad` dataset.

## Boundary

Canonicalization is intentionally distinct from syntax parsing, formatting, graph
storage, and SPARQL. It needs a complete RDF dataset because the RDFC-1.0
algorithm follows blank-node relationships transitively and may explore
permutations of indistinguishable related nodes. The package neither retains
caller data after `canonicalize` returns nor exposes a mutable graph API.

Input is interpreted as an RDF dataset set: exact duplicate quads are removed.
Blank-node identity uses both `Term.value` and `Term.scope`, so parser results
from independent sources cannot accidentally collapse merely because their
source labels match.

## Algorithm and output

The implementation follows RDFC-1.0's first-degree and N-degree hashing,
canonical issuer, and canonical N-Quads serialization. SHA-256 is the default;
SHA-384 is available through `Options.hash_algorithm` as required by the
standard. The output is canonical N-Quads, sorted in Unicode code point order,
with `_:c14n0`, `_:c14n1`, and so on.

The package owns a dedicated canonical serializer. Ordinary N-Quads writing is
not substituted because RDFC-1.0 specifies exact control-character escaping
for its canonical form.

## Resource policy

RDFC-1.0 is a partial operation for intentionally complex inputs. The default
policy rejects datasets exceeding 100,000 input quads, 100,000 blank nodes,
10,000,000 work steps, 1,000,000 permutations, or recursive depth 256. Each
limit can be raised explicitly. The bounds protect the recursive and
permutation-heavy portion of N-degree hashing; they are not a byte-precise
memory accounting mechanism.

Callers processing untrusted content should also apply the source parser's
document and record limits, then choose canonicalization limits appropriate to
their workload. A limit failure leaves the destination builder unchanged.

## Verification

`scripts/run-w3c-rdf-canon-tests.sh` downloads one pinned revision of the W3C
RDFC test suite and runs its 64 canonicalization vectors, including SHA-384,
plus its clique resource-limit negative case. Local unit tests cover atomic
output, duplicate removal, stable errors, and RDFC-specific escaping.
