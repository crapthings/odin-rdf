// odin-rdf is the repository's streaming RDF conversion command-line tool.
package main

import "core:fmt"
import "core:io"
import "core:os"
import "core:strconv"
import "core:strings"
import rdf "../../rdf"
import canon "../../rdf/canon"
import convert "../../rdf/convert"
import dataset "../../rdf/dataset"
import jsonld "../../rdf/jsonld"
import nquads "../../rdf/nquads"
import ntriples "../../rdf/ntriples"
import rdfxml "../../rdf/rdfxml"
import trig "../../rdf/trig"
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
	Invalid_Max_Quads,
	Incompatible_Format_Limit,
	Cannot_Infer_Input_Format,
	Cannot_Infer_Output_Format,
	Same_Input_Output,
	Missing_Compare_Input,
	Compare_Standard_Input,
	Missing_Diff_Input,
	Diff_Standard_Input,
	Invalid_Hash_Algorithm,
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
	case .Invalid_Max_Quads:    return "--max-quads must be a positive decimal integer"
	case .Incompatible_Format_Limit: return "format limit is not valid for selected RDF syntax"
	case .Cannot_Infer_Input_Format: return "cannot infer input RDF syntax; use --from"
	case .Cannot_Infer_Output_Format: return "cannot infer output RDF syntax; use --to"
	case .Same_Input_Output:    return "input and output paths must differ"
	case .Missing_Compare_Input: return "compare requires two input paths"
	case .Compare_Standard_Input: return "compare does not accept standard input"
	case .Missing_Diff_Input: return "diff requires two input paths"
	case .Diff_Standard_Input: return "diff does not accept standard input"
	case .Invalid_Hash_Algorithm: return "--algorithm must be sha256 or sha384"
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
	input_format: convert.Format,
	prefixes: [dynamic]turtle.Prefix,
	infer_prefixes: bool,
	max_triples: int,
	max_quads: int,
	help: bool,
}

Integrity_Command :: enum {
	Canon,
	Hash,
	Compare,
	Diff,
}

// Integrity_Command_Options configures commands that retain one complete,
// explicitly bounded dataset before using the RDFC-1.0 integrity APIs.
Integrity_Command_Options :: struct {
	command:       Integrity_Command,
	input_path:    string,
	other_path:    string,
	output_path:   string,
	input_format:  convert.Format,
	other_format:  convert.Format,
	reader_limits: convert.Reader_Limits,
	max_quads:     int,
	hash_algorithm: canon.Hash_Algorithm,
	help:          bool,
}

parse_format :: proc(value: string) -> (convert.Format, bool) {
	switch value {
	case "ntriples", "n-triples", "nt": return .N_Triples, true
	case "nquads", "n-quads", "nq":      return .N_Quads, true
	case "turtle", "ttl":                 return .Turtle, true
	case "jsonld", "json-ld", "json":      return .JSON_LD, true
	case "rdfxml", "rdf-xml", "rdf/xml", "rdf", "xml": return .RDF_XML, true
	case "trig": return .TriG, true
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
	if len(path) >= len(".trig") && path[len(path) - len(".trig"):] == ".trig" do return .TriG, true
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

parse_hash_algorithm :: proc(value: string) -> (canon.Hash_Algorithm, bool) {
	switch value {
	case "sha256", "sha-256": return .SHA_256, true
	case "sha384", "sha-384": return .SHA_384, true
	}
	return {}, false
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

// parse_format_command_args parses the Turtle and TriG batch formatter command.
// Formatting is necessarily batch-oriented, so its output is produced only
// after the complete input graph or dataset has parsed successfully.
parse_format_command_args :: proc(args: []string) -> (Format_Command_Options, Command_Error) {
	options := Format_Command_Options{output_path = "-", infer_prefixes = true}
	if len(args) == 0 do return options, Command_Error{code = .Missing_Command}
	if args[0] == "--help" || args[0] == "-h" {
		options.help = true
		return options, {}
	}
	if args[0] != "format" do return options, Command_Error{code = .Unknown_Command, value = args[0]}

	has_from, has_input := false, false
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
		if !positional_only && (arg == "--from" || arg == "--output" || arg == "-o" || arg == "--prefix" || arg == "--max-triples" || arg == "--max-quads") {
			if i + 1 >= len(args) do return options, Command_Error{code = .Missing_Option_Value, value = arg}
			i += 1
			value = args[i]
			needs_value = true
		}
		if !positional_only && (arg == "--from" || strings.has_prefix(arg, "--from=")) {
			if !needs_value do value = arg[len("--from="):]
			format, ok := parse_format(value)
			if !ok || (format != .Turtle && format != .TriG) do return options, Command_Error{code = .Invalid_Format, value = value}
			options.input_format = format
			has_from = true
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
		if !positional_only && (arg == "--max-triples" || strings.has_prefix(arg, "--max-triples=")) {
			if !needs_value do value = arg[len("--max-triples="):]
			max_triples, ok := parse_positive_decimal(value)
			if !ok do return options, Command_Error{code = .Invalid_Max_Triples, value = value}
			options.max_triples = max_triples
			continue
		}
		if !positional_only && (arg == "--max-quads" || strings.has_prefix(arg, "--max-quads=")) {
			if !needs_value do value = arg[len("--max-quads="):]
			max_quads, ok := parse_positive_decimal(value)
			if !ok do return options, Command_Error{code = .Invalid_Max_Quads, value = value}
			options.max_quads = max_quads
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
		if format != .Turtle && format != .TriG do return options, Command_Error{code = .Invalid_Format, value = options.input_path}
		options.input_format = format
	}
	if options.input_format == .Turtle && options.max_quads > 0 do return options, Command_Error{code = .Incompatible_Format_Limit, value = "--max-quads is only valid for TriG formatting"}
	if options.input_format == .TriG && options.max_triples > 0 do return options, Command_Error{code = .Incompatible_Format_Limit, value = "--max-triples is only valid for Turtle formatting"}
	if options.input_path != "-" && options.output_path != "-" && options.input_path == options.output_path {
		return options, Command_Error{code = .Same_Input_Output}
	}
	return options, {}
}

// parse_integrity_command_args parses the bounded canon, hash, compare, and
// diff workflows. --from applies to both inputs of compare and diff; otherwise
// each file infers its own format from its extension. The command-level
// max_quads bound applies both to owned collection and RDFC-1.0
// canonicalization.
parse_integrity_command_args :: proc(args: []string) -> (Integrity_Command_Options, Command_Error) {
	options := Integrity_Command_Options{output_path = "-", max_quads = canon.DEFAULT_MAX_QUADS}
	if len(args) == 0 do return options, Command_Error{code = .Missing_Command}
	if args[0] == "--help" || args[0] == "-h" {
		options.help = true
		return options, {}
	}
	switch args[0] {
	case "canon": options.command = .Canon
	case "hash": options.command = .Hash
	case "compare": options.command = .Compare
	case "diff": options.command = .Diff
	case: return options, Command_Error{code = .Unknown_Command, value = args[0]}
	}

	has_from, positional_only := false, false
	input_count := 0
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
		if !positional_only && (arg == "--from" || arg == "--output" || arg == "-o" || arg == "--algorithm" || arg == "--max-quads" || arg == "--max-records" || arg == "--max-line-bytes" || arg == "--max-statement-bytes" || arg == "--max-document-bytes") {
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
		if !positional_only && (arg == "--output" || arg == "-o" || strings.has_prefix(arg, "--output=")) {
			if options.command == .Compare do return options, Command_Error{code = .Unknown_Option, value = arg}
			if !needs_value do value = arg[len("--output="):]
			if len(value) == 0 do return options, Command_Error{code = .Missing_Option_Value, value = "--output"}
			options.output_path = value
			continue
		}
		if !positional_only && (arg == "--algorithm" || strings.has_prefix(arg, "--algorithm=")) {
			if !needs_value do value = arg[len("--algorithm="):]
			algorithm, ok := parse_hash_algorithm(value)
			if !ok do return options, Command_Error{code = .Invalid_Hash_Algorithm, value = value}
			options.hash_algorithm = algorithm
			continue
		}
		if !positional_only && (arg == "--max-quads" || strings.has_prefix(arg, "--max-quads=")) {
			if !needs_value do value = arg[len("--max-quads="):]
			max_quads, ok := parse_positive_decimal(value)
			if !ok do return options, Command_Error{code = .Invalid_Max_Quads, value = value}
			options.max_quads = max_quads
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
		if input_count == 0 {
			options.input_path = arg
		} else if input_count == 1 && (options.command == .Compare || options.command == .Diff) {
			options.other_path = arg
		} else {
			return options, Command_Error{code = .Extra_Input, value = arg}
		}
		input_count += 1
	}
	if options.command == .Compare || options.command == .Diff {
		if input_count != 2 {
			if options.command == .Compare do return options, Command_Error{code = .Missing_Compare_Input}
			return options, Command_Error{code = .Missing_Diff_Input}
		}
		if options.input_path == "-" || options.other_path == "-" {
			if options.command == .Compare do return options, Command_Error{code = .Compare_Standard_Input}
			return options, Command_Error{code = .Diff_Standard_Input}
		}
	} else if input_count == 0 {
		return options, Command_Error{code = .Missing_Input}
	}
	if has_from {
		if options.command == .Compare || options.command == .Diff do options.other_format = options.input_format
		if options.command != .Compare && options.input_path != "-" && options.output_path != "-" && options.input_path == options.output_path do return options, Command_Error{code = .Same_Input_Output}
		if options.command == .Diff && options.other_path != "-" && options.output_path != "-" && options.other_path == options.output_path do return options, Command_Error{code = .Same_Input_Output}
		return options, {}
	}
	format, ok := infer_format_from_path(options.input_path)
	if !ok do return options, Command_Error{code = .Cannot_Infer_Input_Format, value = options.input_path}
	options.input_format = format
	if options.command == .Compare || options.command == .Diff {
		other_format, other_ok := infer_format_from_path(options.other_path)
		if !other_ok do return options, Command_Error{code = .Cannot_Infer_Input_Format, value = options.other_path}
		options.other_format = other_format
	}
	if options.command != .Compare && options.input_path != "-" && options.output_path != "-" && options.input_path == options.output_path do return options, Command_Error{code = .Same_Input_Output}
	if options.command == .Diff && options.other_path != "-" && options.output_path != "-" && options.other_path == options.output_path do return options, Command_Error{code = .Same_Input_Output}
	return options, {}
}

print_help :: proc() {
	fmt.println(`Usage:
	  odin-rdf convert INPUT [--from FORMAT] [--to FORMAT] [--output PATH] [--prefix LABEL=NAMESPACE] [--max-records N] [--max-line-bytes N] [--max-statement-bytes N] [--max-document-bytes N]
	  odin-rdf format INPUT [--from turtle|trig] [--output PATH] [--prefix LABEL=NAMESPACE] [--max-triples N] [--max-quads N] [--no-infer-prefixes]
	  odin-rdf canon INPUT [--from FORMAT] [--output PATH] [--algorithm sha256|sha384] [--max-quads N] [--max-records N] [--max-line-bytes N] [--max-statement-bytes N] [--max-document-bytes N]
	  odin-rdf hash INPUT [--from FORMAT] [--output PATH] [--algorithm sha256|sha384] [--max-quads N] [--max-records N] [--max-line-bytes N] [--max-statement-bytes N] [--max-document-bytes N]
	  odin-rdf compare LEFT RIGHT [--from FORMAT] [--algorithm sha256|sha384] [--max-quads N] [--max-records N] [--max-line-bytes N] [--max-statement-bytes N] [--max-document-bytes N]
	  odin-rdf diff BEFORE AFTER [--from FORMAT] [--output PATH] [--algorithm sha256|sha384] [--max-quads N] [--max-records N] [--max-line-bytes N] [--max-statement-bytes N] [--max-document-bytes N]

Formats: ntriples (nt), nquads (nq), turtle (ttl), trig, jsonld (json-ld, json; input only), rdfxml (rdf-xml, rdf, xml; bounded batch output)

INPUT and --output accept - for stdin and stdout. File output is written to a
same-directory temporary file and replaces the destination only after a
successful conversion and temporary-file close. Prefixes are used for Turtle
and TriG output and may be repeated; use --prefix =https://example.com/ for
the default prefix.

convert infers a file syntax from the canonical .nt, .nq, .ttl, .jsonld, .json, .rdfxml, .rdf, .xml, and .trig extensions.
Explicit --from and --to values override that inference. Standard input and
output, as well as unrecognized file extensions, require the corresponding
explicit format option.

Named graphs can be converted to N-Quads or TriG. The command rejects other
targets rather than silently discarding graph names.

RDF/XML output retains the complete default graph and writes one document only
after parsing succeeds. It requires --max-records N; this is its graph-size
admission bound and applies before standard output or a target file receives XML.

convert accepts reader limits for untrusted input: --max-records N applies to
all source syntaxes, --max-line-bytes N applies to N-Triples and N-Quads,
--max-statement-bytes N applies to Turtle, and --max-document-bytes N applies
to JSON-LD, RDF/XML, and TriG. Every N must be a positive decimal
integer.

format accepts Turtle or TriG input and produces stable, grouped output in the
same syntax. File inputs infer .ttl or .trig; standard input requires --from.
It retains the complete graph or dataset, removes exact duplicate statements,
and infers safe prefixes by default. Use --no-infer-prefixes to emit IRIREFs
except for explicitly supplied prefixes. Use --max-triples N for Turtle or
--max-quads N for TriG to reject input before retained output exceeds the cap.

canon, hash, compare, and diff retain a complete owned RDF dataset before processing.
They accept every supported input syntax, infer each file input independently,
and default --max-quads to 100000. Set --max-quads N to choose the shared
collection and canonicalization admission bound. Use the source reader limits
for untrusted input; compare accepts two file paths (not standard input),
prints equal or different, and exits 0 or 1 respectively (2 on an error).
diff accepts two file paths (not standard input), writes a deterministic
canonical N-Quads line diff with - for removed and + for added lines, and exits
0 when equal, 1 when changed, or 2 on an error. It is not a minimum blank-node
edit script: structural changes can change canonical blank-node identifiers.
hash writes a lowercase hexadecimal SHA-256 digest by default; --algorithm
sha384 selects SHA-384. These commands prepare integrity and signing-protocol
inputs; they do not sign data or add storage/query behavior.

Examples:
  odin-rdf convert input.ttl --output output.nt
  odin-rdf convert input.ttl --from turtle --to ntriples --output output.nt
  odin-rdf convert input.jsonld --output output.nq --max-document-bytes 16777216
  odin-rdf convert - --from ntriples --to turtle --prefix ex=https://example.com/
  odin-rdf format input.ttl --output formatted.ttl
  odin-rdf format input.trig --output formatted.trig --max-quads 100000
  odin-rdf canon input.trig --output canonical.nq --max-quads 100000
  odin-rdf hash input.ttl --algorithm sha384
  odin-rdf compare left.trig right.trig
  odin-rdf diff before.trig after.trig --output changes.nqdiff
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

	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	prefix_policy := turtle.Prefix_Policy.Explicit_Only
	if options.infer_prefixes do prefix_policy = .Infer
	label := options.input_path
	if label == "-" do label = "<stdin>"
	#partial switch options.input_format {
	case .Turtle:
		graph := Format_Graph{triples = make([dynamic]rdf.Triple), owned = make([dynamic]string)}
		defer destroy_format_graph(&graph)
		parsed := turtle.parse_reader(os.to_reader(input_file), collect_format_triple, turtle.Reader_Options{
			parse = turtle.Parse_Options{max_triples = options.max_triples},
		}, &graph)
		if parsed.error.code != .None {
			if parsed.reader_error != .None {
				fmt.eprintfln("odin-rdf: %s: Turtle input at line %d, column %d: %s (%v)", label, parsed.error.line, parsed.error.column, turtle.parse_error_message(parsed.error.code), parsed.reader_error)
			} else {
				fmt.eprintfln("odin-rdf: %s: Turtle input at line %d, column %d: %s", label, parsed.error.line, parsed.error.column, turtle.parse_error_message(parsed.error.code))
			}
			return 1
		}
		if err := turtle.format_triples(&builder, graph.triples[:], turtle.Format_Options{
			prefixes = options.prefixes[:],
			prefix_policy = prefix_policy,
		}); err != .None {
			fmt.eprintfln("odin-rdf: Turtle formatting error: %s", turtle.write_error_message(err))
			return 1
		}
	case .TriG:
		collector: dataset.Collector
		if init_err := dataset.init(&collector, dataset.Options{max_quads = options.max_quads}); init_err != .None {
			fmt.eprintfln("odin-rdf: TriG collection error: %s", dataset.error_message(init_err))
			return 1
		}
		defer dataset.destroy(&collector)
		parsed := trig.parse_reader(os.to_reader(input_file), dataset.sink, trig.Reader_Options{
			parse = trig.Parse_Options{max_quads = options.max_quads},
		}, &collector)
		if parsed.error.code != .None {
			if parsed.error.code == .Stopped && collector.last_error != .None {
				fmt.eprintfln("odin-rdf: %s: TriG collection error: %s", label, dataset.error_message(collector.last_error))
			} else if parsed.reader_error != .None {
				fmt.eprintfln("odin-rdf: %s: TriG input at line %d, column %d: %s (%v)", label, parsed.error.line, parsed.error.column, trig.parse_error_message(parsed.error.code), parsed.reader_error)
			} else {
				fmt.eprintfln("odin-rdf: %s: TriG input at line %d, column %d: %s", label, parsed.error.line, parsed.error.column, trig.parse_error_message(parsed.error.code))
			}
			return 1
		}
		if err := trig.format_quads(&builder, collector.quads[:], trig.Format_Options{
			prefixes = options.prefixes[:],
			prefix_policy = prefix_policy,
		}); err != .None {
			fmt.eprintfln("odin-rdf: TriG formatting error: %s", trig.write_error_message(err))
			return 1
		}
	case:
		fmt.eprintfln("odin-rdf: unsupported RDF syntax for formatting")
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

// collect_integrity_dataset parses one supported input syntax into an owned,
// capacity-bounded quad collection. It is intentionally separate from convert:
// canonicalization requires a complete dataset and must not masquerade as a
// streaming output path.
set_integrity_collection_error :: proc(result: ^convert.Result, collector: ^dataset.Collector, line, column: int, detail: string, reader_error: io.Error = .None) {
	if collector.last_error != .None {
		result.error = convert.Error{code = .Graph_Collection_Error, detail = dataset.error_message(collector.last_error)}
	} else {
		result.error = convert.Error{code = .Source_Parse_Error, line = line, column = column, detail = detail, io_error = reader_error}
	}
}

collect_integrity_dataset :: proc(reader: io.Reader, format: convert.Format, limits: convert.Reader_Limits, collector: ^dataset.Collector) -> convert.Result {
	result: convert.Result
	#partial switch format {
	case .N_Triples:
		parsed := ntriples.parse_reader(reader, dataset.triple_sink, ntriples.Reader_Options{
			chunk_size = limits.chunk_size,
			max_line_bytes = limits.max_line_bytes,
			max_triples = u64(limits.max_records),
		}, collector)
		result.bytes_read = parsed.bytes_read
		if parsed.error.code != .None do set_integrity_collection_error(&result, collector, parsed.error.line, parsed.error.column, ntriples.parse_error_message(parsed.error.code), parsed.reader_error)
	case .N_Quads:
		parsed := nquads.parse_reader(reader, dataset.sink, nquads.Reader_Options{
			chunk_size = limits.chunk_size,
			max_line_bytes = limits.max_line_bytes,
			max_quads = u64(limits.max_records),
		}, collector)
		result.bytes_read = parsed.bytes_read
		if parsed.error.code != .None do set_integrity_collection_error(&result, collector, parsed.error.line, parsed.error.column, nquads.parse_error_message(parsed.error.code), parsed.reader_error)
	case .Turtle:
		parsed := turtle.parse_reader(reader, dataset.triple_sink, turtle.Reader_Options{
			parse = turtle.Parse_Options{max_triples = limits.max_records},
			chunk_size = limits.chunk_size,
			max_statement_bytes = limits.max_statement_bytes,
		}, collector)
		result.bytes_read = parsed.bytes_read
		if parsed.error.code != .None do set_integrity_collection_error(&result, collector, parsed.error.line, parsed.error.column, turtle.parse_error_message(parsed.error.code), parsed.reader_error)
	case .JSON_LD:
		parsed := jsonld.parse_reader(reader, dataset.sink, jsonld.Reader_Options{
			chunk_size = limits.chunk_size,
			max_document_bytes = limits.max_document_bytes,
			parse = jsonld.Options{max_quads = limits.max_records},
		}, collector)
		result.bytes_read = parsed.bytes_read
		if parsed.error.code != .None do set_integrity_collection_error(&result, collector, parsed.error.line, parsed.error.column, jsonld.parse_error_message(parsed.error.code), parsed.reader_error)
	case .RDF_XML:
		parsed := rdfxml.parse_reader(reader, dataset.sink, rdfxml.Reader_Options{
			chunk_size = limits.chunk_size,
			max_document_bytes = limits.max_document_bytes,
			parse = rdfxml.Options{max_quads = limits.max_records},
		}, collector)
		result.bytes_read = parsed.bytes_read
		if parsed.error.code != .None do set_integrity_collection_error(&result, collector, parsed.error.line, parsed.error.column, rdfxml.parse_error_message(parsed.error.code), parsed.reader_error)
	case .TriG:
		parsed := trig.parse_reader(reader, dataset.sink, trig.Reader_Options{
			chunk_size = limits.chunk_size,
			max_document_bytes = limits.max_document_bytes,
			parse = trig.Parse_Options{max_quads = limits.max_records},
		}, collector)
		result.bytes_read = parsed.bytes_read
		if parsed.error.code != .None do set_integrity_collection_error(&result, collector, parsed.error.line, parsed.error.column, trig.parse_error_message(parsed.error.code), parsed.reader_error)
	case:
		result.error.code = .Unsupported_Input_Format
	}
	if result.error.code == .None do result.statements = u64(len(collector.quads))
	return result
}

load_integrity_dataset :: proc(path: string, format: convert.Format, limits: convert.Reader_Limits, max_quads: int, collector: ^dataset.Collector) -> convert.Error {
	if init_err := dataset.init(collector, dataset.Options{max_quads = max_quads}); init_err != .None do return convert.Error{code = .Graph_Collection_Error, detail = dataset.error_message(init_err)}
	input_file := os.stdin
	close_input := false
	if path != "-" {
		file, open_err := os.open(path)
		if open_err != nil do return convert.Error{code = .Source_Parse_Error, detail = os.error_string(open_err)}
		input_file = file
		close_input = true
	}
	defer if close_input do _ = os.close(input_file)
	return collect_integrity_dataset(os.to_reader(input_file), format, limits, collector).error
}

report_integrity_error :: proc(format: convert.Format, path: string, err: convert.Error) {
	if err.code == .Source_Parse_Error && err.line == 0 && len(err.detail) > 0 {
		fmt.eprintfln("odin-rdf: cannot open input %q: %s", path, err.detail)
		return
	}
	report_convert_error(format, path, err)
}

write_integrity_result :: proc(text, output_path: string) -> int {
	if output_path == "-" {
		if write_err := write_all(os.to_writer(os.stdout), text); write_err != .None {
			fmt.eprintfln("odin-rdf: output write error: %v", write_err)
			return 1
		}
		return 0
	}
	if write_err, detail := write_format_file(text, output_path); write_err != .None {
		if len(detail) > 0 {
			fmt.eprintfln("odin-rdf: output write error: %s", detail)
		} else {
			fmt.eprintfln("odin-rdf: output write error: %v", write_err)
		}
		return 1
	}
	return 0
}

// next_canonical_line returns the next newline-delimited canonical N-Quads
// line. RDFC output is sorted, so diffing its complete lines produces stable
// machine-readable text without reparsing or attempting blank-node matching.
next_canonical_line :: proc(text: string, offset: ^int) -> string {
	start := offset^
	for offset^ < len(text) && text[offset^] != '\n' do offset^ += 1
	if offset^ < len(text) do offset^ += 1
	return text[start:offset^]
}

// write_canonical_diff emits the left-only lines before the right-only lines
// they sort against. A changed blank-node structure can alter canonical labels,
// so this is intentionally a deterministic canonical text diff rather than a
// minimum edit script.
write_canonical_diff :: proc(builder: ^strings.Builder, before, after: string) -> bool {
	before_offset, after_offset := 0, 0
	has_changes := false
	for before_offset < len(before) || after_offset < len(after) {
		if before_offset == len(before) {
			strings.write_string(builder, "+ ")
			strings.write_string(builder, next_canonical_line(after, &after_offset))
			has_changes = true
			continue
		}
		if after_offset == len(after) {
			strings.write_string(builder, "- ")
			strings.write_string(builder, next_canonical_line(before, &before_offset))
			has_changes = true
			continue
		}
		before_line := next_canonical_line(before, &before_offset)
		after_line := next_canonical_line(after, &after_offset)
		comparison := strings.compare(before_line, after_line)
		if comparison < 0 {
			strings.write_string(builder, "- ")
			strings.write_string(builder, before_line)
			has_changes = true
			after_offset -= len(after_line)
		} else if comparison > 0 {
			strings.write_string(builder, "+ ")
			strings.write_string(builder, after_line)
			has_changes = true
			before_offset -= len(before_line)
		}
	}
	return has_changes
}

run_integrity_command :: proc(options: Integrity_Command_Options) -> int {
	left: dataset.Collector
	left_error := load_integrity_dataset(options.input_path, options.input_format, options.reader_limits, options.max_quads, &left)
	defer dataset.destroy(&left)
	if left_error.code != .None {
		report_integrity_error(options.input_format, options.input_path, left_error)
		if options.command == .Compare || options.command == .Diff do return 2
		return 1
	}

	if options.command == .Compare || options.command == .Diff {
		right: dataset.Collector
		right_error := load_integrity_dataset(options.other_path, options.other_format, options.reader_limits, options.max_quads, &right)
		defer dataset.destroy(&right)
		if right_error.code != .None {
			report_integrity_error(options.other_format, options.other_path, right_error)
			return 2
		}
		canon_options := canon.Options{hash_algorithm = options.hash_algorithm, max_quads = options.max_quads}
		if options.command == .Compare {
			equal, canon_error := canon.isomorphic(left.quads[:], right.quads[:], canon_options)
			if canon_error != .None {
				fmt.eprintfln("odin-rdf: dataset comparison error: %s", canon.error_message(canon_error))
				return 2
			}
			if equal {
				fmt.println("equal")
				return 0
			}
			fmt.println("different")
			return 1
		}

		before_builder := strings.builder_make()
		defer strings.builder_destroy(&before_builder)
		after_builder := strings.builder_make()
		defer strings.builder_destroy(&after_builder)
		if canon_error := canon.canonicalize(&before_builder, left.quads[:], canon_options); canon_error != .None {
			fmt.eprintfln("odin-rdf: dataset diff error: %s", canon.error_message(canon_error))
			return 2
		}
		if canon_error := canon.canonicalize(&after_builder, right.quads[:], canon_options); canon_error != .None {
			fmt.eprintfln("odin-rdf: dataset diff error: %s", canon.error_message(canon_error))
			return 2
		}
		diff_builder := strings.builder_make()
		defer strings.builder_destroy(&diff_builder)
		has_changes := write_canonical_diff(&diff_builder, strings.to_string(before_builder), strings.to_string(after_builder))
		if write_integrity_result(strings.to_string(diff_builder), options.output_path) != 0 do return 2
		if has_changes do return 1
		return 0
	}

	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	canon_options := canon.Options{hash_algorithm = options.hash_algorithm, max_quads = options.max_quads}
	canon_error := canon.Error_Code.None
	if options.command == .Canon {
		canon_error = canon.canonicalize(&builder, left.quads[:], canon_options)
	} else {
		canon_error = canon.canonical_hash(&builder, left.quads[:], canon_options)
		if canon_error == .None do strings.write_byte(&builder, '\n')
	}
	if canon_error != .None {
		fmt.eprintfln("odin-rdf: canonicalization error: %s", canon.error_message(canon_error))
		return 1
	}
	return write_integrity_result(strings.to_string(builder), options.output_path)
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
	if len(os.args) > 1 && (os.args[1] == "canon" || os.args[1] == "hash" || os.args[1] == "compare" || os.args[1] == "diff") {
		options, parse_err := parse_integrity_command_args(os.args[1:])
		exit_code := 0
		if options.help {
			print_help()
		} else if parse_err.code != .None {
			report_command_error(parse_err)
			exit_code = 2
		} else {
			exit_code = run_integrity_command(options)
		}
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
