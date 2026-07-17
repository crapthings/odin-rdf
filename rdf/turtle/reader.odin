package turtle

import "core:io"

DEFAULT_CHUNK_SIZE         :: 64 * 1024
DEFAULT_MAX_STATEMENT_BYTES :: 16 * 1024 * 1024
@(private) MAX_EMPTY_READS :: 100

// Reader_Options combines Turtle document limits with bounded input buffering.
Reader_Options :: struct {
	// Parser options shared with the memory entry point.
	parse:               Parse_Options,
	// Bytes requested per read. Zero uses DEFAULT_CHUNK_SIZE.
	chunk_size:          int,
	// Maximum bytes buffered for one top-level production.
	max_statement_bytes: int,
}

// Reader_Result contains the parse outcome, preserved I/O error, and progress.
Reader_Result :: struct {
	error:        Parse_Error,
	reader_error: io.Error,
	triples:      u64,
	bytes_read:   u64,
}

@(private) ascii_keyword_prefix :: proc(input: []byte, keyword: string) -> bool {
	if len(input) <= len(keyword) do return false
	for c, index in keyword {
		actual := input[index]
		if actual >= 'a' && actual <= 'z' do actual -= 'a' - 'A'
		expected := byte(c)
		if expected >= 'a' && expected <= 'z' do expected -= 'a' - 'A'
		if actual != expected do return false
	}
	next := input[len(keyword)]
	return next == ' ' || next == '\t' || next == '\r' || next == '\n'
}

@(private) Frame_State :: struct {
	cursor:           int,
	initialized:      bool,
	sparql_directive: bool,
	quote:            byte,
	long_quote:       bool,
	escaped:          bool,
	in_iri:           bool,
	comment:          bool,
	square_depth:     int,
	paren_depth:      int,
}

// complete_unit_end incrementally finds one complete top-level production.
// It is only a framing lexer; parse_document remains the grammar authority.
@(private) complete_unit_end :: proc(input: []byte, state: ^Frame_State, eof := false) -> int {
	if !state.initialized {
		i := state.cursor
		for i < len(input) {
			if input[i] == ' ' || input[i] == '\t' || input[i] == '\r' || input[i] == '\n' { i += 1; continue }
			break
		}
		if i >= len(input) {
			state.cursor = i
			return eof ? len(input) : -1
		}
		remaining := len(input) - i
		if input[i] != '#' && !eof && ((input[i] == 'P' || input[i] == 'p') && remaining <= 6 || (input[i] == 'B' || input[i] == 'b') && remaining <= 4) {
			state.cursor = i
			return -1
		}
		state.sparql_directive = input[i] != '#' && (ascii_keyword_prefix(input[i:], "PREFIX") || ascii_keyword_prefix(input[i:], "BASE"))
		state.initialized = true
		state.cursor = i
	}
	index := state.cursor
	for index < len(input) {
		c := input[index]
		if state.comment {
			if c == '\r' || c == '\n' do state.comment = false
			index += 1
			continue
		}
		if state.in_iri {
			if state.escaped { state.escaped = false; index += 1; continue }
			if c == '\\' { state.escaped = true; index += 1; continue }
			if c == '>' {
				state.in_iri = false
				if state.sparql_directive do return index + 1
			}
			index += 1
			continue
		}
		if state.quote != 0 {
			if state.escaped { state.escaped = false; index += 1; continue }
			if c == '\\' { state.escaped = true; index += 1; continue }
			if c == state.quote {
				if state.long_quote {
					if index + 2 >= len(input) && !eof { state.cursor = index; return -1 }
					if index + 2 < len(input) && input[index + 1] == state.quote && input[index + 2] == state.quote {
						state.quote = 0
						index += 2
					}
				} else do state.quote = 0
			}
			index += 1
			continue
		}
		if state.escaped {
			state.escaped = false
			index += 1
			continue
		}
		if c == '\\' {
			state.escaped = true
			index += 1
			continue
		}
		switch c {
		case '#': state.comment = true
		case '<': state.in_iri = true
		case '\'', '"':
			if index + 2 >= len(input) && !eof { state.cursor = index; return -1 }
			state.quote = c
			if index + 2 < len(input) && input[index + 1] == c && input[index + 2] == c {
				state.long_quote = true
				index += 2
			} else {
				state.long_quote = false
			}
		case '[': state.square_depth += 1
		case ']': if state.square_depth > 0 do state.square_depth -= 1
		case '(': state.paren_depth += 1
		case ')': if state.paren_depth > 0 do state.paren_depth -= 1
		case '.':
			if state.square_depth == 0 && state.paren_depth == 0 {
				if index + 1 == len(input) && !eof { state.cursor = index; return -1 }
				if (index + 1 == len(input) && eof) || (index + 1 < len(input) && (input[index + 1] == ' ' || input[index + 1] == '\t' || input[index + 1] == '\r' || input[index + 1] == '\n' || input[index + 1] == '#' || input[index + 1] == '@' || input[index + 1] == '<' || input[index + 1] == '_' || input[index + 1] == '[' || input[index + 1] == '(')) {
					return index + 1
				}
			}
		}
		index += 1
	}
	state.cursor = index
	if eof do return len(input)
	return -1
}

@(private) consume_buffer :: proc(buffer: ^[dynamic]byte, count: int) {
	remaining := len(buffer^) - count
	if remaining > 0 do copy(buffer^[:remaining], buffer^[count:])
	resize(buffer, remaining)
}

// parse_reader incrementally parses RDF 1.1 Turtle with memory bounded by the
// configured statement, token, prefix, nesting, and pending-triple limits.
// Ownership of the reader remains with the caller.
parse_reader :: proc(reader: io.Reader, sink: Sink, options: Reader_Options = {}, user_data: rawptr = nil) -> Reader_Result {
	result: Reader_Result
	if options.chunk_size < 0 || options.max_statement_bytes < 0 {
		code: Error_Code = .Invalid_Chunk_Size
		if options.max_statement_bytes < 0 do code = .Invalid_Statement_Limit
		result.error = Parse_Error{code = code, line = 1, column = 1}
		return result
	}
	chunk_size := options.chunk_size
	if chunk_size == 0 do chunk_size = DEFAULT_CHUNK_SIZE
	max_statement_bytes := options.max_statement_bytes
	if max_statement_bytes == 0 do max_statement_bytes = DEFAULT_MAX_STATEMENT_BYTES
	p, init_err := init_parser("", sink, options.parse, user_data)
	if init_err.code != .None {
		if p.prefixes != nil do destroy_parser(&p)
		result.error = init_err
		return result
	}
	defer destroy_parser(&p)
	chunk := make([]byte, chunk_size)
	defer delete(chunk)
	buffer := make([dynamic]byte, 0, min(chunk_size, max_statement_bytes))
	defer delete(buffer)
	line, column := 1, 1
	frame: Frame_State
	no_progress := 0
	done := false
	for !done {
		n, read_err := io.read(reader, chunk)
		if n < 0 || n > len(chunk) {
			result.error = Parse_Error{code = .Reader_Error, line = line, column = column}
			result.reader_error = n < 0 ? io.Error.Negative_Read : io.Error.Unknown
			break
		}
		if n == 0 && read_err == .None {
			no_progress += 1
			if no_progress >= MAX_EMPTY_READS {
				result.error = Parse_Error{code = .No_Progress, line = line, column = column}
				result.reader_error = .No_Progress
				break
			}
			continue
		}
		no_progress = 0
		result.bytes_read += u64(n)
		done = read_err != .None
		if done && read_err != .EOF {
			result.error = Parse_Error{code = .Reader_Error, line = line, column = column}
			result.reader_error = read_err
			break
		}
		for byte in chunk[:n] {
			if len(buffer) >= max_statement_bytes {
				result.error = Parse_Error{code = .Statement_Too_Long, line = line, column = column}
				done = true
				break
			}
			append(&buffer, byte)
			end := complete_unit_end(buffer[:], &frame, false)
			if end < 0 do continue
			p.scanner.input = string(buffer[:end])
			p.scanner.pos = 0
			p.scanner.line = line
			p.scanner.column = column
			if parse_err := parse_document(&p); parse_err.code != .None {
				result.error = parse_err
				done = true
				break
			}
			line, column = p.scanner.line, p.scanner.column
			consume_buffer(&buffer, end)
			frame = {}
		}
		if result.error.code != .None do break
		if done && len(buffer) > 0 {
			end := complete_unit_end(buffer[:], &frame, true)
			if end > 0 {
				p.scanner.input = string(buffer[:end])
				p.scanner.pos = 0
				p.scanner.line = line
				p.scanner.column = column
				if parse_err := parse_document(&p); parse_err.code != .None {
					result.error = parse_err
					break
				}
				line, column = p.scanner.line, p.scanner.column
				consume_buffer(&buffer, end)
				frame = {}
			}
		}
	}
	result.triples = u64(p.emitted)
	return result
}
