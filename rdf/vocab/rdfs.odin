// RDFS core vocabulary. This is an IRI inventory only; it does not implement
// RDFS entailment or schema axioms.
package vocab

RDFS_NAMESPACE :: "http://www.w3.org/2000/01/rdf-schema#"

// RDFS model classes.
RDFS_RESOURCE :: RDFS_NAMESPACE + "Resource"
RDFS_CLASS    :: RDFS_NAMESPACE + "Class"
RDFS_LITERAL  :: RDFS_NAMESPACE + "Literal"
RDFS_DATATYPE :: RDFS_NAMESPACE + "Datatype"

// RDFS semantic properties.
RDFS_DOMAIN          :: RDFS_NAMESPACE + "domain"
RDFS_RANGE           :: RDFS_NAMESPACE + "range"
RDFS_SUB_CLASS_OF    :: RDFS_NAMESPACE + "subClassOf"
RDFS_SUB_PROPERTY_OF :: RDFS_NAMESPACE + "subPropertyOf"

// RDFS documentation and definition links.
RDFS_LABEL         :: RDFS_NAMESPACE + "label"
RDFS_COMMENT       :: RDFS_NAMESPACE + "comment"
RDFS_SEE_ALSO      :: RDFS_NAMESPACE + "seeAlso"
RDFS_IS_DEFINED_BY :: RDFS_NAMESPACE + "isDefinedBy"
