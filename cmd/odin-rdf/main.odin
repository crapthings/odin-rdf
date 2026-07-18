// odin-rdf is the repository's streaming RDF conversion command-line tool.
package main

import "core:fmt"
import "core:io"
import "core:os"
import "core:strconv"
import "core:strings"
import rdf "../../rdf"
import convert "../../rdf/convert"
import turtle "../../rdf/turtle"

Command_Error_Code :: enum {
	None,
	Missing_Command,
	Unknown_Command,
	Missing_Option_Value,
	Unknown_Option,
	Missing_Input,
	Extra_Input,
	Invalid_Format,
	Invalid_Prefix,
	Invalid_Max_Records,
	Invalid_Max_Line_Bytes,
	Invalid_Max_Statement_Bytes,
	Invalid_Max_Document_Bytes,
	Invalid_Max_Triples,
	Cannot_Infer_Input_Format,
	Cannot_Infer_Output_Format,
	Same_Input_Output,
}

command_error_message :: proc(code: Command_Error_Code) -> string {
	switch code {
	case .None:                 return "no error"
	case .Missing_Command:      return "expected a command"
	case .Unknown_Command:      return "unknown command"
	case .Missing_Option_Value: return "option requires a value"
	case .Unknown_Option:       return "unknown option"
	case .Missing_Input:        return "expected an input path or - for standard input"
	case .Extra_Input:          return "only one input path is supported"
	case .Invalid_Format:       return "unsupported RDF syntax"
	case .Invalid_Prefix:       return "--prefix must use LABEL=NAMESPACE"
	case .Invalid_Max_Records:  return "--max-records must be a positive decimal integer"
	case .Invalid_Max_Line_Bytes: return "--max-line-bytes must be a positive decimal integer"
	case .Invalid_Max_Statement_Bytes: return "--max-statement-bytes must be a positive decimal integer"
	case .Invalid_Max_Document_Bytes: return "--max-document-bytes must be a positive decimal integer"
	case .Invalid_Max_Triples:  return "--max-triples must be a positive decimal integer"
	case .Cannot_Infer_Input_Format: return "cannot infer input RDF syntax; use --from"
	case .Cannot_Infer_Output_Format: return "cannot infer output RDF syntax; use --to"
	case .Same_Input_Output:    return "input and output paths must differ"
	}
	return "unknown error"
}

Command_Error :: struct {
	code:  Command_Error_Code,
	value: string,
}

Command_Options :: struct {
	input_path: string,
	output_path: string,
	input_format: convert.Format,
	output_format: convert.Format,
	prefixes: [dynamic]turtle.Prefix,
	reader_limits: convert.Reader_Limits,
	help: bool,
}

Format_Command_Options :: struct {
	input_path: string,
	output_path: string,
	prefixes: [dynamic]turtle.Prefix,
	infer_prefixes: bool,
	max_triples: int,
	help: bool,
}

parse_format :: proc(value: string) -> (convert.Format, bool) {
	switch value {
	case "ntriples", "n-triples", "nt": return .N_Triples, true
	case "nquads", "n-quads", "nq":      return .N_Quads, true
	case "turtle", "ttl":                 return .Turtle, true
	case "jsonld", "json-ld", "json":      return .JSON_LD, true
	case "rdfxml", "rdf-xml", "rdf/xml", "rdf", "xml": return .RDF_XML, true
	}
	return {}, false
}

// infer_format_from_path recognizes only the canonical file extensions used by
// the command. It deliberately does not inspect input bytes: callers using
// stdin, stdout, or an unrecognized filename must choose a syntax explicitly.
infer_format_from_path :: proc(path: string) -> (convert.Format, bool) {
	if len(path) >= len(".nt") && path[len(path) - len(".nt"):] == ".nt" do return .N_Triples, true
	if len(path) >= len(".nq") && path[len(path) - len(".nq"):] == ".nq" do return .N_Quads, true
	if len(path) >= len(".ttl") && path[len(path) - len(".ttl"):] == ".ttl" do return .Turtle, true
	if len(path) >= len(".jsonld") && path[len(path) - len(".jsonld"):] == ".jsonld" do return .JSON_LD, true
	if len(path) >= len(".json") && path[len(path) - len(".json"):] == ".json" do return .JSON_LD, true
	if len(path) >= len(".rdfxml") && path[len(path) - len(".rdfxml"):] == ".rdfxml" do return .RDF_XML, true
	if len(path) >= len(".rdf") && path[len(path) - len(".rdf"):] == ".rdf" do return .RDF_XML, true
	if len(path) >= len(".xml") && path[len(path) - len(".xml"):] == ".xml" do return .RDF_XML, true
	return {}, false
}

append_prefix :: proc(prefixes: ^[dynamic]turtle.Prefix, value: string) -> bool {
	equals := strings.index_byte(value, '=')
	if equals < 0 do return false
	append(prefixes, turtle.Prefix{label = value[:equals], namespace = value[equals + 1:]})
	return true
}

parse_positive_decimal :: proc(value: string) -> (int, bool) {
	if len(value) == 0 do return 0, false
	for c in value do if c < '0' || c > '9' do return 0, false
	parsed, ok := strconv.parse_int(value, 10)
	return parsed, ok && parsed > 0
}

// parse_convert_args accepts conventional Unix-style options. Prefixes may be
// repeated, and input/output use - for stdin/stdout. It only parses arguments;
// Turtle prefix grammar is validated by the conversion package before I/O.
parse_convert_args :: proc(args: []string) -> (Command_Options, Command_Error) {
	options := Command_Options{output_path = "-"}
	if len(args) == 0 do return options, Command_Error{code = .Missing_Command}
	if args[0] == "--help" || args[0] == "-h" {
		options.help = true
		return options, {}
	}
	if args[0] != "convert" do return options, Command_Error{code = .Unknown_Command, value = args[0]}

	has_from, has_to, has_input := false, false, false
	positional_only := false
	for i := 1; i < len(args); i += 1 {
		arg := args[i]
		if !positional_only && (arg == "--help" || arg == "-h") {
			options.help = true
			return options, {}
		}
		if !positional_only && arg == "--" {
			positional_only = true
			continue
		}

		value: string
		needs_value := false
		if !positional_only && (arg == "--from" || arg == "--to" || arg == "--output" || arg == "-o" || arg == "--prefix" || arg == "--max-records" || arg == "--max-line-bytes" || arg == "--max-statement-bytes" || arg == "--max-document-bytes") {
			if i + 1 >= len(args) do return options, Command_Error{code = .Missing_Option_Value, value = arg}
			i += 1
			value = args[i]
			needs_value = true
		}

		if !positional_only && (arg == "--from" || strings.has_prefix(arg, "--from=")) {
			if !needs_value do value = arg[len("--from="):]
			format, ok := parse_format(value)
			if !ok do return options, Command_Error{code = .Invalid_Format, value = value}
			options.input_format = format
			has_from = true
			continue
		}
		if !positional_only && (arg == "--to" || strings.has_prefix(arg, "--to=")) {
			if !needs_value do value = arg[len("--to="):]
			format, ok := parse_format(value)
			if !ok do return options, Command_Error{code = .Invalid_Format, value = value}
			options.output_format = format
			has_to = true
			continue
		}
		if !positional_only && (arg == "--output" || arg == "-o" || strings.has_prefix(arg, "--output=")) {
			if !needs_value do value = arg[len("--output="):]
			if len(value) == 0 do return options, Command_Error{code = .Missing_Option_Value, value = "--output"}
			options.output_path = value
			continue
		}
		if !positional_only && (arg == "--prefix" || strings.has_prefix(arg, "--prefix=")) {
			if !needs_value do value = arg[len("--prefix="):]
			if !append_prefix(&options.prefixes, value) do return options, Command_Error{code = .Invalid_Prefix, value = value}
			continue
		}
		if !positional_only && (arg == "--max-records" || strings.has_prefix(arg, "--max-records=")) {
			if !needs_value do value = arg[len("--max-records="):]
			max_records, ok := parse_positive_decimal(value)
			if !ok do return options, Command_Error{code = .Invalid_Max_Records, value = value}
			options.reader_limits.max_records = max_records
			continue
		}
		if !positional_only && (arg == "--max-line-bytes" || strings.has_prefix(arg, "--max-line-bytes=")) {
			if !needs_value do value = arg[len("--max-line-bytes="):]
			max_line_bytes, ok := parse_positive_decimal(value)
			if !ok do return options, Command_Error{code = .Invalid_Max_Line_Bytes, value = value}
			options.reader_limits.max_line_bytes = max_line_bytes
			continue
		}
		if !positional_only && (arg == "--max-statement-bytes" || strings.has_prefix(arg, "--max-statement-bytes=")) {
			if !needs_value do value = arg[len("--max-statement-bytes="):]
			max_statement_bytes, ok := parse_positive_decimal(value)
			if !ok do return options, Command_Error{code = .Invalid_Max_Statement_Bytes, value = value}
			options.reader_limits.max_statement_bytes = max_statement_bytes
			continue
		}
		if !positional_only && (arg == "--max-document-bytes" || strings.has_prefix(arg, "--max-document-bytes=")) {
			if !needs_value do value = arg[len("--max-document-bytes="):]
			max_document_bytes, ok := parse_positive_decimal(value)
			if !ok do return options, Command_Error{code = .Invalid_Max_Document_Bytes, value = value}
			options.reader_limits.max_document_bytes = max_document_bytes
			continue
		}
		if !positional_only && len(arg) > 1 && arg[0] == '-' && arg != "-" do return options, Command_Error{code = .Unknown_Option, value = arg}
		if has_input do return options, Command_Error{code = .Extra_Input, value = arg}
		options.input_path = arg
		has_input = true
	}

	if !has_input do return options, Command_Error{code = .Missing_Input}
	if !has_from {
		format, ok := infer_format_from_path(options.input_path)
		if !ok do return options, Command_Error{code = .Cannot_Infer_Input_Format, value = options.input_path}
		options.input_format = format
	}
	if !has_to {
		format, ok := infer_format_from_path(options.output_path)
		if !ok do return options, Command_Error{code = .Cannot_Infer_Output_Format, value = options.output_path}
		options.output_format = format
	}
	if options.input_path != "-" && options.output_path != "-" && options.input_path == options.output_path {
		return options, Command_Error{code = .Same_Input_Output}
	}
	return options, {}
}

// parse_format_command_args parses the graph formatter's Turtle-only command.
// Formatting is necessarily batch-oriented, so its output is produced only
// after the entire input graph has parsed successfully.
parse_format_command_args :: proc(args: []string) -> (Format_Command_Options, Command_Error) {
	options := Format_Command_Options{output_path = "-", infer_prefixes = true}
	if len(args) == 0 do return options, Command_Error{code = .Missing_Command}
	if args[0] == "--help" || args[0] == "-h" {
		options.help = true
		return options, {}
	}
	if args[0] != "format" do return options, Command_Error{code = .Unknown_Command, value = args[0]}

	has_input := false
	positional_only := false
	for i := 1; i < len(args); i += 1 {
		arg := args[i]
		if !positional_only && (arg == "--help" || arg == "-h") {
			options.help = true
			return options, {}
		}
		if !positional_only && arg == "--" {
			positional_only = true
			continue
		}
		if !positional_only && arg == "--no-infer-prefixes" {
			options.infer_prefixes = false
			continue
		}

		value: string
		needs_value := false
		if !positional_only && (arg == "--output" || arg == "-o" || arg == "--prefix" || arg == "--max-triples") {
			if i + 1 >= len(args) do return options, Command_Error{code = .Missing_Option_Value, value = arg}
			i += 1
			value = args[i]
			needs_value = true
		}
		if !positional_only && (arg == "--output" || arg == "-o" || strings.has_prefix(arg, "--output=")) {
			if !needs_value do value = arg[len("--output="):]
			if len(value) == 0 do return options, Command_Error{code = .Missing_Option_Value, value = "--output"}
			options.output_path = value
			continue
		}
		if !positional_only && (arg == "--prefix" || strings.has_prefix(arg, "--prefix=")) {
			if !needs_value do value = arg[len("--prefix="):]
			if !append_prefix(&options.prefixes, value) do return options, Command_Error{code = .Invalid_Prefix, value = value}
			continue
		}
		if !positional_only && (arg == "--max-triples" || strings.has_prefix(arg, "--max-triples=")) {
			if !needs_value do value = arg[len("--max-triples="):]
			max_triples, ok := parse_positive_decimal(value)
			if !ok do return options, Command_Error{code = .Invalid_Max_Triples, value = value}
			options.max_triples = max_triples
			continue
		}
		if !positional_only && len(arg) > 1 && arg[0] == '-' && arg != "-" do return options, Command_Error{code = .Unknown_Option, value = arg}
		if has_input do return options, Command_Error{code = .Extra_Input, value = arg}
		options.input_path = arg
		has_input = true
	}
	if !has_input do return options, Command_Error{code = .Missing_Input}
	if options.input_path != "-" && options.output_path != "-" && options.input_path == options.output_path {
		return options, Command_Error{code = .Same_Input_Output}
	}
	return options, {}
}

print_help :: proc() {
	fmt.println(`Usage:
	  odin-rdf convert INPUT [--from FORMAT] [--to FORMAT] [--output PATH] [--prefix LABEL=NAMESPACE] [--max-records N] [--max-line-bytes N] [--max-statement-bytes N] [--max-document-bytes N]
  odin-rdf format INPUT [--output PATH] [--prefix LABEL=NAMESPACE] [--max-triples N] [--no-infer-prefixes]

Formats: ntriples (nt), nquads (nq), turtle (ttl), jsonld (json-ld, json; input only), rdfxml (rdf-xml, rdf, xml; input only)

INPUT and --output accept - for stdin and stdout. File output is written to a
same-directory temporary file and replaces the destination only after a
successful conversion and temporary-file close. Prefixes are used only for
Turtle output and may be repeated; use --prefix =https://example.com/ for the
default prefix.

convert infers a file syntax from the canonical .nt, .nq, .ttl, .jsonld, .json, .rdfxml, .rdf, and .xml extensions.
Explicit --from and --to values override that inference. Standard input and
output, as well as unrecognized file extensions, require the corresponding
explicit format option.

N-Quads named graphs can only be converted to N-Quads. The command rejects
other targets rather than silently discarding graph names.

convert accepts reader limits for untrusted input: --max-records N applies to
all source syntaxes, --max-line-bytes N applies to N-Triples and N-Quads,
--max-statement-bytes N applies to Turtle, and --max-document-bytes N applies
to JSON-LD and RDF/XML. Every N must be a positive decimal
integer.

format accepts Turtle input and produces stable, grouped Turtle. It retains the
complete graph in memory, removes exact duplicate triples, and infers safe
prefixes by default. Use --no-infer-prefixes to emit IRIREFs except for the
prefixes supplied explicitly. Use --max-triples N to reject an input before
the collector retains more than N triples.

Examples:
  odin-rdf convert input.ttl --output output.nt
  odin-rdf convert input.ttl --from turtle --to ntriples --output output.nt
  odin-rdf convert input.jsonld --output output.nq --max-document-bytes 16777216
  odin-rdf convert - --from ntriples --to turtle --prefix ex=https://example.com/
  odin-rdf format input.ttl --output formatted.ttl
`)
}

report_command_error :: proc(err: Command_Error) {
	if len(err.value) > 0 {
		fmt.eprintfln("odin-rdf: %s: %s (%s)", command_error_message(err.code), err.value, "use --help for usage")
	} else {
		fmt.eprintfln("odin-rdf: %s (%s)", command_error_message(err.code), "use --help for usage")
	}
}

report_convert_error :: proc(input: convert.Format, input_path: string, err: convert.Error) {
	label := input_path
	if label == "-" do label = "<stdin>"
	#partial switch err.code {
	case .Source_Parse_Error:
		fmt.eprintfln("odin-rdf: %s: %s input at line %d, column %d: %s", label, convert.format_name(input), err.line, err.column, err.detail)
	case .Output_Write_Error:
		if len(err.detail) > 0 {
			fmt.eprintfln("odin-rdf: %s: %s", convert.error_message(err.code), err.detail)
		} else {
			fmt.eprintfln("odin-rdf: %s: %v", convert.error_message(err.code), err.io_error)
		}
	case:
		if len(err.detail) > 0 {
			fmt.eprintfln("odin-rdf: %s: %s", convert.error_message(err.code), err.detail)
		} else {
			fmt.eprintfln("odin-rdf: %s", convert.error_message(err.code))
		}
	}
}

convert_to_file :: proc(input: io.Reader, output_path: string, options: convert.Options) -> convert.Result {
	path_builder := strings.builder_make()
	defer strings.builder_destroy(&path_builder)
	strings.write_string(&path_builder, output_path)
	strings.write_string(&path_builder, ".odin-rdf.tmp")
	temporary_path := strings.to_string(path_builder)
	temporary, open_err := os.open(temporary_path, {.Write, .Create, .Excl}, os.Permissions_Default_File)
	if open_err != nil do return convert.Result{error = {code = .Output_Write_Error, detail = os.error_string(open_err)}}

	result := convert.convert(input, os.to_writer(temporary), options)
	if result.error.code != .None {
		_ = os.close(temporary)
		_ = os.remove(temporary_path)
		return result
	}
	if close_err := os.close(temporary); close_err != nil {
		_ = os.remove(temporary_path)
		result.error = {code = .Output_Write_Error, detail = os.error_string(close_err)}
		return result
	}
	if rename_err := os.rename(temporary_path, output_path); rename_err != nil {
		_ = os.remove(temporary_path)
		result.error = {code = .Output_Write_Error, detail = os.error_string(rename_err)}
	}
	return result
}

run_convert :: proc(options: Command_Options) -> int {
	input_file := os.stdin
	close_input := false
	if options.input_path != "-" {
		file, open_err := os.open(options.input_path)
		if open_err != nil {
			fmt.eprintfln("odin-rdf: cannot open input %q: %s", options.input_path, os.error_string(open_err))
			return 1
		}
		input_file = file
		close_input = true
	}
	defer if close_input do _ = os.close(input_file)

	conversion_options := convert.Options{
		input = options.input_format,
		output = options.output_format,
		reader_limits = options.reader_limits,
		turtle_prefixes = options.prefixes[:],
	}
	input := os.to_reader(input_file)
	result: convert.Result
	if options.output_path == "-" {
		result = convert.convert(input, os.to_writer(os.stdout), conversion_options)
	} else {
		result = convert_to_file(input, options.output_path, conversion_options)
	}
	if result.error.code != .None {
		report_convert_error(options.input_format, options.input_path, result.error)
		return 1
	}
	return 0
}

Format_Graph :: struct {
	triples: [dynamic]rdf.Triple,
	owned: [dynamic]string,
}

destroy_format_graph :: proc(graph: ^Format_Graph) {
	for value in graph.owned do delete(value)
	delete(graph.owned)
	delete(graph.triples)
}

clone_format_string :: proc(graph: ^Format_Graph, value: string) -> string {
	if len(value) == 0 do return ""
	cloned := strings.clone(value) or_else ""
	append(&graph.owned, cloned)
	return cloned
}

clone_format_term :: proc(graph: ^Format_Graph, term: rdf.Term) -> rdf.Term {
	return rdf.Term{
		kind = term.kind,
		value = clone_format_string(graph, term.value),
		language = clone_format_string(graph, term.language),
		datatype = clone_format_string(graph, term.datatype),
		scope = term.scope,
	}
}

collect_format_triple :: proc(triple: rdf.Triple, data: rawptr) -> bool {
	graph := cast(^Format_Graph)data
	append(&graph.triples, rdf.Triple{
		clone_format_term(graph, triple.subject),
		clone_format_term(graph, triple.predicate),
		clone_format_term(graph, triple.object),
	})
	return true
}

write_all :: proc(output: io.Writer, text: string) -> io.Error {
	bytes := transmute([]byte)text
	for len(bytes) > 0 {
		count, err := io.write(output, bytes)
		if count < 0 || count > len(bytes) do return .Invalid_Write
		bytes = bytes[count:]
		if err != .None do return err
		if count == 0 do return .Short_Write
	}
	return .None
}

write_format_file :: proc(text, output_path: string) -> (io.Error, string) {
	path_builder := strings.builder_make()
	defer strings.builder_destroy(&path_builder)
	strings.write_string(&path_builder, output_path)
	strings.write_string(&path_builder, ".odin-rdf.tmp")
	temporary_path := strings.to_string(path_builder)
	temporary, open_err := os.open(temporary_path, {.Write, .Create, .Excl}, os.Permissions_Default_File)
	if open_err != nil do return .Invalid_Write, os.error_string(open_err)
	if write_err := write_all(os.to_writer(temporary), text); write_err != .None {
		_ = os.close(temporary)
		_ = os.remove(temporary_path)
		return write_err, ""
	}
	if close_err := os.close(temporary); close_err != nil {
		_ = os.remove(temporary_path)
		return .Invalid_Write, os.error_string(close_err)
	}
	if rename_err := os.rename(temporary_path, output_path); rename_err != nil {
		_ = os.remove(temporary_path)
		return .Invalid_Write, os.error_string(rename_err)
	}
	return .None, ""
}

run_format :: proc(options: Format_Command_Options) -> int {
	input_file := os.stdin
	close_input := false
	if options.input_path != "-" {
		file, open_err := os.open(options.input_path)
		if open_err != nil {
			fmt.eprintfln("odin-rdf: cannot open input %q: %s", options.input_path, os.error_string(open_err))
			return 1
		}
		input_file = file
		close_input = true
	}
	defer if close_input do _ = os.close(input_file)

	graph := Format_Graph{triples = make([dynamic]rdf.Triple), owned = make([dynamic]string)}
	defer destroy_format_graph(&graph)
	parsed := turtle.parse_reader(os.to_reader(input_file), collect_format_triple, turtle.Reader_Options{
		parse = turtle.Parse_Options{max_triples = options.max_triples},
	}, &graph)
	if parsed.error.code != .None {
		label := options.input_path
		if label == "-" do label = "<stdin>"
		if parsed.reader_error != .None {
			fmt.eprintfln("odin-rdf: %s: Turtle input at line %d, column %d: %s (%v)", label, parsed.error.line, parsed.error.column, turtle.parse_error_message(parsed.error.code), parsed.reader_error)
		} else {
			fmt.eprintfln("odin-rdf: %s: Turtle input at line %d, column %d: %s", label, parsed.error.line, parsed.error.column, turtle.parse_error_message(parsed.error.code))
		}
		return 1
	}

	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	prefix_policy := turtle.Prefix_Policy.Explicit_Only
	if options.infer_prefixes do prefix_policy = .Infer
	if err := turtle.format_triples(&builder, graph.triples[:], turtle.Format_Options{
		prefixes = options.prefixes[:],
		prefix_policy = prefix_policy,
	}); err != .None {
		fmt.eprintfln("odin-rdf: Turtle formatting error: %s", turtle.write_error_message(err))
		return 1
	}
	if options.output_path == "-" {
		if write_err := write_all(os.to_writer(os.stdout), strings.to_string(builder)); write_err != .None {
			fmt.eprintfln("odin-rdf: output write error: %v", write_err)
			return 1
		}
		return 0
	}
	if write_err, detail := write_format_file(strings.to_string(builder), options.output_path); write_err != .None {
		if len(detail) > 0 {
			fmt.eprintfln("odin-rdf: output write error: %s", detail)
		} else {
			fmt.eprintfln("odin-rdf: output write error: %v", write_err)
		}
		return 1
	}
	return 0
}

main :: proc() {
	if len(os.args) > 1 && os.args[1] == "format" {
		options, parse_err := parse_format_command_args(os.args[1:])
		exit_code := 0
		if options.help {
			print_help()
		} else if parse_err.code != .None {
			report_command_error(parse_err)
			exit_code = 2
		} else {
			exit_code = run_format(options)
		}
		delete(options.prefixes)
		os.exit(exit_code)
	}

	options, parse_err := parse_convert_args(os.args[1:])
	exit_code := 0
	if options.help {
		print_help()
	} else if parse_err.code != .None {
		report_command_error(parse_err)
		exit_code = 2
	} else {
		exit_code = run_convert(options)
	}
	delete(options.prefixes)
	os.exit(exit_code)
}
