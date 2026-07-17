package ntriples

import "core:io"
import rdf ".."

// DEFAULT_CHUNK_SIZE is used when Reader_Options.chunk_size is zero.
DEFAULT_CHUNK_SIZE :: 64 * 1024
// DEFAULT_MAX_LINE_BYTES is used when Reader_Options.max_line_bytes is zero.
DEFAULT_MAX_LINE_BYTES :: 16 * 1024 * 1024
@(private) MAX_EMPTY_READS :: 100

// Reader_Options controls buffering and resource limits for parse_reader.
Reader_Options :: struct {
	// Number of bytes requested from the reader per call. Zero uses 64 KiB.
	chunk_size:     int,
	// Maximum physical line length in bytes. Zero uses 16 MiB.
	max_line_bytes: int,
	// Maximum number of triples to emit. Zero disables the limit.
	max_triples:    u64,
}

// Reader_Result contains the parse outcome, preserved I/O error, and progress.
Reader_Result :: struct {
	error:       Parse_Error,
	reader_error: io.Error,
	triples:     u64,
	bytes_read:  u64,
}

@(private) Reader_State :: struct {
	sink:        Sink,
	user_data:   rawptr,
	max_triples: u64,
	triples:     u64,
	limit_hit:   bool,
	scope:       rdf.Blank_Node_Scope,
}

@(private) reader_sink :: proc(triple: rdf.Triple, data: rawptr) -> bool {
	state := cast(^Reader_State)data
	if state.max_triples > 0 && state.triples >= state.max_triples {
		state.limit_hit = true
		return false
	}
	state.triples += 1
	return state.sink(triple, state.user_data)
}

@(private) line_limit_exceeded :: proc(current, incoming, limit: int) -> bool {
	return incoming > limit - current
}

@(private) parse_reader_line :: proc(line: []byte, line_number: int, state: ^Reader_State) -> Parse_Error {
	err := parse_scoped(string(line), reader_sink, state.scope, state)
	if state.limit_hit do return Parse_Error{code = .Triple_Limit, line = line_number, column = err.column}
	if err.code != .None {
		err.line += line_number - 1
	}
	return err
}

// parse_reader incrementally parses an io.Reader with memory bounded by
// max_line_bytes plus chunk_size. Sink strings remain valid only for the current
// callback. Ownership of the reader remains with the caller.
parse_reader :: proc(
	reader: io.Reader,
	sink: Sink,
	options: Reader_Options = {},
	user_data: rawptr = nil,
) -> Reader_Result {
	result: Reader_Result
	if sink == nil {
		result.error = Parse_Error{code = .Missing_Sink, line = 1, column = 1}
		return result
	}
	if options.chunk_size < 0 {
		result.error = Parse_Error{code = .Invalid_Chunk_Size, line = 1, column = 1}
		return result
	}
	if options.max_line_bytes < 0 {
		result.error = Parse_Error{code = .Invalid_Line_Limit, line = 1, column = 1}
		return result
	}
	chunk_size := options.chunk_size
	if chunk_size == 0 do chunk_size = DEFAULT_CHUNK_SIZE
	max_line_bytes := options.max_line_bytes
	if max_line_bytes == 0 do max_line_bytes = DEFAULT_MAX_LINE_BYTES

	chunk := make([]byte, chunk_size)
	defer delete(chunk)
	line := make([dynamic]byte, 0, min(chunk_size, max_line_bytes))
	defer delete(line)
	state := Reader_State{sink = sink, user_data = user_data, max_triples = options.max_triples, scope = rdf.new_blank_node_scope()}
	line_number := 1
	skip_lf := false
	no_progress := 0

	for {
		n, read_err := io.read(reader, chunk)
		if n < 0 || n > len(chunk) {
			result.error = Parse_Error{code = .Reader_Error, line = line_number, column = 1}
			result.reader_error = n < 0 ? io.Error.Negative_Read : io.Error.Unknown
			break
		}
		if n == 0 && read_err == .None {
			no_progress += 1
			if no_progress >= MAX_EMPTY_READS {
				result.error = Parse_Error{code = .No_Progress, line = line_number, column = 1}
				result.reader_error = .No_Progress
				break
			}
			continue
		}
		no_progress = 0
		result.bytes_read += u64(n)
		start := 0
		for i in 0..<n {
			c := chunk[i]
			if skip_lf {
				skip_lf = false
				if c == '\n' {
					start = i + 1
					continue
				}
			}
			if c != '\r' && c != '\n' do continue
			part := chunk[start:i]
			if line_limit_exceeded(len(line), len(part), max_line_bytes) {
				result.error = Parse_Error{code = .Line_Too_Long, line = line_number, column = max_line_bytes + 1}
				break
			}
			append(&line, ..part)
			// Retain a physical terminator while parsing this record so malformed
			// literals have the same error code as the in-memory document path.
			append(&line, '\n')
			if parse_err := parse_reader_line(line[:], line_number, &state); parse_err.code != .None {
				result.error = parse_err
				break
			}
			clear(&line)
			line_number += 1
			start = i + 1
			if c == '\r' do skip_lf = true
		}
		if result.error.code != .None do break
		if start < n {
			part := chunk[start:n]
			if line_limit_exceeded(len(line), len(part), max_line_bytes) {
				result.error = Parse_Error{code = .Line_Too_Long, line = line_number, column = max_line_bytes + 1}
				break
			}
			append(&line, ..part)
		}
		if read_err != .None {
			if read_err != .EOF {
				result.error = Parse_Error{code = .Reader_Error, line = line_number, column = 1}
				result.reader_error = read_err
			}
			break
		}
	}

	if result.error.code == .None && len(line) > 0 {
		result.error = parse_reader_line(line[:], line_number, &state)
	}
	result.triples = state.triples
	return result
}
