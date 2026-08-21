// Casting a raw pointer to a struct whose first field is NOT a pointer
// has no honest lowering — there is no slot the address could fill.
// This used to fall through gen_cast's branch chain with no conversion
// emitted at all: the .ll handed a ptr to a struct-typed use and clang
// rejected the module with `%rN defined with type ptr but expected
// %Pair`, an error the user met far from the cast that caused it. It
// must be a COMPILE error here, at the cast, in the compiler's words.
// (The handle-wrapper shape — field 0 IS a pointer, e.g. ( Vec u ) —
// stays legal: cast_ptr_struct_roundtrip covers that half.)

: Pair { i a i b }

@ main → i {
    : s p ( nurl_alloc 16 )
    : Pair w # Pair p
    ( nurl_free p )
    ^ . w a
}
