// lent_bound_join_result_read_after_its_argument_is_reassigned: the result of `: String r ? == k 0 p ( mk )  ^ r` read after the caller gave its argument a new value - the String the result borrowed was released
// D4c (AGORA-995): a binding of a join that lends only the caller's argument hands it back lent, per call, as `^ ? == k 0 p ( mk )` does. Before it the return copied on the runs it lent, and this program was accepted.
// map: §2.5 | A2 | rejected | - | AGORA-995: the result of a bound join over an `in` parameter read after the caller reassigned its argument
$ `stdlib/core/string.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

@ pick String p i k → String {
    : String r ? == k 0 p ( mk )
    ^ r
}

@ main → i {
    : ~ String s ( mk )
    : String r ( pick s 0 )
    = s ( mk )
    ( nurl_println ( string_data r ) )
    ^ 0
}
