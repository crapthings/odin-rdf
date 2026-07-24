package rdf

// DateTime_Data_Value retains the XML Schema dateTime properties needed for
// data-value identity. In particular, an explicit timezone offset is retained
// instead of normalizing to an instant: xsd:dateTime equality and OWL RL
// dt-eq/dt-diff intentionally have different semantics here.
@(private) DateTime_Data_Value :: struct {
	year_negative: bool,
	year:          string,
	month, day:    int,
	hour, minute:  int,
	second:        int,
	fraction:      string,
	utc_offset:    int,
	has_timezone:  bool,
}

// owl_rl_datetime_literals_have_same_value compares valid xsd:dateTime and
// xsd:dateTimeStamp literals by XML Schema data-value identity. Values with
// distinct timezone offsets remain distinct even when they identify the same
// instant.
owl_rl_datetime_literals_have_same_value :: proc(left, right: Term) -> (compared, same: bool) {
	if owl_rl_datetime_literal_status(left) != .Valid || owl_rl_datetime_literal_status(right) != .Valid do return false, false
	left_value, left_ok := parse_owl_rl_datetime_data_value(left.value)
	right_value, right_ok := parse_owl_rl_datetime_data_value(right.value)
	if !left_ok || !right_ok do return false, false
	if left_value.has_timezone != right_value.has_timezone || left_value.utc_offset != right_value.utc_offset do return true, false
	left_shift := 0
	right_shift := 0
	left_hour := left_value.hour
	right_hour := right_value.hour
	if left_hour == 24 { left_hour = 0; left_shift = 1 }
	if right_hour == 24 { right_hour = 0; right_shift = 1 }
	if !datetime_date_shift_equals(left_value, left_shift, right_value, right_shift) do return true, false
	if left_hour != right_hour || left_value.minute != right_value.minute || left_value.second != right_value.second do return true, false
	return true, datetime_fraction_equal(left_value.fraction, right_value.fraction)
}

@(private) parse_owl_rl_datetime_data_value :: proc(value: string) -> (DateTime_Data_Value, bool) {
	if !is_xsd_datetime_lexical(value, false) do return {}, false
	index := 0
	negative := false
	if value[index] == '-' { negative = true; index += 1 }
	year_start := index
	for is_ascii_digit(value[index]) do index += 1
	year := trim_leading_zeroes(value[year_start:index])
	index += 1 // '-'
	month, _ := parse_fixed_digits(value, &index, 2)
	index += 1 // '-'
	day, _ := parse_fixed_digits(value, &index, 2)
	index += 1 // 'T'
	hour, _ := parse_fixed_digits(value, &index, 2)
	index += 1 // ':'
	minute, _ := parse_fixed_digits(value, &index, 2)
	index += 1 // ':'
	second, _ := parse_fixed_digits(value, &index, 2)
	fraction := ""
	if index < len(value) && value[index] == '.' {
		index += 1
		fraction_start := index
		for index < len(value) && is_ascii_digit(value[index]) do index += 1
		fraction = value[fraction_start:index]
	}
	result := DateTime_Data_Value{year_negative = negative, year = year, month = month, day = day, hour = hour, minute = minute, second = second, fraction = fraction}
	if index == len(value) do return result, true
	if value[index] == 'Z' { result.has_timezone = true; return result, index+1 == len(value) }
	sign := value[index]
	if sign != '+' && sign != '-' do return {}, false
	index += 1
	offset_hour, hour_ok := parse_fixed_digits(value, &index, 2)
	if !hour_ok || index == len(value) || value[index] != ':' do return {}, false
	index += 1
	offset_minute, minute_ok := parse_fixed_digits(value, &index, 2)
	if !minute_ok || index != len(value) do return {}, false
	result.utc_offset = offset_hour*60 + offset_minute
	if sign == '-' do result.utc_offset = -result.utc_offset
	result.has_timezone = true
	return result, true
}

@(private) datetime_date_shift_equals :: proc(left: DateTime_Data_Value, left_shift: int, right: DateTime_Data_Value, right_shift: int) -> bool {
	shift := left_shift-right_shift
	if shift == 0 do return datetime_base_date_equal(left, right)
	if shift > 0 do return datetime_shifted_date_equals(left, shift, right)
	return datetime_shifted_date_equals(right, -shift, left)
}

@(private) datetime_shifted_date_equals :: proc(source: DateTime_Data_Value, days: int, target: DateTime_Data_Value) -> bool {
	month, day := source.month, source.day
	year_steps := 0
	days_remaining := days
	for days_remaining > 0 {
		if day < days_in_month(month, is_gregorian_leap_year(source.year)) {
			day += 1
		} else if month < 12 {
			month += 1
			day = 1
		} else {
			month = 1
			day = 1
			year_steps += 1
		}
		days_remaining -= 1
	}
	if month != target.month || day != target.day do return false
	if year_steps == 0 do return datetime_year_equal(source.year_negative, source.year, target.year_negative, target.year)
	if year_steps == 1 do return datetime_year_successor(source.year_negative, source.year, target.year_negative, target.year)
	return false
}

@(private) datetime_base_date_equal :: proc(left, right: DateTime_Data_Value) -> bool {
	return left.month == right.month && left.day == right.day && datetime_year_equal(left.year_negative, left.year, right.year_negative, right.year)
}

@(private) datetime_year_equal :: proc(left_negative: bool, left: string, right_negative: bool, right: string) -> bool {
	return left_negative == right_negative && left == right
}

@(private) datetime_year_successor :: proc(source_negative: bool, source: string, target_negative: bool, target: string) -> bool {
	if !source_negative do return !target_negative && datetime_unsigned_increment_equals(source, target)
	if source == "1" do return !target_negative && target == "1"
	return target_negative && datetime_unsigned_decrement_equals(source, target)
}

@(private) datetime_unsigned_increment_equals :: proc(source, target: string) -> bool {
	all_nines := true
	for byte in source { if byte != '9' { all_nines = false; break } }
	if all_nines {
		if len(target) != len(source)+1 || target[0] != '1' do return false
		for index := 1; index < len(target); index += 1 { if target[index] != '0' do return false }
		return true
	}
	if len(source) != len(target) do return false
	carry := 1
	for index := len(source)-1; index >= 0; index -= 1 {
		digit := int(source[index]-'0') + carry
		if digit == 10 { digit = 0; carry = 1 } else { carry = 0 }
		if target[index] != u8('0'+digit) do return false
	}
	return carry == 0
}

@(private) datetime_unsigned_decrement_equals :: proc(source, target: string) -> bool {
	if source == "0" || source == "1" do return false
	borrow := 1
	target_index := len(target)-1
	for source_index := len(source)-1; source_index >= 0; source_index -= 1 {
		digit := int(source[source_index]-'0') - borrow
		if digit < 0 { digit += 10; borrow = 1 } else { borrow = 0 }
		if source_index == 0 && digit == 0 do continue
		if target_index < 0 || target[target_index] != u8('0'+digit) do return false
		target_index -= 1
	}
	return borrow == 0 && target_index < 0
}

@(private) datetime_fraction_equal :: proc(left, right: string) -> bool {
	left_end := len(left)
	for left_end > 0 && left[left_end-1] == '0' do left_end -= 1
	right_end := len(right)
	for right_end > 0 && right[right_end-1] == '0' do right_end -= 1
	width := left_end
	if right_end > width do width = right_end
	for index in 0..<width {
		left_digit := index < left_end ? left[index] : u8('0')
		right_digit := index < right_end ? right[index] : u8('0')
		if left_digit != right_digit do return false
	}
	return true
}
