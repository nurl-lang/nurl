// owned_string_field_assign.nu — a string field its struct owns (the
// struct literal gave it a fresh string) holds an allocator-owned pointer
// on every path, as a string binding that owns its value does: a view, a
// literal or an owned local assigned to it is copied, a fresh value is
// taken, and the value it replaces is freed. A string binding that owns
// its value copies a field it is given; one born from a field owns the
// strings assigned to it after. The struct handed back carries its copy.
// The sanitizer corpus runs this with leak detection (tools/fuzz/holes
// h121–h127).
//
// A raw string field owns a fresh string only in `unsafe` code and the
// trusted library; safe code holds a String there, or a view of a
// binding (docs/MEMORY.md §2.13). The functions that build such structs
// are `unsafe` to keep exercising that machinery.
$ `stdlib/core/string.nu`

: Rec { s name i n }

unsafe @ view_in → i {
    : String t ( string_from `view` )
    : ~ Rec r @ Rec { ( nurl_str_cat `a` `b` ) 1 }
    = . r name ( string_data t )
    ^ ( nurl_str_len . r name )
}

unsafe @ fresh_in → i {
    : ~ Rec r @ Rec { ( nurl_str_cat `a` `b` ) 1 }
    = . r name ( nurl_str_cat `c` `de` )
    = . r name ( nurl_str_cat `f` `ghi` )
    ^ ( nurl_str_len . r name )
}

unsafe @ literal_in → i {
    : ~ Rec r @ Rec { ( nurl_str_cat `a` `b` ) 1 }
    = . r name `lit`
    ^ ( nurl_str_len . r name )
}

unsafe @ local_in → i {
    : ~ Rec r @ Rec { ( nurl_str_cat `a` `b` ) 1 }
    : s x ( nurl_str_cat `x` `yz` )
    = . r name x
    = . r name . r name
    ^ ( nurl_str_len . r name )
}

unsafe @ handed_back → Rec {
    : String t ( string_from `kept` )
    : ~ Rec r @ Rec { ( nurl_str_cat `a` `b` ) 1 }
    = . r name ( string_data t )
    ^ r
}

@ field_into_binding → i {
    : Rec r @ Rec { `abc` 1 }
    : ~ s p ``
    = p . r name
    ^ ( nurl_str_len p )
}

@ field_born_binding → i {
    : Rec r @ Rec { `abc` 1 }
    : ~ s p . r name
    : ~ i k 0
    ~ < k 3 {
        = p ( nurl_str_cat `x` ( nurl_str_int k ) )
        = k + k 1
    }
    ^ ( nurl_str_len p )
}

@ main → i {
    ( nurl_print_int ( view_in ) ) ( nurl_print ` ` ) ( nurl_print_int ( fresh_in ) ) ( nurl_print ` ` )
    ( nurl_print_int ( literal_in ) ) ( nurl_print ` ` ) ( nurl_print_int ( local_in ) ) ( nurl_print `\n` )
    : Rec q ( handed_back )
    ( nurl_print . q name ) ( nurl_print `\n` )
    ( nurl_print_int ( field_into_binding ) ) ( nurl_print ` ` ) ( nurl_print_int ( field_born_binding ) ) ( nurl_print `\n` )
    ^ 0
}
