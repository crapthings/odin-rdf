# Streaming conversion design

`rdf/convert` connects the existing RDF 1.1 readers and writers without adding
graph storage or an AST. Its unit of work is one callback-scoped RDF statement:

```text
io.Reader → syntax reader → Triple or Quad callback → syntax writer → io.Writer
```

The adapter owns one reusable `strings.Builder` for the current output record.
It writes each completed record before asking the source reader for the next
one, so memory is independent of document size apart from the selected reader's
existing bounds and the largest serialized record.

## Supported conversions

N-Triples and Turtle are RDF graph syntaxes. N-Quads is an RDF dataset syntax.
The conversion matrix is therefore intentionally asymmetric:

| Source | Target | Behavior |
| --- | --- | --- |
| N-Triples | N-Triples, Turtle | Stream triples directly. |
| N-Triples | N-Quads | Emit each triple in the default graph. |
| Turtle | N-Triples, Turtle | Stream triples directly. |
| Turtle | N-Quads | Emit each triple in the default graph. |
| N-Quads default graph | N-Triples, Turtle, N-Quads | Preserve the triple or default-graph quad. |
| N-Quads named graph | N-Quads | Preserve the quad. |
| N-Quads named graph | N-Triples, Turtle | Reject with `Named_Graph_Not_Supported`. |

The last row is a data-integrity boundary. The adapter never silently removes a
graph name to make a conversion appear successful.

## Error and output semantics

Source parse errors preserve their syntax-specific stable message and one-based
line and column. Serialization and writer failures preserve the corresponding
stable writer message. Reader and writer I/O errors are retained in `Error`.

Records written before a later source error remain in the destination stream.
This is inherent in streaming output and useful for pipes. Consumers that need
all-or-nothing file output should use the command or implement the same
temporary-file policy around `convert.convert`.

Turtle output requires caller-supplied prefixes. Prefixes are validated and
written before source bytes are consumed; the writer otherwise falls back to a
canonical IRIREF. No prefix inference or document grouping is hidden inside the
converter.

## Reader limits

`convert.Reader_Limits` keeps conversion resource policy explicit without
exposing three unrelated syntax-option structs at every call site. It maps
`max_records` to triples, quads, or Turtle triples as appropriate; maps
`max_line_bytes` only to the two line-oriented syntaxes; and maps
`max_statement_bytes` only to Turtle's top-level production framing.

The zero value keeps existing reader defaults and disables the record cap.
Negative fields are rejected before the converter writes a Turtle prefix or
reads the input. A streaming destination may already contain complete earlier
records if a later source limit is reached; `odin-rdf convert --output PATH`
uses its temporary-file policy to avoid replacing the target in that case.

## Command file policy

`odin-rdf convert` treats `-` as standard input or output. For a file target it
opens `<target>.odin-rdf.tmp` exclusively in the destination directory, streams
the conversion into that file, closes it, then renames it over the target.
Failure closes and removes the temporary file while leaving the existing target
unchanged. A pre-existing temporary file is treated as a safety error rather
than overwritten.

The command rejects an input and output path with the same literal spelling.
It deliberately does not infer a format from a filename: `--from` and `--to`
are required so that scripts stay explicit as more RDF syntaxes are added.
