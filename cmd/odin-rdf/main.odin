// odin-rdf is the repository's streaming RDF conversion command-line tool.
package main

import "core:fmt"
import "core:io"
import "core:os"
import "core:strings"
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
	Missing_From,
	Missing_To,
	Invalid_Format,
	Invalid_Prefix,
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
	case .Missing_From:         return "--from is required"
	case .Missing_To:           return "--to is required"
	case .Invalid_Format:       return "unsupported RDF syntax"
	case .Invalid_Prefix:       return "--prefix must use LABEL=NAMESPACE"
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
	help: bool,
}

parse_format :: proc(value: string) -> (convert.Format, bool) {
	switch value {
	case "ntriples", "n-triples", "nt": return .N_Triples, true
	case "nquads", "n-quads", "nq":      return .N_Quads, true
	case "turtle", "ttl":                 return .Turtle, true
	}
	return {}, false
}

append_prefix :: proc(prefixes: ^[dynamic]turtle.Prefix, value: string) -> bool {
	equals := strings.index_byte(value, '=')
	if equals < 0 do return false
	append(prefixes, turtle.Prefix{label = value[:equals], namespace = value[equals + 1:]})
	return true
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
		if !positional_only && (arg == "--from" || arg == "--to" || arg == "--output" || arg == "-o" || arg == "--prefix") {
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
		if !positional_only && len(arg) > 1 && arg[0] == '-' && arg != "-" do return options, Command_Error{code = .Unknown_Option, value = arg}
		if has_input do return options, Command_Error{code = .Extra_Input, value = arg}
		options.input_path = arg
		has_input = true
	}

	if !has_from do return options, Command_Error{code = .Missing_From}
	if !has_to do return options, Command_Error{code = .Missing_To}
	if !has_input do return options, Command_Error{code = .Missing_Input}
	if options.input_path != "-" && options.output_path != "-" && options.input_path == options.output_path {
		return options, Command_Error{code = .Same_Input_Output}
	}
	return options, {}
}

print_help :: proc() {
	fmt.println(`Usage:
  odin-rdf convert INPUT --from FORMAT --to FORMAT [--output PATH] [--prefix LABEL=NAMESPACE]

Formats: ntriples (nt), nquads (nq), turtle (ttl)

INPUT and --output accept - for stdin and stdout. File output is written to a
same-directory temporary file and replaces the destination only after a
successful conversion and temporary-file close. Prefixes are used only for
Turtle output and may be repeated; use --prefix =https://example.com/ for the
default prefix.

N-Quads named graphs can only be converted to N-Quads. The command rejects
other targets rather than silently discarding graph names.

Examples:
  odin-rdf convert input.ttl --from turtle --to ntriples --output output.nt
  odin-rdf convert - --from ntriples --to turtle --prefix ex=https://example.com/
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

main :: proc() {
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
