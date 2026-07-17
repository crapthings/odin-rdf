package main

import "core:fmt"

// This intentionally tiny example explains the syntax; it is not a complete RDF parser.
main :: proc() {
	line := `<alice> <knows> <bob> .`
	parts: [3]string
	count := 0
	start := 0
	for i in 0..<len(line) {
		if line[i] == '<' do start = i + 1
		if line[i] == '>' && count < len(parts) {
			parts[count] = line[start:i]
			count += 1
		}
	}
	fmt.println(parts[0], parts[1], parts[2])
}
