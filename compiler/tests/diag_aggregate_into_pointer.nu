// diag_aggregate_into_pointer.nu — a struct VALUE bound to a binding
// declared as a POINTER to that struct.
//
// Found by the token-deletion sweep (seed 14, `mut_pointer.nu`), and the
// mutation is one character: `# *Node x` minus its star is `# Node x`,
// which is a legal cast producing a `%Node` VALUE. The binding still
// says `*Node`, so the store was
//
//     store %Node* %r1, %Node** %r2      ; %r1 is a %Node
//
// clang: "'%r1' defined with type '%Node = type { i64, i64 }' but
// expected 'ptr'" — exit 0 from nurlc, and generated IR with no NURL
// location as the only report.
//
// The binding's never-legal-mix battery has six clauses and this fell
// through every one: `csv_int_ptr` knows only INTEGERS into a pointer,
// `csv_named` requires NEITHER side to be a pointer, the pointer-into-
// non-pointer clause runs the other direction, and the aggregate clauses
// all want a scalar or aggregate TARGET. It is the exact mirror of the
// String-vs-raw-C-string clause added the round before, which existed
// because every other clause wanted one side not to be a pointer.
//
// All three aggregate shapes reached it — a named struct or enum, an
// anonymous option/result, and a slice — so the clause asks about the
// shape, not about the name.
: Node { i a i b }

@ main → i {
    : *Node p # Node 0
    ^ 0
}
