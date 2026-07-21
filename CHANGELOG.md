# Changelog

This project follows [Semantic Versioning](https://semver.org/).

## Unreleased

- Preserve term-coerced `@json` values as deterministically ordered RDF JSON
  literals, including arrays, `null`, and empty object member names;
  source-aware Compaction restores a uniquely associated source numeric shape.
  Expand the W3C JSON-LD to-RDF gate from 162 to 185 vectors.
- Remove free-floating top-level values and lists during Expansion, and apply
  document-relative IRI processing to node identifiers and `@type: @id`
  values. A null local context restores the document base while null `@base`
  clears it. The configured base option is also covered. Expand the W3C
  JSON-LD Expansion gate from 106 to 299 vectors, including existing graph
  values in graph/index and graph/id containers, native values under IRI
  coercion, multiple aliases for `@type`, and explicit `@prefix: false`
  Compact IRI handling. Custom `@index` properties now retain pre-existing
  expanded values while adding the map key, including graph/index containers.
  Keyword-shaped `@reverse` mappings are ignored rather than creating reverse
  properties, and repeated aliases for `@included`/`@graph` merge their
  expanded values. Property-scoped contexts propagate through nested values by
  default, while explicit `@propagate: false` keeps its rollback behavior;
  scoped contexts on `@nest` aliases apply at every nested level. The to-RDF
  gate grows from 185 to 355 vectors alongside these Expansion cases. The
  `@id` map base-option vector is now included in both gates. W3C fixture
  loaders now cover the relative remote-context resolution vector as well.
  Empty and relative `@base` overrides are covered with the configured base
  option. Invalid datatype IRIs in value objects are rejected during
  Expansion. W3C runners now expose JSON-LD 1.0 mode, and both document paths
  reject 1.1-only `@import`, `@propagate`, and custom `@index` definitions
  there, as well as `@type: "@none"`. JSON-LD 1.0 now rejects empty and
  relative `@vocab` mappings; the pinned gates also cover version conflicts
  and 1.1-only `@id`/array container mappings. JSON-LD 1.0 also rejects the
  JSON-LD 1.1-only `@type` keyword redefinition used to select `@set`.
  The to-RDF gate also fixes RDF graph comparison for blank-node label
  allocation and locks the supported protected-term and scoped-context cases.
  Property-scoped null contexts now clear inherited protection before applying
  a nested local context, matching JSON-LD 1.1 protected-term semantics.
  Keyword-shaped invalid `@reverse` mappings without a vocabulary are ignored
  during to-RDF conversion instead of producing an invalid RDF predicate.
  Graph containers now apply property-scoped contexts before parsing graph
  members, including scoped null-context protection clearing.
  Custom index properties now also emit RDF data for graph/index containers.
  Type-scoped contexts now govern node identifiers as well as nested values.
  Invalid and recursively sourced `@import` contexts are pinned as negative
  cases in both Expansion and to-RDF.
  Language maps now recognize a term alias of `@none` during to-RDF conversion.
  The W3C to-RDF runner now covers the `base` and `expandContext` option
  fixtures without broadening the library's public parse surface. Empty and
  relative `@base` option vectors are now pinned directly. Invalid expanded
  predicates, including a raw second fragment delimiter after vocabulary
  expansion, are dropped instead of being serialized as RDF IRIs. Invalid or
  relative `@id`-coerced values are likewise removed from RDF lists.
  Identifiers supplied through direct `@nest` members now select the enclosing
  RDF node, preserving JSON:API-style included-resource identity.
  Native negative zero now uses JSON-LD's integer zero RDF representation.
  JSON-LD 1.1 `@type: "@none"` now suppresses only string type coercion while
  retaining native values, explicit value-object types, and IRI objects.
  To-RDF now drops statements containing invalid subject, predicate, object,
  datatype, language-tag, or graph-name terms before serializing RDF.
  The Flattening W3C gate now includes the already-supported list, graph, and
  embedded-node vectors, increasing from 35 to 56 cases. Flattening now also
  folds nested `@included` nodes into the active node map and issues stable
  blank-node identifiers independently of source labels. Explicit empty IDs
  remain present when a local context clears the document base. Direct `@id`
  members inside `@nest` now identify the enclosing expanded node.
  The Expansion gate includes the matching JSON:API nested-identity and JSON
  value vectors, increasing from 299 to 308 cases. Type identifiers now expand
  against the context preceding their type-scoped contexts, and property-scoped
  contexts now govern scalar coercion as well as object values.
  The W3C Expansion runner also covers its `expandContext` fixture without
  broadening the public Expansion options.
  Type-map-selected scoped contexts now remain active while expanding nested
  index-map values, covering the W3C `c013` composition vector.
  Expansion expectations now use parsed JSON-value comparison, as required by
  the W3C object-comparison harness, so equivalent JSON number representations
  cover `js12` without conflating source spelling with JSON value semantics.
- Add the already-supported W3C Framing `0021` and `ra03` vectors, covering
  JSON-LD 1.0 blank-node types and `@requireAll` matching of both type and
  properties; the Framing gate now has 89 cases.
- Prune unselected ID-only anonymous references from compact framed values,
  covering W3C Framing `p046` and raising that gate to 90 cases.
- Propagate JSON-LD 1.0 processing mode through Framing and preserve legacy
  CURIE-conflict properties during framed compaction, covering W3C Framing
  `0010` and raising that gate to 91 cases.
- Add the already-passing JSON-LD 1.0 deep-embedding replacement vector
  W3C Framing `0015`, raising that gate to 92 cases.
- Add Flatten output-context compaction with a selectable compact-arrays
  policy, covering W3C Flatten `0044` and raising that gate to 57 cases.
- Add opt-in JSON-LD `produce_generalized_rdf` support for blank-node
  predicates. Strict RDF validation and writers remain the default; the new
  N-Quads generalized-writer option is explicit. Cover W3C to-RDF `0118` and
  `e075`, raising that gate to 357 cases.
- Reject value and list objects under `@included` and `@nest`, and reject
  reverse term definitions that declare `@nest`. Cover W3C to-RDF negative
  vectors `en04`, `en06`, `in08`, and `in09`, raising that gate to 361 cases.
- Enforce value-object keyword, type/language, and scalar-language invariants,
  and reject extra members on list objects. Cover W3C to-RDF negative vectors
  `er37`, `er38`, `er39`, and `er41`, raising that gate to 365 cases.
- Reject blank-node and relative IRI term-definition `@type` mappings. Cover
  W3C to-RDF negative vectors `er13` and `er23`, raising that gate to 367
  cases.
- Reject conflicting or non-IRI reverse term definitions, invalid reverse
  containers, keyword reverse-map entries, and reverse list values. Cover W3C
  to-RDF negative vectors `er14`, `er17`, `er25`, `er36`, and `er50`, raising
  that gate to 372 cases.
- Reject non-string `@index` values and non-string language-map entries, and
  pin JSON-LD 1.0's existing nested-list rejection. Cover W3C to-RDF negative
  vectors `er24`, `er31`, `er32`, and `er35`, raising that gate to 376 cases.
- Pin the existing JSON-LD 1.0 rejection of empty and relative `@vocab`
  mappings with W3C to-RDF negative vectors `e115` and `e116`, raising that
  gate to 378 cases.
- Reject invalid `@context` aliases, implicit relative mappings without a
  vocabulary, and JSON-LD 1.1 keyword aliases with coercion or prefix flags.
  Cover W3C to-RDF negative vectors `er19`, `er20`, `er43`, `er56`, and
  `pr33`, raising that gate to 383 cases.
- Reject JSON-LD's `@index` keyword as a property-valued index name. Cover
  W3C to-RDF negative vector `pi03`, raising that gate to 384 cases.
- Reject a second `@id` member introduced through a colliding identifier
  alias, while retaining multiple legal `@type` aliases. Cover W3C to-RDF
  negative vector `er26`, raising that gate to 385 cases.
- Require JSON-LD 1.1 relative and compact IRI-looking terms to retain their
  own expansion, and prohibit a relative term from becoming an `@prefix`.
  Cover W3C to-RDF negative vectors `er44`, `er48`, and `er49`, raising that
  gate to 388 cases. The runner now explicitly executes `e071` in its W3C
  JSON-LD 1.0 mode.
- Reject an empty context term while retaining the internal empty-object-key
  sentinel exclusively for opaque `@json` values. Cover W3C to-RDF negative
  vector `er52`, raising that gate to 389 cases.
- Statically validate an unused scoped context's implicit terms without
  constructing that context or altering protected-term ordering. Cover W3C
  to-RDF negative vector `c033`, raising that gate to 390 cases.
- Expand the JSON-LD to-RDF gate to every W3C evaluation vector: all 345
  positive and all 106 negative cases, for 451 cases total.
- Expand the JSON-LD Expansion gate from 19 to 91 verified negative W3C
  vectors, raising that gate from 308 to 380 cases.
- Validate Expansion value-object members, arrays, type/language combinations,
  language tags, and language-map values. Cover W3C negative vectors `er29`,
  `er35`, `er37`–`er39`, and `er51`, raising the gate to 386 cases.
- Reject non-node `@included` values during Expansion and the invalid
  `[@list, @set]` container combination. Cover W3C negative vectors `in07`–
  `in09` and `es02`, raising the gate to 390 cases.
- Validate reverse-property names and expanded values during Expansion. Cover
  W3C negative vectors `er25`, `er34`, and `er36`, raising the gate to 393
  cases.
- Enforce JSON-LD 1.0 list-of-lists restrictions and list-object member
  validation during Expansion. Cover W3C negative vectors `er24`, `er32`, and
  `er41`, raising the gate to 396 cases.
- Reject duplicate `@id` aliases and property-valued index injection into a
  value object during Expansion. Cover W3C negative vectors `er26` and
  `pi05`, raising the gate to 398 cases.
- Extend the RDF-to-JSON-LD gate from 46 to all 54 pinned vectors, including
  the supported direction-mode cases `di01`–`di10`. Directional output now
  compares parsed JSON values while allowing only the top-level node array to
  be unordered, matching RDF dataset semantics without weakening nested
  `@list` order checks.
- Reorganize the README around supported workflows, production boundaries,
  and task-oriented entry points; consolidate conformance indicators while
  retaining the full W3C gate breakdown on demand.
- Synchronize JSON-LD W3C gate counts, supported Framing and scoped-context
  capabilities, Compaction exact-output coverage, and the landing-page total
  with the pinned runners used by CI.

## 0.28.0 - 2026-07-21

- Restore the direct JSON shape of an anonymous JSON-LD 1.1 `@graph`
  container when its original source document is supplied to Compaction,
  including `@included` for multiple graph nodes. Add unit coverage and
  structural W3C `0077`/`0081`/`0109` assertions. The single anonymous
  `[@graph, @index]` form now restores its source index key, and the matching
  `[@graph, @id]` form restores `@none` (including its term alias). `@set`
  is preserved for the single anonymous `[@graph, @id, @set]` form; other
  graph-map combinations remain independently handled. The same unique
  source association restores both explicit and `@none` keys for
  `[@graph, @index, @set]`, and restores explicit source graph IDs as keys
  for `[@graph, @id]` with and without `@set`.
- Restore the source `@index` member on a named graph inside an anonymous
  `[@graph, @index]` container, retaining its `@id`/`@index`/`@graph` object
  form and adding a structural W3C `0083` assertion.
- Preserve the `@none` key for an anonymous `[@graph, @id]` container even
  when its source graph object has an unrelated ordinary `@index` annotation;
  add the structural W3C `0088` assertion.
- Preserve the array shape for a direct anonymous `[@graph, @set]` container
  restored from source metadata; add the structural W3C `0078` assertion.
- Restore a direct anonymous `@graph` container even when its source graph
  object carries an unrelated ordinary `@index`; add the structural W3C
  `0079` assertion.
- Restore a direct named `@graph` container from its unique source graph ID;
  add the structural W3C `0080` assertion.
- Preserve a source graph boundary as an explicit `@graph` wrapper when the
  compaction context defines an ordinary property rather than a graph
  container; add the structural W3C `0090` assertion.
- Extend source graph-boundary recovery to multiple values of one ordinary
  property, adding the structural W3C `0092` assertion.
- Cover the equivalent single-boundary W3C `0094` output shape.
- Map W3C `compactArrays: false` to `Compact_Array_Policy.Preserve` in the
  Compaction runner. Preserve the top-level `@graph` document shape for
  source-recovered graph boundaries, adding structural `0091`/`0093`
  assertions.
- Restore multiple graph values from one source `@graph` container, retaining
  `@set` at the property level rather than around each graph; add structural
  `0096`/`0097` assertions.
- Restore multiple anonymous `[@graph, @index]` values as one source-indexed
  map, with and without `@set`; add structural W3C `0098`/`0099` assertions.
- Restore multiple explicit source graph IDs as `[@graph, @id]` map keys,
  with and without `@set`; add structural W3C `0100`/`0101` assertions.
- Preserve repeated source keys as arrays in an anonymous `[@graph, @index]`
  map; add the structural W3C `0102` assertion.
- Recover repeated explicit graph-ID occurrences only when source fragment
  signatures exactly partition the merged RDF named graph; add the structural
  W3C `0103` assertion.
- Preserve the outer `@set` array around a source-recovered multi-node graph
  container; add the structural W3C `0110` assertion.
- Recover the uniquely identifiable anonymous source root of a custom-index
  map after RDF serialization; add structural assertions for W3C `0112`/`0113`.
- Recover a source-confirmed reverse custom-index map whose root is present
  only as an RDF object; add the structural W3C `0114` assertion.
- Preserve an `@json` array as one `@set` value rather than nesting it;
  extend the W3C JSON literal Compaction gate through `js01`–`js11` and
  add structural assertions for all eleven vectors. Restore a source-proven
  lone JSON `null` value when its RDF dataset is empty.
- Recover a source-signature-verified, single-layer `@included` boundary
  with aliased, keyword, and source-only-root forms; add structural W3C
  `in01`–`in03` assertions.
- Extend source-signature recovery to nested `@included` boundaries; add
  the structural W3C `in04` assertion.
- Recover a source-confirmed ordinary parent edge that RDF later presents as
  a reverse relation, completing the structural W3C `in05` assertion.
- Add exact structural W3C coverage for list-container vectors
  `li01`–`li05`.
- Add parsed JSON structural assertions to the W3C Compaction runner for
  shape-sensitive vectors. Cover relative property IRIs and JavaScript object
  property names, extending the semantic Compaction gate to 151 vectors.
- Honor `@set` on direct and aliased `@type` definitions during compaction,
  and omit RDF-generated blank-node IDs from an anonymous singleton result.
  Add direct output-shape regression coverage for both forms.
- Cover an aliased JSON-LD 1.1 `@type` with an `@set` container in the
  semantic Compaction gate, raising it to 149 vectors.
- Cover JSON-LD 1.1 `@type` with an `@set` container in the semantic
  Compaction gate, raising it to 148 vectors.
- Cover shared ID keys for multiple graphs in a JSON-LD 1.1 `[@graph, @id]`
  container in the semantic Compaction gate, raising it to 147 vectors.
- Cover shared index keys for multiple graphs in a JSON-LD 1.1
  `[@graph, @index]` container in the semantic Compaction gate, raising it to
  146 vectors.
- Cover multiple graphs in a JSON-LD 1.1 `[@graph, @id, @set]` container in
  the semantic Compaction gate, raising it to 145 vectors.
- Cover multiple graphs in a JSON-LD 1.1 `[@graph, @id]` container in the
  semantic Compaction gate, raising it to 144 vectors.
- Cover multiple indexed graphs in a JSON-LD 1.1 `[@graph, @index, @set]`
  container in the semantic Compaction gate, raising it to 143 vectors.
- Cover multiple indexed graphs in a JSON-LD 1.1 `[@graph, @index]` container
  in the semantic Compaction gate, raising it to 142 vectors.
- Cover multiple graphs in a JSON-LD 1.1 `[@graph, @set]` container in the
  semantic Compaction gate, raising it to 141 vectors.
- Cover multiple graphs in a JSON-LD 1.1 `@graph` container in the semantic
  Compaction gate, raising it to 140 vectors.
- Cover a graph `@index` annotation with a JSON-LD 1.1 `[@graph, @id]`
  container in the semantic Compaction gate, raising it to 139 vectors.
- Cover the named JSON-LD 1.1 `[@graph, @id, @set]` container form in the
  semantic Compaction gate, raising it to 138 vectors.
- Cover the anonymous JSON-LD 1.1 `[@graph, @id, @set]` container form in the
  semantic Compaction gate, raising it to 137 vectors.
- Cover the named JSON-LD 1.1 `[@graph, @id]` container form in the semantic
  Compaction gate, raising it to 136 vectors.
- Cover the anonymous JSON-LD 1.1 `[@graph, @id]` container form in the
  semantic Compaction gate, raising it to 135 vectors.
- Cover the anonymous JSON-LD 1.1 `[@graph, @index, @set]` container form in
  the semantic Compaction gate, raising it to 134 vectors.
- Cover the anonymous JSON-LD 1.1 `[@graph, @index]` container form in the
  semantic Compaction gate, raising it to 133 vectors.
- Cover an ordinary `@index` annotation on a JSON-LD 1.1 `@graph` container
  in the semantic Compaction gate, raising it to 132 vectors.
- Cover the JSON-LD 1.1 `[@graph, @set]` container in the semantic Compaction
  gate, raising it to 131 vectors.
- Cover the basic JSON-LD 1.1 `@graph` container in the semantic Compaction
  gate, raising it to 130 vectors.
- Normalize compact-IRI term dependencies after a local context is fully
  constructed, so sibling prefix declarations are independent of JSON object
  iteration order. Preserve ordinary `@index` keys when their source document
  is explicitly supplied to compaction. Extend the semantic Compaction gate to
  129 vectors.
- Keep type-scoped contexts from leaking into inline referenced nodes.
  Extend the semantic Compaction gate to 128 vectors.
- Reconstruct safe RDF reverse links as compact `@reverse` entries and extend
  dataset comparison with `--base IRI` for relative JSON-LD identifiers.
  Extend the semantic Compaction gate to 127 vectors.
- Avoid compact IRI spellings that collide with a same-named coercing term
  when that term cannot represent the property's values. Extend the semantic
  Compaction gate to 126 vectors.
- Resolve custom `@index` references after all local context terms are defined,
  including forward references to compact IRIs. Extend the semantic Compaction
  gate to 125 vectors.
- Compact graph-container references inline, retaining named graph IDs while
  using direct contents for anonymous graphs and `@none` for graph/id maps.
  Extend the semantic Compaction gate to 124 vectors.
- Apply the coercion of a property-valued `@index` term in both JSON-LD-to-RDF
  conversion and Compaction, moving one index value into its map key while
  retaining any additional values on the node, or using `@none` when no value
  can compact to a string. Extend the semantic Compaction gate to 122 vectors.
- Inline referenced nodes when a property or type-scoped context supplies
  semantics needed to compact their contents, while preserving ordinary
  references and graph containers. Extend the semantic Compaction gate to 118
  vectors.
- Permit a property-scoped context to locally refine a protected outer term,
  while retaining protected-term enforcement for ordinary and type-scoped
  contexts. Extend the semantic Compaction gate to 116 vectors.
- Copy every term-definition string into the JSON-LD processor state, so
  keyword aliases in temporary term-scoped contexts remain valid after their
  source JSON is released. Extend the semantic Compaction gate to 115 vectors.
- Keep the context from before type-scoped processing available for `@type`
  output, including scoped-context arrays that reset mappings with `null`.
  Extend the semantic Compaction gate to 114 vectors.
- Resolve Compaction type-scoped contexts from serialized expanded type IRIs,
  apply multiple scopes in JSON-LD order, and retain graph containers while
  compacting scoped `@id` values. Avoid vocabulary candidates that conflict
  with existing keyword aliases. Extend the semantic Compaction gate to 113
  vectors.
- Add a reusable RFC 3986 IRI relativizer and use it for JSON-LD Compaction
  under `@base`, including parent paths, query/fragment-only references, and
  keyword-like path segments such as `./@special`. Extend the semantic
  Compaction gate to 109 vectors.
- Do not use context terms ending in RFC 3986 general delimiters as
  compact-IRI prefixes. Extend the semantic Compaction gate to 105 vectors.
- Preserve nested RDF lists through both to-RDF and Compaction, writing list
  members as JSON arrays rather than redundant nested `@list` wrappers.
  Extend the W3C to-RDF and semantic Compaction gates to 162 and 104 vectors.
- Preserve term-definition `@nest` mappings during Compaction, and route
  object and array `@nest` values through the normal to-RDF property path.
  Extend the W3C to-RDF and semantic Compaction gates to 157 and 99 vectors.
- Apply property scoped contexts while processing their values, and reuse the
  type-scoped context selection used by Framing during Compaction. Preserve
  `@propagate: false` boundaries for nested node values. Extend the W3C
  to-RDF and semantic Compaction gates to 154 and 95 vectors.
- Compact aliases of `@none` in language maps and aliases of `@json` in value
  objects; preserve value-object form for `@type: @none` terms and native
  `xsd:double` values whose shortest JSON spelling looks like an integer.
  Extend the semantic Compaction gate to 86 vectors.
- Preserve referenced graph-node identifiers and treat `@none` (including its
  aliases) as an anonymous graph key in `@graph`/`@id` containers. Extend the
  semantic Compaction gate to 81 vectors covering the corresponding W3C graph
  map cases.
- Implement ordinary JSON-LD `@id` map expansion for to-RDF, respecting
  explicit node identifiers; raise the to-RDF gate to 147 and the semantic
  Compaction gate to 78 vectors.
- Reject invalid `rdf:JSON` lexical forms during RDF-to-JSON-LD conversion,
  preserving atomic output; extend the FromRDF gate to 46 vectors covering
  JSON literals and nested RDF lists.
- Align Expansion's id/type, graph, index, and language container processing
  with to-RDF for scoped type keys and `@none` aliases; extend the pinned
  Expansion gate to 106 vectors.
- Add JSON-LD `@type` container handling to RDF conversion, including named
  and blank-node type keys, `@none`, nested type-scoped contexts, and scalar
  `@id`/`@vocab` mappings; raise the to-RDF gate to 145 vectors.
- Expand the pinned JSON-LD to-RDF gate to 134 vectors with graph index maps,
  non-string `@id`/`@vocab` coercion, nested base resolution, relative
  vocabularies, and context terms such as `valueOf` and `toString`.
- Extend the pinned JSON-LD to-RDF gate from 114 to 127 vectors, covering
  keyword-form term and IRI handling, invalid datatype IRIs, compact and term
  `@vocab` mappings, scoped-context recursion, and base IRIs without a
  trailing slash.
- Ignore JSON-LD strings matching the reserved keyword form (`@` followed by
  letters) while preserving usable terms such as `@` and `@foo.bar`; reject
  invalid raw datatype IRIs before emitting RDF.
- Expand nested JSON-LD `@set` values in the to-RDF processor, preserving
  list/type container semantics and dropping null values. Extend the pinned
  to-RDF core gate to 114 vectors.
- Recognize aliases of `@value` and `@type` while converting JSON-LD value
  objects to RDF.
- Drop unmapped JSON object properties where JSON-LD expansion has no usable
  property IRI instead of reporting an RDF conversion error.
- Drop language-only objects that lack `@value` during to-RDF conversion.
- Correct nested reverse-term handling inside top-level `@reverse` maps.
- Reset active term, vocabulary, language, and direction mappings for nested
  `@context: null` values during to-RDF conversion, while preserving the
  document base IRI.
- Ignore null members and null value objects inside language and index
  containers during to-RDF conversion.
- Preserve blank-node identifiers used as `@type` values during to-RDF
  conversion instead of serializing them as invalid IRIs.
- Apply term-level datatype coercion to JSON boolean values during to-RDF
  conversion.
- Resolve compact IRIs against object-form absolute term definitions while
  processing one local context.
- Drop unmapped relative keys inside `@reverse` maps during to-RDF conversion.
- Resolve redefined terms against their current context prefix and `@vocab`
  settings instead of a previous definition of the same term.
- Ignore free-floating scalar, value-object, and list entries in `@graph`
  during to-RDF conversion while retaining graph members with properties.
- Resolve `@id`-coerced values as document-relative IRIs rather than through
  unrelated term mappings; compact IRI prefixes remain supported.
- Emit every value supplied through multiple aliases of `@type`.
- Convert basic `@graph` and `[@graph, @set]` containers into linked named
  RDF graphs during to-RDF conversion.
- Support `[@graph, @index]` and `[@graph, @index, @set]` containers while
  discarding ordinary index annotations.
- Support `[@graph, @id]` and `[@graph, @id, @set]` containers, including
  explicit `@graph` wrappers and multi-graph maps.
- Ignore nodes whose `@id` remains relative after a local `@base: null`
  reset, preventing invalid RDF output.
- Resolve `@id`-coerced fragment references containing a colon against the
  active base IRI unless they use a declared prefix or IRI scheme.

## 0.27.0 - 2026-07-20

- Add opt-in JSON-LD 1.1 `i18n-datatype` and `compound-literal`
  directional-literal mappings to to-RDF, RDF-to-JSON-LD, and context
  compaction. Default RDF conversion still omits `@direction`.
- Extend the pinned JSON-LD core gates to 67 to-RDF, 32 RDF-to-JSON-LD, and
  73 compaction vectors, including directional datatype and compound-literal
  coverage.

## 0.26.0 - 2026-07-20

- Retain owned keys while processing sourced JSON-LD contexts, so term
  definitions remain valid after the loaded JSON document is released.
- Resolve relative sourced term identifiers against an importing context's
  `@vocab`, as required when a source context is merged.
- Extend the JSON-LD Expansion gate with the W3C `so07`, `so10`, and `so11`
  source-context vectors. The gate now covers 78 vectors, including expected
  failures for protected-term redefinitions.
- Support JSON-LD 1.1 non-propagating scoped contexts in document Expansion,
  Flattening, and Framing. `@propagate: false` now restores the previous
  context at nested node objects, while type-scoped contexts are
  non-propagating unless they explicitly opt in.
- Extend the Expansion gate to 84 vectors with W3C property-, type-, embedded-,
  and sourced-context propagation coverage, plus invalid `@propagate` values.
- Add JSON-LD 1.1 base and term `@direction` handling to document Expansion
  and Flattening, including language maps, lists, explicit value directions,
  and validation of invalid direction/type combinations.
- Extend the Expansion gate to 93 vectors with W3C directional-context
  coverage. RDF directional-literal encodings remain out of scope.
- Extend the bounded Framing gate with W3C `0062` (`@set` container output)
  and `0070` (protected empty context), for 81 passing vectors.
- Add bounded Framing `@included` support and extend the W3C Framing gate with
  `in01`–`in03`, for 84 passing vectors.
- Add bounded named-graph Framing: `@graph` subframes use graph-local node
  maps, preventing same-ID default- and named-graph nodes from leaking into
  one another; graph-container terms compact selected graph members directly.
- Extend the Framing gate with W3C `0047`, `0050`, and `g010`, for 87 passing
  vectors covering graph-local selection, nested graph subframes, and graph
  containers.

## 0.25.0 - 2026-07-20

- Add bounded JSON-LD `@import` source contexts through the existing opt-in
  document loader. Imported definitions apply before definitions in the
  containing context, and recursive or array-valued source contexts are
  rejected explicitly.
- Enforce JSON-LD `@protected` term definitions, including sourced contexts:
  same-context overrides remain valid, while later incompatible redefinitions
  return `Protected_Term_Redefinition`.
- Resolve each object context once during Expansion, avoiding duplicate remote
  loads while keeping term-scoped and object-local contexts in one path.
- Extend the pinned JSON-LD Expansion gate with two sourced-context override
  vectors, for 75 cases total.

## 0.24.0 - 2026-07-20

- Add bounded, deterministic JSON-LD Expansion and Flattening APIs. Expansion
  preserves document-level JSON-LD annotations before RDF conversion; Flattening
  builds a bounded deterministic node-map.
- Add a bounded JSON-LD Framing profile with recursive embedding, standard
  embed modes, `@explicit`, defaults, `@requireAll`, value/list patterns, and
  basic reverse framing. Named-graph matching, `@included`, and the remaining
  Framing policy matrix remain explicitly out of scope.
- Add pinned W3C core gates for 73 Expansion, 35 Flattening, and 79 Framing
  vectors. No implicit network access is added; document loading remains
  caller-controlled.

## 0.23.0 - 2026-07-18

- Add bounded, deterministic RDF dataset to expanded JSON-LD serialization with
  named-graph preservation, safe RDF list collapse, `rdf:JSON`, and optional
  native JSON scalars.
- Add atomic explicit-context JSON-LD compaction with language maps, list and
  `@set` containers, typed values, named graphs, and a `convert --to jsonld
  --context PATH` CLI path. JSON-LD output requires an explicit positive
  `max_records` dataset bound.
- Add pinned W3C RDF-to-JSON-LD (28 cases) and compaction (66 cases) core
  gates. The document-level Expansion, Flattening, and Framing APIs remain
  deliberately out of scope for this release.

## 0.22.0 - 2026-07-18

- Add bounded `odin-rdf diff BEFORE AFTER` for deterministic canonical dataset
  change review across every supported input syntax. It canonicalizes both
  complete datasets under the existing RDFC-1.0 and reader limits, then emits
  sorted canonical N-Quads lines prefixed with `- ` (removed) or `+ ` (added).
- `diff` accepts an atomic `--output` target and returns `0` for no changes,
  `1` for changes, or `2` for an input, canonicalization, or output error.
  It intentionally does not claim to be a minimum blank-node edit script.
- Add CLI coverage for two-input syntax inference, bounded failure, deterministic
  output, empty equal output, and stable diagnostic text. No public library API
  changes.

## 0.21.0 - 2026-07-18

- Add bounded `odin-rdf canon`, `hash`, and `compare` commands for every
  supported RDF input syntax. They use the existing RDFC-1.0 APIs only after a
  complete owned dataset is collected under an explicit quad admission policy.
- `canon` writes atomic canonical N-Quads, `hash` writes a SHA-256 or SHA-384
  hexadecimal digest, and `compare` reports isomorphism with conventional
  `0` (equal), `1` (different), and `2` (error) exit codes.
- Add CLI coverage for syntax inference, hash selection, blank-node equality,
  collector limits, and atomic file replacement. No existing public APIs
  change.

## 0.20.0 - 2026-07-18

- Add `canon.canonical_hash` for atomic SHA-256 or SHA-384 digests of a
  complete dataset's RDFC-1.0 canonical N-Quads form.
- Add `canon.isomorphic` for collision-independent dataset comparison through
  canonical text, permitting unrelated source blank-node labels and scopes.
- Document the integrity-helper boundary: these APIs support cache, integrity,
  and higher-level signing inputs but do not implement signatures, storage, or
  SPARQL. No existing public APIs change.

## 0.19.0 - 2026-07-18

- Add `rdf/canon`, a resource-bounded implementation of W3C RDF Dataset
  Canonicalization 1.0 (RDFC-1.0) with canonical N-Quads output and SHA-256 or
  SHA-384 algorithm selection.
- Add the pinned 65-case official RDFC-1.0 conformance and resource-limit
  suite to local verification and CI. No existing public APIs change.

## 0.18.0 - 2026-07-18

- Add an explicit-prefix stateful RDF/XML document writer with per-record
  atomicity, copied and capacity-bounded blank-node identity, and a runnable
  streaming example. Extend RDF/XML QName validation to the XML 1.0 Fifth
  Edition NCName grammar.

## 0.17.0 - 2026-07-18

- Add RDF/XML as an explicit bounded batch `convert` target. It requires a
  positive `max_records` admission limit, retains owned default-graph terms,
  rejects named graphs before output, and writes the XML document only after
  parsing and serialization both succeed.

## 0.16.0 - 2026-07-18

- Add `rdfxml.write_triples`, an atomic deterministic RDF/XML writer for
  complete default graphs. It uses XML-safe blank-node identifiers, preserves
  source triple order, supports language, datatype, and XML Literal values,
  and explicitly rejects RDF/XML-unrepresentable predicates and XML 1.0
  characters.

## 0.15.0 - 2026-07-18

- Add markup-bearing RDF/XML `rdf:parseType="Literal"` support with
  token-preserved XML Literal serialization, including mixed content, comments,
  namespace propagation, explicit end tags, and canonical attribute ordering.
- Expand the pinned RDF/XML core conformance gate from 169 to 173 cases by
  enabling the four XML Literal namespace and canonicalization fixtures.

## 0.14.0 - 2026-07-18

- Add `trig.format_quads`, an atomic batch formatter for complete RDF datasets.
  It groups default and named graphs, deterministically orders and deduplicates
  quads, infers safe prefixes including graph names, and rejects ambiguous
  blank-node labels across source scopes.
- Extend `odin-rdf format` to infer Turtle or TriG file input, require an
  explicit syntax for standard input, and use separate `--max-triples` and
  `--max-quads` retention limits.

## 0.13.0 - 2026-07-18

- Add a streaming-safe TriG writer with explicit Turtle-compatible prefix
  declarations, atomic quad serialization, canonical IRIREF fallback, and one
  independent named-graph block per input quad.
- Allow TriG conversion targets and `.trig` output inference without retaining
  or regrouping a dataset. Named graphs now preserve losslessly to TriG as well
  as N-Quads.

## 0.12.0 - 2026-07-18

- Add bounded RDF 1.1 TriG-to-RDF input with default and named graph support,
  `.trig` conversion inference, explicit token/prefix/nesting/quad limits, and
  loss-aware conversion to N-Quads.
- Add a pinned 355-case W3C TriG gate that verifies memory and bounded-reader
  paths with blank-node-aware dataset isomorphism.
- Add a bounded, owned dataset collector that copies callback-scoped RDF terms,
  preserves source order and duplicates, and exposes explicit quad admission
  limits without becoming a graph-store API.

## 0.11.1 - 2026-07-18

- Correct public status text after the `0.11.0` RDF/XML release.

## 0.11.0 - 2026-07-18

- Add bounded RDF/XML-to-RDF conversion with namespace, base-IRI, language,
  node/property element, collection, reification, and default-graph support.
- Add `.rdf`, `.rdfxml`, and `.xml` input inference plus a pinned 169-case
  RDF/XML core gate. Markup-bearing XML Literals remain explicitly unsupported
  until canonical XML handling is added.

## 0.10.0 - 2026-07-18

- Add bounded JSON-LD-to-RDF dataset processing with local contexts, opt-in
  remote document loading, explicit document/context/quad limits, and
  N-Triples/N-Quads/Turtle conversion targets.
- Add `.jsonld` and `.json` conversion inference plus `--max-document-bytes`.

## 0.9.1 - 2026-07-18

- Add a reproducible batch Turtle formatter benchmark to the quality gate.
- Document formatter peak-memory behavior and how to set a deployment-specific
  `--max-triples` admission policy.

## 0.9.0 - 2026-07-18

- Let `odin-rdf convert` infer `.nt`, `.nq`, and `.ttl` file formats while
  retaining explicit `--from`/`--to` overrides and strict format requirements
  for standard streams and unrecognized extensions.

## 0.8.0 - 2026-07-18

- Add `convert.Reader_Limits` and `odin-rdf convert` limits for records,
  N-Triples/N-Quads physical lines, and Turtle top-level statements.
- Add a conversion example with an explicit resource policy.

## 0.7.1 - 2026-07-18

- Add `odin-rdf format --max-triples N` to bound the command's retained Turtle
  graph before formatting. The limit rejects input atomically and preserves an
  existing target file.
- Add a runnable batch Turtle formatter example.

## 0.7.0 - 2026-07-18

- Add `turtle.format_triples`, an atomic batch formatter that groups triples,
  uses Turtle predicate/object-list syntax, emits `a` for valid `rdf:type`,
  removes exact duplicates, and produces deterministic output.
- Add safe automatic prefix inference with familiar RDF, RDFS, XSD, OWL, SKOS,
  and Dublin Core labels plus deterministic generated labels.
- Add `odin-rdf format` for Turtle input with atomic file replacement,
  explicit-prefix control, and safe blank-node scope collision rejection.
- Preserve writer validation when using `a`, improve formatter lookup scaling,
  and add formatter round-trip and CLI failure-atomicity regression tests.

## 0.6.0 - 2026-07-18

- Add `rdf/convert`, a streaming adapter for N-Triples, N-Quads, and Turtle
  readers and writers. It rejects named-graph conversions that would lose RDF
  dataset information.
- Add the `odin-rdf convert` command with stdin/stdout, explicit Turtle prefix
  declarations, source-location diagnostics, and atomic file replacement.

## 0.5.0 - 2026-07-18

- Add a streaming-safe Turtle writer with explicit prefix declarations,
  deterministic longest-namespace compaction, typed-literal datatype
  compaction, and canonical IRIREF fallback.
- Add a Turtle-to-Turtle streaming conversion example and writer documentation.

## 0.4.1 - 2026-07-18

- Correct the Turtle W3C documentation after the 313-case gate landed.
- Run the Turtle example in the cross-platform CI matrix.
- Add a public API reference, benchmark comparison baseline, and release
  checklist.

## 0.4.0 - 2026-07-17

- Define the RDF 1.1 Turtle parser API, streaming architecture, transient
  parse-state model, resource limits, and 313-case W3C conformance gate.
- Add pinned Turtle manifest inventory, test-only RDF graph isomorphism, and a
  relative-capable internal IRIREF decoder while preserving absolute-IRI policy
  for N-Triples and N-Quads.
- Add an RDF 1.1 Turtle parser with directives, relative IRI resolution,
  prefixed names, literal shorthands, property lists, collections, bounded
  reader parsing, statement-atomic emission, and all 313 pinned W3C cases
  passing through memory and 1-byte, 7-byte, and default reader chunks.

## 0.3.1 - 2026-07-17

- Preserve the first invalid Unicode-escape digit when a physical line ending also truncates the escape, keeping memory and reader diagnostics identical.

## 0.3.0 - 2026-07-17

- Add deterministic property tests that compare N-Triples and N-Quads memory parsing, bounded-reader chunking, and canonical writer round trips across generated RDF data and random byte input.
- Document the shared term-lexer migration contract and add a configurable, reproducible benchmark runner with a frozen before-refactor baseline.
- Extract syntax-neutral RDF term lexing into `rdf/internal/termlex` and migrate N-Triples without changing its public API, diagnostics, or callback lifetimes.
- Parse N-Quads directly through the shared term lexer, removing synthetic N-Triples reparsing while preserving conformance and improving parser throughput.
- Add mixed-term N-Triples and N-Quads benchmarks alongside the focused synthetic workloads.
- Add reproducible differential parser fuzzing with pull-request smoke coverage and a daily AddressSanitizer campaign.
- Align N-Triples memory and bounded-reader errors for physical line endings inside literals and Unicode escapes.

## 0.2.0 - 2026-07-17

- Add the RDF dataset `Quad` model with explicit default-graph representation.
- Add an RDF 1.1 N-Quads parser, bounded `io.Reader` path, and atomic writer.
- Pass all 87 pinned W3C RDF 1.1 N-Quads syntax tests through memory and streaming paths with writer round trips.
- Share blank-node scopes and proven N-Triples term parsing across syntax packages.

## 0.1.0 - 2026-07-17

Initial public release.

- Add an RDF 1.1 N-Triples parser with strict grammar validation for UTF-8 input, IRI references, blank-node labels, language tags, and escapes.
- Add bounded-memory `io.Reader` parsing with line and triple limits.
- Add explicit simple, language-tagged, and typed literal constructors.
- Add syntax-independent RDF term and triple structure validation.
- Preserve document-local blank-node identity across in-memory and streaming parser calls.
- Add stable, allocation-free messages for every public error enum.
- Reject invalid negative reader limits instead of silently applying defaults.
- Add an atomic N-Triples writer with parser/writer round-trip coverage.
- Pass all 72 pinned W3C RDF 1.1 N-Triples syntax tests through the in-memory and streaming parser paths.
- Add Linux, macOS, and Windows CI, AddressSanitizer tests, examples, and a parser benchmark.
