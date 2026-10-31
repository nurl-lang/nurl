// option_kept_by_vec_push_then_read_after_the_vec: an option of a String pushed into a Vec (`( vec_push [?String] out o
// )`), the Vec released, then the option read: a String or a struct in the
// same place is "stored in 'out'", but the store row was emitted only for
// handle types, and an option's is none.
// Closed: a value that needs a drop kept by a callee is stored in the
// container it is handed with — gen_call's `pendkeep` row for every such
// type (agora #149).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.12 | A2 | rejected | h421 | an option of a String pushed into a Vec, the Vec freed, the option read (UAF); the store row covers every value that needs a drop
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

@ main → i {
    : ( Vec ? String ) out ( vec_new [? String] )
    : ?String o @ ?String { T ( mk ) }
    ( vec_push [? String] out o )
    ( vec_free [? String] out )
    ?? o { T x → { ( nurl_println ( string_data x ) ) } F → {} }
    ^ 0
}
