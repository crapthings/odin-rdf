package turtle

import "core:testing"
import rdf ".."

collect :: proc(triple: rdf.Triple, data: rawptr) -> bool {
	append(cast(^[dynamic]rdf.Triple)data, triple)
	return true
}

@(test)
test_parse_directives_abbreviations_and_relative_iris :: proc(t: ^testing.T) {
	input := `@base <http://example.com/root/> .
@prefix ex: <vocab/> .
<#alice> a ex:Person ; ex:name "Alice", "A" .`
	triples := make([dynamic]rdf.Triple)
	defer delete(triples)
	err := parse(input, collect, {}, &triples)
	testing.expect_value(t, err.code, Error_Code.None)
	testing.expect_value(t, len(triples), 3)
	if len(triples) == 3 {
		testing.expect_value(t, triples[0].subject.value, "http://example.com/root/#alice")
		testing.expect_value(t, triples[0].predicate.value, RDF_TYPE)
		testing.expect_value(t, triples[0].object.value, "http://example.com/root/vocab/Person")
		testing.expect_value(t, triples[1].object.value, "Alice")
	}
}

@(test)
test_parse_sparql_directives_and_default_prefix :: proc(t: ^testing.T) {
	input := `BASE <http://example.com/base/>
PREFIX : <v/>
:s :p <o> .`
	triples := make([dynamic]rdf.Triple)
	defer delete(triples)
	err := parse(input, collect, {}, &triples)
	testing.expect_value(t, err.code, Error_Code.None)
	testing.expect_value(t, len(triples), 1)
	if len(triples) == 1 {
		testing.expect_value(t, triples[0].subject.value, "http://example.com/base/v/s")
		testing.expect_value(t, triples[0].object.value, "http://example.com/base/o")
	}
}

@(test)
test_statement_is_not_emitted_before_terminating_dot :: proc(t: ^testing.T) {
	triples := make([dynamic]rdf.Triple)
	defer delete(triples)
	err := parse(`<urn:s> <urn:p> <urn:o>`, collect, {}, &triples)
	testing.expect_value(t, err.code, Error_Code.Expected_Dot)
	testing.expect_value(t, len(triples), 0)
}

@(test)
test_relative_iri_requires_base :: proc(t: ^testing.T) {
	err := parse(`<s> <urn:p> <urn:o> .`, proc(_: rdf.Triple, _: rawptr) -> bool { return true })
	testing.expect_value(t, err.code, Error_Code.Missing_Base)
}

@(test)
test_resource_limits_preserve_statement_atomicity :: proc(t: ^testing.T) {
	count := 0
	count_sink := proc(_: rdf.Triple, data: rawptr) -> bool {
		(cast(^int)data)^ += 1
		return true
	}
	pending_err := parse(`<urn:s> <urn:p> <urn:a>, <urn:b> .`, count_sink, Parse_Options{max_pending_triples = 1}, &count)
	testing.expect_value(t, pending_err.code, Error_Code.Pending_Triple_Limit)
	testing.expect_value(t, count, 0)

	triple_err := parse(`<urn:s> <urn:p> <urn:a> . <urn:s> <urn:p> <urn:b>, <urn:c> .`, count_sink, Parse_Options{max_triples = 2}, &count)
	testing.expect_value(t, triple_err.code, Error_Code.Triple_Limit)
	testing.expect_value(t, count, 1)

	token_err := parse(`<urn:s> <urn:p> "four" .`, count_sink, Parse_Options{max_token_bytes = 3}, &count)
	testing.expect_value(t, token_err.code, Error_Code.Token_Limit)
	nesting_err := parse(`<urn:s> <urn:p> ((<urn:o>)) .`, count_sink, Parse_Options{max_nesting_depth = 1}, &count)
	testing.expect_value(t, nesting_err.code, Error_Code.Nesting_Limit)
	prefix_bytes_err := parse(`@prefix : <urn:namespace> .`, count_sink, Parse_Options{max_prefix_bytes = 4}, &count)
	testing.expect_value(t, prefix_bytes_err.code, Error_Code.Prefix_Bytes_Limit)
}

@(test)
test_error_messages_cover_every_public_code :: proc(t: ^testing.T) {
	for code in Error_Code {
		testing.expect(t, parse_error_message(code) != "unknown error")
	}
}
