package trig

import "core:io"
import "core:strings"
import rdf ".."

TRIG_DEFAULT_CHUNK_SIZE :: 64 * 1024
TRIG_MAX_EMPTY_READS    :: 100

// Reader_Options controls bounded buffering for a TriG document. TriG graph
// blocks may omit a terminating dot, so this first reader retains one bounded
// document before parsing it.
Reader_Options :: struct {
	parse:              Parse_Options,
	chunk_size:         int,
	max_document_bytes: int,
}

// Reader_Result returns the TriG outcome, underlying reader error, and number
// of dataset statements passed to the caller's sink.
Reader_Result :: struct {
	error:        Parse_Error,
	reader_error: io.Error,
	quads:        u64,
	bytes_read:   u64,
}

@(private) Reader_State :: struct {
	sink:      Sink,
	user_data: rawptr,
	quads:     u64,
}

@(private) forward_quad :: proc(quad: rdf.Quad, user_data: rawptr) -> bool {
	state := cast(^Reader_State)user_data
	if !state.sink(quad, state.user_data) do return false
	state.quads += 1
	return true
}

// parse_reader reads one bounded TriG document, then parses it as a dataset.
// Reader ownership remains with the caller.
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
	if options.max_document_bytes < 0 {
		result.error = Parse_Error{code = .Invalid_Option, line = 1, column = 1}
		return result
	}
	chunk_size := options.chunk_size
	if chunk_size == 0 do chunk_size = TRIG_DEFAULT_CHUNK_SIZE
	maximum := options.max_document_bytes
	if maximum == 0 do maximum = DEFAULT_MAX_DOCUMENT_BYTES
	chunk := make([]byte, chunk_size)
	defer delete(chunk)
	buffer := make([dynamic]byte, 0, min(chunk_size, maximum))
	defer delete(buffer)
	empty_reads := 0
	for {
		count, read_error := io.read(reader, chunk)
		if count < 0 || count > len(chunk) {
			result.error = Parse_Error{code = .Reader_Error, line = 1, column = 1}
			result.reader_error = count < 0 ? io.Error.Negative_Read : io.Error.Unknown
			return result
		}
		if count == 0 && read_error == .None {
			empty_reads += 1
			if empty_reads >= TRIG_MAX_EMPTY_READS {
				result.error = Parse_Error{code = .No_Progress, line = 1, column = 1}
				result.reader_error = .No_Progress
				return result
			}
			continue
		}
		empty_reads = 0
		result.bytes_read += u64(count)
		if count > maximum - len(buffer) {
			result.error = Parse_Error{code = .Document_Too_Large, line = 1, column = 1}
			return result
		}
		append(&buffer, ..chunk[:count])
		if read_error == .None do continue
		if read_error != .EOF {
			result.error = Parse_Error{code = .Reader_Error, line = 1, column = 1}
			result.reader_error = read_error
			return result
		}
		break
	}
	document, clone_error := strings.clone(string(buffer[:]))
	if clone_error != nil {
		result.error = Parse_Error{code = .Out_Of_Memory}
		return result
	}
	defer delete(document)
	state := Reader_State{sink = sink, user_data = user_data}
	result.error = parse(document, forward_quad, options.parse, &state)
	result.quads = state.quads
	return result
}
