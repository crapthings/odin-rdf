package rdf

import "core:testing"

@(test)
test_owl_rl_datetime_literal_status :: proc(t: ^testing.T) {
	date_time := "http://www.w3.org/2001/XMLSchema#dateTime"
	date_time_stamp := "http://www.w3.org/2001/XMLSchema#dateTimeStamp"
	testing.expect_value(t, owl_rl_datetime_literal_status(typed_literal("2024-02-29T24:00:00Z", date_time)), OWL_RL_DateTime_Status.Valid)
	testing.expect_value(t, owl_rl_datetime_literal_status(typed_literal("-12024-02-29T23:59:59.1+14:00", date_time_stamp)), OWL_RL_DateTime_Status.Valid)
	testing.expect_value(t, owl_rl_datetime_literal_status(typed_literal("2023-02-29T12:00:00", date_time)), OWL_RL_DateTime_Status.Not_In_Value_Space)
	testing.expect_value(t, owl_rl_datetime_literal_status(typed_literal("00001-01-01T00:00:00", date_time)), OWL_RL_DateTime_Status.Not_In_Value_Space)
	testing.expect_value(t, owl_rl_datetime_literal_status(typed_literal("2024-01-01T24:00:01", date_time)), OWL_RL_DateTime_Status.Not_In_Value_Space)
	testing.expect_value(t, owl_rl_datetime_literal_status(typed_literal("2024-01-01T00:00:60", date_time)), OWL_RL_DateTime_Status.Not_In_Value_Space)
	testing.expect_value(t, owl_rl_datetime_literal_status(typed_literal("2024-01-01T00:00:00+14:01", date_time)), OWL_RL_DateTime_Status.Not_In_Value_Space)
	testing.expect_value(t, owl_rl_datetime_literal_status(typed_literal("2024-01-01T00:00:00", date_time_stamp)), OWL_RL_DateTime_Status.Not_In_Value_Space)
}
