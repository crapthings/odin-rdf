package dataset

import "core:testing"
import rdf ".."
import trig "../trig"
import turtle "../turtle"

@(test)
test_collector_owns_transient_parser_terms :: proc(t: ^testing.T) {
	collector: Collector
	testing.expect_value(t, init(&collector), Error_Code.None)
	defer destroy(&collector)

	input := `@prefix ex: <https://example.test/> .
ex:g { ex:s ex:p "value"@en . }`
	err := trig.parse(input, sink, {}, &collector)
	testing.expect_value(t, err.code, trig.Error_Code.None)
	testing.expect_value(t, collector.last_error, Error_Code.None)
	testing.expect_value(t, len(collector.quads), 1)
	if len(collector.quads) == 1 {
		quad := collector.quads[0]
		testing.expect(t, quad.has_graph)
		testing.expect_value(t, quad.subject.value, "https://example.test/s")
		testing.expect_value(t, quad.object.value, "value")
		testing.expect_value(t, quad.object.language, "en")
		testing.expect_value(t, quad.graph.value, "https://example.test/g")
	}
}

@(test)
test_collector_limit_stops_parser_without_partial_record :: proc(t: ^testing.T) {
	collector: Collector
	testing.expect_value(t, init(&collector, Options{max_quads = 1}), Error_Code.None)
	defer destroy(&collector)
	err := trig.parse(`<urn:s> <urn:p> <urn:a> . <urn:s> <urn:p> <urn:b> .`, sink, {}, &collector)
	testing.expect_value(t, err.code, trig.Error_Code.Stopped)
	testing.expect_value(t, collector.last_error, Error_Code.Quad_Limit)
	testing.expect_value(t, len(collector.quads), 1)
	if len(collector.quads) == 1 do testing.expect_value(t, collector.quads[0].object.value, "urn:a")
}

@(test)
test_collector_adapts_graph_parser_to_default_graph :: proc(t: ^testing.T) {
	collector: Collector
	testing.expect_value(t, init(&collector), Error_Code.None)
	defer destroy(&collector)
	err := turtle.parse(`<urn:s> <urn:p> <urn:o> .`, triple_sink, {}, &collector)
	testing.expect_value(t, err.code, turtle.Error_Code.None)
	testing.expect_value(t, len(collector.quads), 1)
	if len(collector.quads) == 1 do testing.expect(t, !collector.quads[0].has_graph)
}

@(test)
test_collector_rejects_invalid_quads_atomically :: proc(t: ^testing.T) {
	collector: Collector
	testing.expect_value(t, init(&collector), Error_Code.None)
	defer destroy(&collector)
	invalid := rdf.Quad{
		subject = rdf.literal("not allowed"),
		predicate = rdf.iri("urn:p"),
		object = rdf.literal("value"),
	}
	testing.expect_value(t, add(&collector, invalid), Error_Code.Invalid_Quad)
	testing.expect_value(t, len(collector.quads), 0)
	testing.expect_value(t, len(collector.owned), 0)
}

@(test)
test_collector_reports_option_and_message_coverage :: proc(t: ^testing.T) {
	collector: Collector
	testing.expect_value(t, init(&collector, Options{max_quads = -1}), Error_Code.Invalid_Option)
	for code in Error_Code do testing.expect(t, error_message(code) != "unknown error")
}
