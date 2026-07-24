package rdf

// OWL_RL_DateTime_Status describes XML Schema dateTime/dateTimeStamp lexical
// and calendar value-space validation.
OWL_RL_DateTime_Status :: enum {
	Not_DateTime_Datatype,
	Not_In_Value_Space,
	Valid,
}

// owl_rl_datetime_literal_status validates the XML Schema dateTime grammar,
// including arbitrary-width years, Gregorian calendar days, the 24:00:00
// boundary, and the ±14:00 timezone limit. dateTimeStamp additionally
// requires an explicit timezone.
owl_rl_datetime_literal_status :: proc(literal: Term) -> OWL_RL_DateTime_Status {
	if literal.kind != .Literal do return .Not_DateTime_Datatype
	require_timezone := false
	switch literal.datatype {
	case "http://www.w3.org/2001/XMLSchema#dateTime":
	case "http://www.w3.org/2001/XMLSchema#dateTimeStamp":
		require_timezone = true
	case:
		return .Not_DateTime_Datatype
	}
	if is_xsd_datetime_lexical(literal.value, require_timezone) do return .Valid
	return .Not_In_Value_Space
}

@(private) is_xsd_datetime_lexical :: proc(value: string, require_timezone: bool) -> bool {
	index := 0
	if index < len(value) && value[index] == '-' do index += 1
	year_start := index
	for index < len(value) && is_ascii_digit(value[index]) do index += 1
	if index-year_start < 4 || index == len(value) || value[index] != '-' do return false
	if all_ascii_zeroes(value[year_start:index]) do return false
	index += 1

	month, month_ok := parse_fixed_digits(value, &index, 2)
	if !month_ok || index == len(value) || value[index] != '-' do return false
	index += 1
	day, day_ok := parse_fixed_digits(value, &index, 2)
	if !day_ok || index == len(value) || value[index] != 'T' do return false
	index += 1
	hour, hour_ok := parse_fixed_digits(value, &index, 2)
	if !hour_ok || index == len(value) || value[index] != ':' do return false
	index += 1
	minute, minute_ok := parse_fixed_digits(value, &index, 2)
	if !minute_ok || index == len(value) || value[index] != ':' do return false
	index += 1
	second, second_ok := parse_fixed_digits(value, &index, 2)
	if !second_ok do return false

	fraction_is_zero := true
	if index < len(value) && value[index] == '.' {
		index += 1
		fraction_start := index
		for index < len(value) && is_ascii_digit(value[index]) {
			if value[index] != '0' do fraction_is_zero = false
			index += 1
		}
		if index == fraction_start do return false
	}

	if month < 1 || month > 12 || day < 1 || day > days_in_month(month, is_gregorian_leap_year(value[year_start:index_of_year_end(value, year_start)])) do return false
	if hour > 24 || minute > 59 || second > 60 do return false
	if hour == 24 && (minute != 0 || second != 0 || !fraction_is_zero) do return false

	has_timezone := false
	if index < len(value) {
		switch value[index] {
		case 'Z':
			has_timezone = true
			index += 1
		case '+', '-':
			has_timezone = true
			index += 1
			offset_hour, offset_hour_ok := parse_fixed_digits(value, &index, 2)
			if !offset_hour_ok || index == len(value) || value[index] != ':' do return false
			index += 1
			offset_minute, offset_minute_ok := parse_fixed_digits(value, &index, 2)
			if !offset_minute_ok || offset_hour > 14 || offset_minute > 59 || (offset_hour == 14 && offset_minute != 0) do return false
		case:
			return false
		}
	}
	return index == len(value) && (!require_timezone || has_timezone)
}

@(private) index_of_year_end :: proc(value: string, year_start: int) -> int {
	index := year_start
	for index < len(value) && is_ascii_digit(value[index]) do index += 1
	return index
}

@(private) parse_fixed_digits :: proc(value: string, index: ^int, count: int) -> (number: int, ok: bool) {
	if index^+count > len(value) do return 0, false
	for offset := 0; offset < count; offset += 1 {
		character := value[index^+offset]
		if !is_ascii_digit(character) do return 0, false
		number = number*10 + int(character-'0')
	}
	index^ += count
	return number, true
}

@(private) is_ascii_digit :: proc(character: u8) -> bool {
	return character >= '0' && character <= '9'
}

@(private) all_ascii_zeroes :: proc(value: string) -> bool {
	for character in value {
		if character != '0' do return false
	}
	return true
}

@(private) is_gregorian_leap_year :: proc(year: string) -> bool {
	modulo_400 := 0
	for character in year {
		modulo_400 = (modulo_400*10 + int(character-'0')) % 400
	}
	return modulo_400 % 400 == 0 || (modulo_400 % 4 == 0 && modulo_400 % 100 != 0)
}

@(private) days_in_month :: proc(month: int, leap_year: bool) -> int {
	switch month {
	case 1, 3, 5, 7, 8, 10, 12: return 31
	case 4, 6, 9, 11: return 30
	case 2: return 29 if leap_year else 28
	}
	return 0
}
