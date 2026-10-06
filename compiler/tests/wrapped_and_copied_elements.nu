// wrapped_and_copied_elements.nu — options / results in struct fields and
// Vec elements are dropped and copied with their payloads, and the Vec
// copy functions copy what the elements own.
//
// Before, in turn:
//   - an option or result held in a struct field or a Vec element never
//     released its payload (only a `:` binding of one did, through its
//     `%__opt.<T>` twin): every `S { ?String a … }` leaked the String;
//   - `vec_clone`, `vec_extend` and `vec_extend_range` copied elements
//     bitwise, so a Vec of Strings or owning structs was released twice
//     (vec_clone of a Vec of owning structs crashed outright).
// Each round must leave the live allocation count where it found it.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

unsafe @ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

: Pt { String name ( Vec i ) xs }

: Holder { ? Pt p ! String i r i n }

@ mkpt s name → Pt {
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs ( nurl_str_len name ) )
    ^ @ Pt { ( string_from name ) xs }
}

@ names → ( Vec String ) {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `ada` ) )
    ( vec_push [String] v ( string_from `grace` ) )
    ^ v
}

@ round → i {
    : ~ i acc 0
    // Option payloads as Vec elements, present and absent.
    : ( Vec ? Pt ) opts ( vec_new [? Pt] )
    ( vec_push [? Pt] opts @ ?Pt { T ( mkpt `one` ) } )
    ( vec_push [? Pt] opts @ ?Pt { F # Pt 0 } )
    = acc + acc ( vec_len [? Pt] opts )
    // An option and a result as struct fields, copied into another owner.
    : Holder h @ Holder { @ ?Pt { T ( mkpt `four` ) } @ !String i { T ( string_from `ok` ) } 3 }
    : ( Vec Holder ) hs ( vec_new [Holder] )
    ( vec_push [Holder] hs h )
    ( vec_push [Holder] hs @ Holder { @ ?Pt { F # Pt 0 } @ !String i { F 7 } 4 } )
    : ( Vec Holder ) hs2 ( vec_clone [Holder] hs )
    ?? ( vec_get [Holder] hs2 0 ) {
        T x → { ?? . x p { T pt → { = acc + acc ( string_len . pt name ) } F → {} } }
        F → {}
    }
    // Copies of owned elements: clone, extend, a range; and a move.
    : ( Vec String ) v ( names )
    : ( Vec String ) c ( vec_clone [String] v )
    : ( Vec String ) d ( vec_new [String] )
    ( vec_extend [String] d v )
    ( vec_extend_range [String] d c 1 1 )
    ( vec_append [String] d ( names ) )
    = acc + acc ( vec_len [String] d )
    : ( Vec Pt ) ps ( vec_new [Pt] )
    ( vec_push [Pt] ps ( mkpt `xy` ) )
    : ( Vec Pt ) ps2 ( vec_clone [Pt] ps )
    = acc + acc ( vec_len [Pt] ps2 )
    ^ acc
}

@ main → i {
    : i first ( round )
    : i l0 ( live )
    : ~ i k 0
    ~ < k 30 { ( round ) = k + k 1 }
    : i l1 ( live )
    // 2 options + "four" (4) + 2 + 1 + 2 Strings + 1 Pt
    ( nurl_println ( nurl_str_cat `sum ` ( nurl_str_int first ) ) )
    ( nurl_println ? == l0 l1 `live allocations: steady` ( nurl_str_cat `live allocations grew by ` ( nurl_str_int - l1 l0 ) ) )
    ^ 0
}
