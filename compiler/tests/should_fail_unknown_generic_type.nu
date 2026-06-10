// should_fail_unknown_generic_type.nu — critic A7, unsized-generic
// half. `( Vec i )` with no vec.nu import has no generic struct
// template to materialise `%Vec__i64` from; the reference stayed an
// opaque unsized type and clang rejected with "loading unsized types
// is not allowed" — far from the real cause. Now a hard error at the
// type's use site naming the missing import.
: | E { Nil  V ( Vec i ) }
@ main → i {
    : E e @ E { Nil }
    ?? e {
        V w → { ( nurl_print `vec\n` ) }
        Nil → { ( nurl_print `nil\n` ) }
    }
    ^ 0
}
