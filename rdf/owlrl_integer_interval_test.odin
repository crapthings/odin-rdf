package rdf

import "core:testing"

@(test)
test_owl_rl_integer_datatype_intersection_subset :: proc(t: ^testing.T) {
	short := "http://www.w3.org/2001/XMLSchema#short"
	unsigned_integer32 := "http://www.w3.org/2001/XMLSchema#unsignedInt"
	unsigned_short := "http://www.w3.org/2001/XMLSchema#unsignedShort"
	unsigned_byte := "http://www.w3.org/2001/XMLSchema#unsignedByte"
	non_negative := "http://www.w3.org/2001/XMLSchema#nonNegativeInteger"
	non_positive := "http://www.w3.org/2001/XMLSchema#nonPositiveInteger"
	byte := "http://www.w3.org/2001/XMLSchema#byte"
	positive := "http://www.w3.org/2001/XMLSchema#positiveInteger"
	negative := "http://www.w3.org/2001/XMLSchema#negativeInteger"

	testing.expect(t, owl_rl_integer_datatype_intersection_is_subset_of(short, unsigned_integer32, unsigned_short))
	testing.expect(t, !owl_rl_integer_datatype_intersection_is_subset_of(short, unsigned_integer32, unsigned_byte))
	testing.expect(t, owl_rl_integer_datatype_intersection_is_subset_of(non_negative, non_positive, short))
	testing.expect(t, owl_rl_integer_datatype_intersection_is_subset_of(non_negative, non_positive, byte))
	// Empty intersections are intentionally not promoted: a bounded range
	// supplement must not use vacuous containment to create arbitrary ranges.
	testing.expect(t, !owl_rl_integer_datatype_intersection_is_subset_of(positive, negative, short))
	testing.expect(t, !owl_rl_integer_datatype_intersection_is_subset_of("http://www.w3.org/2001/XMLSchema#decimal", short, unsigned_short))
}
