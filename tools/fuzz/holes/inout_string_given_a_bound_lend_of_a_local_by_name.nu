// inout_string_given_a_bound_lend_of_a_local_by_name: agora #456 — `: String l ( make2 )  : String t ( id l )  = o t`
// Closed: an `inout` String or Vec given, by name, a local that holds a value it does not own (bound as a borrow, or a cursor over another binding) copies it in, as for a borrowed parameter given by name (agora #456).
// main: heap-use-after-free (base 70aaf0c7 too).
// map: §7.6 | A2 | runs-clean | - | agora #456: `: String l ( make2 )  : String t ( id l )  = o t`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ make → String { ^ ( string_from `a fresh string long enough for the heap, one` ) }

@ make2 → String { ^ ( string_from `a fresh string long enough for the heap, two` ) }

@ id String a → String { ^ a }

@ pick String a String b i k → String { ? == k 0 { ^ a } {} ^ b }

@ putl inout String o → v { : String l ( make2 ) : String t ( id l ) = o t }

@ main → i {
    : ~ String a ( make )
    ( putl a )
    ( nurl_println ( string_data a ) )
    ^ 0
}
