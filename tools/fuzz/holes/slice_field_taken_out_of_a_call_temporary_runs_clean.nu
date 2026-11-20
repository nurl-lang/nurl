// slice_field_taken_out_of_a_call_temporary_runs_clean: `( ln . ( mkb ) s )`, `: [i x . ( mkb ) s` and `. . ( mkb ) s length`, a `[i` field read out of a struct a call handed back
// Closed (agora #895): an owned slice owns its buffer, which `__type_needs_drop` does not count: the field read took it for one that owns nothing and released the struct under the slice it handed on (h232). It leaves with the read now, as an owned field does (h266): the rest is released, the slice is the argument's or the binding's own by the read's flag.
// main aae76ca (with github#2103): AddressSanitizer: heap-use-after-free (the argument and the binding read the buffer the struct's release freed).
// map: §7.6 | A2 | runs-clean | - | agora #895: an owned slice field read out of a call's struct result, handed to a call, bound, and read for its length
: Bag { [i s i n }

@ mk → [i { ^ [i | 1 2 3] }
@ mkb → Bag { ^ @ Bag { ( mk ) 3 } }
@ ln [i t → i { : ~ i k 0 ~ x t { = k + k x } ^ k }

@ main → i {
    ( nurl_println_int ( ln . ( mkb ) s ) )
    : [i x . ( mkb ) s
    ( nurl_println_int ( ln x ) )
    ( nurl_println_int . . ( mkb ) s length )
    ^ 0
}
