// drop_impl_semantics.nu — what a `% Drop` impl owns, and who runs it.
//
// A destructor releases what only it knows about (a raw buffer here); the
// fields the language manages — String, Vec, library handles, values with
// their own `% Drop` — are dropped after it, as a Rust Drop's fields are
// (drop glue). Every shape below runs for several rounds and must leave
// the live allocation count where it found it. Before, in turn:
//   - a `% Drop` type used as a Vec element or a struct field had its impl
//     replaced by a generated field-by-field drop of the same name, so the
//     program's destructor never ran (anywhere in the program);
//   - a struct holding a `% Drop` value was not dropped at all;
//   - a raw string field of a `% Drop` type was released by the compiler
//     AND by the impl (a double free), and a nested one produced invalid IR;
//   - fields the impl did not release by hand leaked.
//
// A raw string field owns a fresh string only in `unsafe` code and the
// trusted library; safe code holds a String there, or a view of a
// binding (docs/MEMORY.md §2.13). The functions that build such structs
// are `unsafe` to keep exercising that machinery.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

unsafe @ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

: ~ i g_dropped 0

// Releases only its raw field; `d` and `t` are the glue's.
: Raw { s name ( Vec i ) d String t }

% Drop Raw { unsafe @ drop Raw r → v { ( nurl_free . r name ) = g_dropped + g_dropped 1 } }

// Releases a managed field by hand too: the glue must skip it.
: ByHand { s name ( Vec i ) d }

% Drop ByHand { unsafe @ drop ByHand r → v { ( nurl_free . r name ) ( vec_free [i] . r d ) = g_dropped + g_dropped 1 } }

// Hands itself to a disposer, which releases everything.
: Disposed { s name ( Vec i ) d }

unsafe @ disposed_free sink Disposed r → v { ( nurl_free . r name ) ( vec_free [i] . r d ) }

% Drop Disposed { @ drop Disposed r → v { = g_dropped + g_dropped 1 ( disposed_free r ) } }

// Structs that hold a `% Drop` value, directly and one level down.
: Holder { Raw r i n }
: Outer { Holder h ( Vec i ) extra }

unsafe @ raw_new i k → Raw {
    : s n ( nurl_str_cat `raw-` ( nurl_str_int k ) )
    ^ @ Raw { n ( vec_new [i] ) ( string_from `t` ) }
}

unsafe @ by_hand_new → ByHand { : s n ( nurl_str_cat `a` `b` ) ^ @ ByHand { n ( vec_new [i] ) } }

unsafe @ disposed_new → Disposed { : s n ( nurl_str_cat `a` `b` ) ^ @ Disposed { n ( vec_new [i] ) } }

@ holder_new → Holder { ^ @ Holder { ( raw_new 7 ) 1 } }

@ name_len Raw r → i { ^ ( nurl_str_len . r name ) }

@ round → i {
    : ~ i acc 0
    : Raw a ( raw_new 1 )
    = acc + acc ( name_len a )
    : ( Vec Raw ) v ( vec_new [Raw] )
    ( vec_push [Raw] v ( raw_new 2 ) )
    ( vec_push [Raw] v a )
    = acc + acc ( vec_len [Raw] v )
    : ByHand b ( by_hand_new )
    : Disposed d ( disposed_new )
    : Holder h ( holder_new )
    = acc + acc . h n
    : Outer o @ Outer { @ Holder { ( raw_new 3 ) 2 } ( vec_new [i] ) }
    = acc + acc . . o h n
    ^ acc
}

@ main → i {
    : i r1 ( round )
    : i l1 ( live )
    : i d1 g_dropped
    : i r2 ( round )
    : i r3 ( round )
    : i l3 ( live )
    ( puts ( nurl_str_int r1 ) )
    ( puts ( nurl_str_int + r2 r3 ) )
    ( puts ( nurl_str_cat `destructors per round: ` ( nurl_str_int d1 ) ) )
    ? == l1 l3 { ( puts `live allocations: steady` ) } { ( puts ( nurl_str_cat `live allocations grew by ` ( nurl_str_int - l3 l1 ) ) ) }
    ^ 0
}
