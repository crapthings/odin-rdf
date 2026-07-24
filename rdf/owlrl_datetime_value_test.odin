package rdf

import "core:testing"

@(test)
test_owl_rl_datetime_values_normalize_timezone_day_and_fraction :: proc(t: ^testing.T) {
	date_time := "http://www.w3.org/2001/XMLSchema#dateTime"
	date_time_stamp := "http://www.w3.org/2001/XMLSchema#dateTimeStamp"

	compared, same := owl_rl_datetime_literals_have_same_value(
		typed_literal("2024-01-01T00:00:00Z", date_time_stamp),
		typed_literal("2023-12-31T19:00:00-05:00", date_time),
	)
	testing.expect(t, compared && same)
	compared, same = owl_rl_datetime_literals_have_same_value(
		typed_literal("2024-02-29T24:00:00.0", date_time),
		typed_literal("2024-03-01T00:00:00", date_time),
	)
	testing.expect(t, compared && same)
	compared, same = owl_rl_datetime_literals_have_same_value(
		typed_literal("2025-01-01T00:30:00+01:00", date_time),
		typed_literal("2024-12-31T23:30:00Z", date_time_stamp),
	)
	testing.expect(t, compared && same)
	testing.expect_value(t, owl_rl_literal_value_relation(
		typed_literal("2024-01-01T00:00:01.20Z", date_time),
		typed_literal("2024-01-01T00:00:01.2Z", date_time_stamp),
	), OWL_RL_Literal_Value_Relation.Same)
	testing.expect_value(t, owl_rl_literal_value_relation(
		typed_literal("2024-01-01T00:00:00", date_time),
		typed_literal("2024-01-01T00:00:00Z", date_time),
	), OWL_RL_Literal_Value_Relation.Different)
}
