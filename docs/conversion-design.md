# Streaming conversion design

`rdf/convert` connects the existing RDF 1.1 readers and writers without adding
a persistent graph store or AST. Its normal unit of work is one callback-scoped
RDF statement:

```text
io.Reader → syntax reader → Triple or Quad callback → syntax writer → io.Writer
```

The adapter normally owns one reusable `strings.Builder` for the current output
record. It writes each completed record before asking the source reader for the
next one, so memory is independent of document size apart from the selected
reader's existing bounds and the largest serialized record. RDF/XML and JSON-LD
output are explicit exceptions: each retains one owned, capacity-bounded
dataset, then emits one document atomically after successful parsing.

## Supported conversions

N-Triples and Turtle are RDF graph syntaxes. N-Quads and TriG are RDF dataset syntaxes.
The conversion matrix is therefore intentionally asymmetric:

| Source | Target | Behavior |
| --- | --- | --- |
| N-Triples | N-Triples, Turtle | Stream triples directly. |
| N-Triples | N-Quads, TriG | Emit each triple in the default graph. |
| Turtle | N-Triples, Turtle | Stream triples directly. |
| Turtle | N-Quads, TriG | Emit each triple in the default graph. |
| Graph syntax default graph | RDF/XML | Collect up to a required `max_records` bound, then write one RDF/XML document. |
| Any graph or dataset syntax | JSON-LD | Collect up to a required `max_records` bound, then write deterministic expanded JSON-LD; CLI `--context PATH` selects atomic context-directed compaction. |
| Dataset default graph | N-Triples, Turtle, N-Quads, TriG | Preserve the triple or default-graph quad. |
| Dataset default graph | RDF/XML | Collect up to a required `max_records` bound, then write one RDF/XML document. |
| Dataset named graph | N-Quads, TriG, JSON-LD | Preserve the quad. |
| Dataset named graph | N-Triples, Turtle, RDF/XML | Reject with `Named_Graph_Not_Supported`. |
| JSON-LD, RDF/XML, TriG | N-Triples, Turtle, N-Quads, TriG, RDF/XML, JSON-LD | Parse bounded input; preserve named graphs for N-Quads, TriG, and JSON-LD; reject them for RDF/XML. |

The last row is a data-integrity boundary. The adapter never silently removes a
graph name to make a conversion appear successful.

## Error and output semantics

Source parse errors preserve their syntax-specific stable message and one-based
line and column. Serialization and writer failures preserve the corresponding
stable writer message. Reader and writer I/O errors are retained in `Error`.

Records written before a later source error remain in the streaming destination
formats. This is inherent in streaming output and useful for pipes. RDF/XML and
JSON-LD are all-or-nothing even on standard output: they leave the destination
untouched until the complete bounded dataset has parsed and serialized. Consumers that need
the same all-or-nothing behavior for streaming formats should use the command
or implement its temporary-file policy around `convert.convert`.

Turtle and TriG output require caller-supplied prefixes. Prefixes are validated and
written before source bytes are consumed; the writer otherwise falls back to a
canonical IRIREF. No prefix inference or document grouping is hidden inside the
converter. TriG emits one self-contained named graph block per named quad, which
keeps its memory bounded and preserves record order.

## Reader limits

`convert.Reader_Limits` keeps conversion resource policy explicit without
exposing three unrelated syntax-option structs at every call site. It maps
`max_records` to triples, quads, or Turtle triples as appropriate; maps
`max_line_bytes` only to the two line-oriented syntaxes; and maps
`max_statement_bytes` only to Turtle's top-level production framing.
`max_document_bytes` applies to the bounded JSON-LD, RDF/XML, and TriG readers.

The zero value keeps existing reader defaults and disables the record cap for
streaming destinations. RDF/XML and JSON-LD output require a positive
`max_records` value before the source reader is touched; the value bounds both
parser admission and the owned collector.
Negative fields are rejected before the converter writes a Turtle prefix or
reads the input. A streaming destination may already contain complete earlier
records if a later source limit is reached; RDF/XML and JSON-LD output stay empty. In all
cases, `odin-rdf convert --output PATH` uses its temporary-file policy to avoid
replacing the target on failure.

## Command file policy

`odin-rdf convert` treats `-` as standard input or output. For a file target it
opens `<target>.odin-rdf.tmp` exclusively in the destination directory, streams
the conversion into that file, closes it, then renames it over the target.
Failure closes and removes the temporary file while leaving the existing target
unchanged. A pre-existing temporary file is treated as a safety error rather
than overwritten.

The command rejects an input and output path with the same literal spelling.
For non-stdio paths it infers syntax from the canonical `.nt`, `.nq`, `.ttl`,
`.jsonld`, `.json`, `.rdfxml`, `.rdf`, `.xml`, and `.trig` extensions. Explicit `--from` and `--to` values override the inferred
formats. The command never inspects bytes to guess a syntax: `-` and an
unrecognized extension require the corresponding explicit option. This keeps
pipe behavior and future syntax additions unambiguous while removing redundant
flags from ordinary file-to-file conversions.
