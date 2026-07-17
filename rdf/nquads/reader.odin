package nquads

import "core:io"
import rdf ".."

DEFAULT_CHUNK_SIZE     :: 64 * 1024
DEFAULT_MAX_LINE_BYTES :: 16 * 1024 * 1024
@(private) MAX_EMPTY_READS :: 100

// Reader_Options controls buffering and resource limits for parse_reader.
Reader_Options :: struct {
	chunk_size:     int,
	max_line_bytes: int,
	max_quads:      u64,
}

// Reader_Result contains the parse outcome, preserved I/O error, and progress.
Reader_Result :: struct {
	error:        Parse_Error,
	reader_error: io.Error,
	quads:        u64,
	bytes_read:   u64,
}

@(private) Reader_State :: struct {
	sink:      Sink,
	user_data: rawptr,
	max_quads: u64,
	quads:     u64,
	limit_hit: bool,
	scope:     rdf.Blank_Node_Scope,
}

@(private) reader_sink :: proc(quad: rdf.Quad, data: rawptr) -> bool {
	state := cast(^Reader_State)data
	if state.max_quads > 0 && state.quads >= state.max_quads {
		state.limit_hit = true
		return false
	}
	state.quads += 1
	return state.sink(quad, state.user_data)
}

@(private) line_limit_exceeded :: proc(current, incoming, limit: int) -> bool {
	return incoming > limit - current
}

@(private) parse_reader_line :: proc(line: []byte, line_number: int, state: ^Reader_State) -> Parse_Error {
	err := parse_line(string(line), reader_sink, state.scope, state)
	if state.limit_hit do return Parse_Error{code = .Quad_Limit, line = line_number, column = max(err.column, 1)}
	if err.code != .None do err.line = line_number
	return err
}

// parse_reader incrementally parses an io.Reader with memory bounded by
// max_line_bytes plus chunk_size. Sink strings remain callback-scoped.
parse_reader :: proc(reader: io.Reader, sink: Sink, options: Reader_Options = {}, user_data: rawptr = nil) -> Reader_Result {
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
	state := Reader_State{sink = sink, user_data = user_data, max_quads = options.max_quads, scope = rdf.new_blank_node_scope()}
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
				if c == '\n' { start = i + 1; continue }
			}
			if c != '\r' && c != '\n' do continue
			part := chunk[start:i]
			if line_limit_exceeded(len(line), len(part), max_line_bytes) {
				result.error = Parse_Error{code = .Line_Too_Long, line = line_number, column = max_line_bytes + 1}
				break
			}
			append(&line, ..part)
			if err := parse_reader_line(line[:], line_number, &state); err.code != .None { result.error = err; break }
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
	if result.error.code == .None && len(line) > 0 do result.error = parse_reader_line(line[:], line_number, &state)
	result.quads = state.quads
	return result
}
