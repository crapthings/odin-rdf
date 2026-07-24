package rdf

// OWL_RL_DATATYPE_IRIS is the complete W3C OWL 2 RL supported datatype set.
//
// The registry deliberately contains datatype resources only; it does not
// validate lexical forms or compare literal values.  Consumers implementing
// OWL RL dt-type2, dt-eq, dt-diff, or dt-not-type must use this exact set as
// their scope, then apply the appropriate value-space semantics.
OWL_RL_DATATYPE_IRIS :: [32]string{
	"http://www.w3.org/1999/02/22-rdf-syntax-ns#PlainLiteral",
	"http://www.w3.org/1999/02/22-rdf-syntax-ns#XMLLiteral",
	"http://www.w3.org/2000/01/rdf-schema#Literal",
	"http://www.w3.org/2001/XMLSchema#decimal",
	"http://www.w3.org/2001/XMLSchema#integer",
	"http://www.w3.org/2001/XMLSchema#nonNegativeInteger",
	"http://www.w3.org/2001/XMLSchema#nonPositiveInteger",
	"http://www.w3.org/2001/XMLSchema#positiveInteger",
	"http://www.w3.org/2001/XMLSchema#negativeInteger",
	"http://www.w3.org/2001/XMLSchema#long",
	"http://www.w3.org/2001/XMLSchema#int",
	"http://www.w3.org/2001/XMLSchema#short",
	"http://www.w3.org/2001/XMLSchema#byte",
	"http://www.w3.org/2001/XMLSchema#unsignedLong",
	"http://www.w3.org/2001/XMLSchema#unsignedInt",
	"http://www.w3.org/2001/XMLSchema#unsignedShort",
	"http://www.w3.org/2001/XMLSchema#unsignedByte",
	"http://www.w3.org/2001/XMLSchema#float",
	"http://www.w3.org/2001/XMLSchema#double",
	"http://www.w3.org/2001/XMLSchema#string",
	"http://www.w3.org/2001/XMLSchema#normalizedString",
	"http://www.w3.org/2001/XMLSchema#token",
	"http://www.w3.org/2001/XMLSchema#language",
	"http://www.w3.org/2001/XMLSchema#Name",
	"http://www.w3.org/2001/XMLSchema#NCName",
	"http://www.w3.org/2001/XMLSchema#NMTOKEN",
	"http://www.w3.org/2001/XMLSchema#boolean",
	"http://www.w3.org/2001/XMLSchema#hexBinary",
	"http://www.w3.org/2001/XMLSchema#base64Binary",
	"http://www.w3.org/2001/XMLSchema#anyURI",
	"http://www.w3.org/2001/XMLSchema#dateTime",
	"http://www.w3.org/2001/XMLSchema#dateTimeStamp",
}

// is_owl_rl_datatype reports whether iri is one of the datatype resources
// supported by the OWL 2 RL/RDF rules datatype table.
is_owl_rl_datatype :: proc(iri: string) -> bool {
	for datatype_iri in OWL_RL_DATATYPE_IRIS {
		if iri == datatype_iri do return true
	}
	return false
}
