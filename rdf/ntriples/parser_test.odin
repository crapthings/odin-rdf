package ntriples

import "core:testing"
import rdf ".."

@(private) collect :: proc(triple: rdf.Triple, data: rawptr) -> bool {
	triples := cast(^[dynamic]rdf.Triple)data
	append(triples, triple)
	return true
}

@(private) ignore :: proc(_: rdf.Triple, _: rawptr) -> bool { return true }

@(test)
test_parse_core_terms :: proc(t: ^testing.T) {
	input := `<urn:s> <urn:p> <urn:o> .
_:alice <urn:name> "Δημήτρης"@el .
<urn:s> <urn:age> "18"^^<http://www.w3.org/2001/XMLSchema#integer> .`
	triples := make([dynamic]rdf.Triple)
	defer delete(triples)
	err := parse(input, collect, &triples)
	testing.expect_value(t, err.code, Error_Code.None)
	testing.expect_value(t, len(triples), 3)
	if len(triples) == 3 {
		testing.expect_value(t, triples[1].object.value, "Δημήτρης")
		testing.expect_value(t, triples[1].object.language, "el")
		testing.expect_value(t, triples[1].object.datatype, rdf.RDF_LANG_STRING)
		testing.expect_value(t, triples[2].object.datatype, "http://www.w3.org/2001/XMLSchema#integer")
	}
}

@(test)
test_literal_constructor_invariants :: proc(t: ^testing.T) {
	simple := rdf.literal("value")
	testing.expect_value(t, simple.language, "")
	testing.expect_value(t, simple.datatype, rdf.XSD_STRING)

	language := rdf.language_literal("colour", "en-GB")
	testing.expect_value(t, language.language, "en-GB")
	testing.expect_value(t, language.datatype, rdf.RDF_LANG_STRING)

	typed := rdf.typed_literal("42", "http://www.w3.org/2001/XMLSchema#integer")
	testing.expect_value(t, typed.language, "")
	testing.expect_value(t, typed.datatype, "http://www.w3.org/2001/XMLSchema#integer")
}

@(private) Escape_State :: struct { calls: int, valid: bool }

@(private) check_escapes :: proc(triple: rdf.Triple, data: rawptr) -> bool {
	state := cast(^Escape_State)data
	state.calls += 1
	state.valid = triple.subject.value == "urn:snowman:☃" &&
		triple.object.value == "line\nquote\" slash\\ tab\t ☃ 😀"
	return true
}

@(test)
test_decode_escapes_during_callback :: proc(t: ^testing.T) {
	state: Escape_State
	err := parse(`<urn:snowman:\u2603> <urn:p> "line\nquote\" slash\\ tab\t \u2603 \U0001F600" .`, check_escapes, &state)
	testing.expect_value(t, err.code, Error_Code.None)
	testing.expect_value(t, state.calls, 1)
	testing.expect(t, state.valid)
}

@(test)
test_comments_blank_lines_and_line_endings :: proc(t: ^testing.T) {
	input := "# header\r\n\r<urn:s>\t<urn:p>\t<urn:o>. # tail\n\n"
	count := 0
	count_sink := proc(_: rdf.Triple, data: rawptr) -> bool {
		(cast(^int)data)^ += 1
		return true
	}
	err := parse(input, count_sink, &count)
	testing.expect_value(t, err.code, Error_Code.None)
	testing.expect_value(t, count, 1)
}

@(test)
test_stop_is_not_parse_failure :: proc(t: ^testing.T) {
	stop := proc(_: rdf.Triple, _: rawptr) -> bool { return false }
	err := parse(`<urn:s> <urn:p> <urn:o> .`, stop)
	testing.expect_value(t, err.code, Error_Code.Stopped)
}

@(private) Invalid_Case :: struct { input: string, code: Error_Code }

@(test)
test_reject_invalid_inputs :: proc(t: ^testing.T) {
	cases := []Invalid_Case{
		{`<urn:s> <urn:p> <urn:o>`, .Expected_Dot},
		{`<s> <urn:p> <urn:o> .`, .Invalid_IRI},
		{`"literal" <urn:p> <urn:o> .`, .Expected_Term},
		{`<urn:s> <urn:p> "x"@1bad .`, .Invalid_Language_Tag},
		{`<urn:s> <urn:p> "x"@en- .`, .Invalid_Language_Tag},
		{`<urn:s> <urn:p> "\q" .`, .Invalid_Escape},
		{`<urn:s> <urn:p> "\uD800" .`, .Invalid_Unicode_Escape},
		{`<urn:s> <urn:p> "\U00110000" .`, .Invalid_Unicode_Escape},
		{`<urn:s> <urn:p> _:bad. .`, .Trailing_Data},
		{`<urn:s> <urn:p> <urn:o> . junk`, .Trailing_Data},
	}
	for item in cases {
		err := parse(item.input, ignore)
		testing.expect_value(t, err.code, item.code)
	}
}

@(test)
test_unicode_escape_cannot_cross_physical_line :: proc(t: ^testing.T) {
	err := parse("<urn:\\u26\r03> <urn:p> <urn:o> .", ignore)
	testing.expect_value(t, err.code, Error_Code.Unexpected_End)
	testing.expect_value(t, err.column, 6)
}

@(test)
test_reject_invalid_utf8 :: proc(t: ^testing.T) {
	bytes := []byte{'<','u','r','n',':','s','>',' ','<','u','r','n',':','p','>',' ','"',0xff,'"',' ','.'}
	err := parse(string(bytes), ignore)
	testing.expect_value(t, err.code, Error_Code.Invalid_UTF8)
}

@(test)
test_reject_nil_sink :: proc(t: ^testing.T) {
	err := parse(`<urn:s> <urn:p> <urn:o> .`, nil)
	testing.expect_value(t, err.code, Error_Code.Missing_Sink)
}

@(test)
test_blank_node_grammar :: proc(t: ^testing.T) {
	valid := []string{
		`_:0 <urn:p> <urn:o> .`,
		`_:a.b <urn:p> <urn:o> .`,
		`_:café <urn:p> <urn:o> .`,
		`<urn:s> <urn:p> _:node.`,
	}
	for input in valid {
		err := parse(input, ignore)
		testing.expect_value(t, err.code, Error_Code.None)
	}
	invalid := []string{
		`_:-bad <urn:p> <urn:o> .`,
		`_:.bad <urn:p> <urn:o> .`,
	}
	for input in invalid {
		err := parse(input, ignore)
		testing.expect_value(t, err.code, Error_Code.Invalid_Blank_Node)
	}
}

@(private) Scope_State :: struct {
	first:  rdf.Blank_Node_Scope,
	second: rdf.Blank_Node_Scope,
	calls:  int,
}

@(private) scope_sink :: proc(triple: rdf.Triple, data: rawptr) -> bool {
	state := cast(^Scope_State)data
	if state.calls == 0 {
		state.first = triple.subject.scope
	} else {
		state.second = triple.subject.scope
	}
	state.calls += 1
	return true
}

@(test)
test_blank_node_scope_is_document_local :: proc(t: ^testing.T) {
	input := "_:same <urn:p> <urn:o> .\n_:same <urn:p> <urn:o> ."
	within: Scope_State
	err := parse(input, scope_sink, &within)
	testing.expect_value(t, err.code, Error_Code.None)
	testing.expect(t, within.first != rdf.Blank_Node_Scope(0))
	testing.expect_value(t, within.first, within.second)

	separate: Scope_State
	err = parse(`_:same <urn:p> <urn:o> .`, scope_sink, &separate)
	testing.expect_value(t, err.code, Error_Code.None)
	testing.expect(t, separate.first != within.first)
}

@(test)
test_parse_error_messages_are_stable :: proc(t: ^testing.T) {
	messages := [Error_Code]string{
		.None                   = "no error",
		.Unexpected_End         = "unexpected end of input",
		.Expected_Term          = "expected RDF term",
		.Expected_IRI           = "expected IRI",
		.Expected_Dot           = "expected terminating dot",
		.Trailing_Data          = "unexpected data after triple",
		.Invalid_UTF8           = "invalid UTF-8",
		.Invalid_IRI            = "invalid absolute IRI",
		.Invalid_Escape         = "invalid escape sequence",
		.Invalid_Unicode_Escape = "invalid Unicode escape",
		.Invalid_Blank_Node     = "invalid blank-node label",
		.Invalid_Language_Tag   = "invalid language tag",
		.Missing_Sink           = "sink is required",
		.Invalid_Chunk_Size     = "chunk size must not be negative",
		.Invalid_Line_Limit     = "line limit must not be negative",
		.Line_Too_Long          = "line exceeds configured limit",
		.Triple_Limit           = "triple limit reached",
		.Reader_Error           = "reader error",
		.No_Progress            = "reader made no progress",
		.Stopped                = "stopped by sink",
	}
	for code in Error_Code {
		testing.expect_value(t, parse_error_message(code), messages[code])
	}
}
