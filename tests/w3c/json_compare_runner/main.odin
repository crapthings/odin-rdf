// json_compare_runner compares two JSON documents as parsed JSON values.
// W3C JSON-LD Expansion expectations use object comparison, not byte-for-byte
// source comparison; number spellings such as 4.50 and 4.5 therefore compare
// as the same JSON number after parsing.
package main

import "core:fmt"
import json "core:encoding/json"
import "core:os"

json_values_equal :: proc(left, right: json.Value) -> bool {
	#partial switch left_value in left {
	case json.Null:
		_, matches := right.(json.Null)
		return matches
	case json.Boolean:
		right_value, matches := right.(json.Boolean)
		return matches && bool(left_value) == bool(right_value)
	case json.String:
		right_value, matches := right.(json.String)
		return matches && string(left_value) == string(right_value)
	case json.Integer:
		#partial switch right_value in right {
		case json.Integer:
			return i64(left_value) == i64(right_value)
		case json.Float:
			return f64(left_value) == f64(right_value)
		}
		return false
	case json.Float:
		#partial switch right_value in right {
		case json.Integer:
			return f64(left_value) == f64(right_value)
		case json.Float:
			return f64(left_value) == f64(right_value)
		}
		return false
	case json.Array:
		right_value, matches := right.(json.Array)
		if !matches || len(left_value) != len(right_value) do return false
		for item, index in left_value {
			if !json_values_equal(item, right_value[index]) do return false
		}
		return true
	case json.Object:
		right_value, matches := right.(json.Object)
		if !matches || len(left_value) != len(right_value) do return false
		for key, item in left_value {
			right_item, found := right_value[key]
			if !found || !json_values_equal(item, right_item) do return false
		}
		return true
	}
	return false
}

json_top_level_arrays_equal_unordered :: proc(left, right: json.Value) -> bool {
	left_values, left_is_array := left.(json.Array)
	right_values, right_is_array := right.(json.Array)
	if !left_is_array || !right_is_array do return json_values_equal(left, right)
	if len(left_values) != len(right_values) do return false
	matched := make([]bool, len(right_values))
	defer delete(matched)
	for left_value in left_values {
		found := false
		for right_value, index in right_values {
			if matched[index] || !json_values_equal(left_value, right_value) do continue
			matched[index] = true
			found = true
			break
		}
		if !found do return false
	}
	return true
}

main :: proc() {
	if len(os.args) < 3 || len(os.args) > 4 {
		fmt.eprintln("usage: json_compare_runner <expected.json> <actual.json> [--unordered-top-level-array]")
		os.exit(2)
	}
	expected_data, expected_read_error := os.read_entire_file(os.args[1], context.allocator)
	if expected_read_error != nil {
		fmt.eprintf("cannot read expected JSON %s: %v\n", os.args[1], expected_read_error)
		os.exit(2)
	}
	defer delete(expected_data)
	actual_data, actual_read_error := os.read_entire_file(os.args[2], context.allocator)
	if actual_read_error != nil {
		fmt.eprintf("cannot read actual JSON %s: %v\n", os.args[2], actual_read_error)
		os.exit(2)
	}
	defer delete(actual_data)
	expected, expected_error := json.parse_string(string(expected_data), .JSON, true)
	if expected_error != .None {
		fmt.eprintf("expected JSON is invalid: %v\n", expected_error)
		os.exit(2)
	}
	defer json.destroy_value(expected)
	actual, actual_error := json.parse_string(string(actual_data), .JSON, true)
	if actual_error != .None {
		fmt.eprintf("actual JSON is invalid: %v\n", actual_error)
		os.exit(1)
	}
	defer json.destroy_value(actual)
	unordered_top_level_array := len(os.args) == 4 && os.args[3] == "--unordered-top-level-array"
	if len(os.args) == 4 && !unordered_top_level_array {
		fmt.eprintf("unknown comparison option: %s\n", os.args[3])
		os.exit(2)
	}
	if unordered_top_level_array ? !json_top_level_arrays_equal_unordered(expected, actual) : !json_values_equal(expected, actual) {
		fmt.eprintln("parsed JSON values differ")
		os.exit(1)
	}
}
