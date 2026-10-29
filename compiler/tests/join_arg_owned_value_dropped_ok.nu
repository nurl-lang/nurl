// join_arg_owned_value_dropped_ok.nu — a `?` / `??` join of owning values
// handed straight to a call is a temporary of that call: dropped after it by
// the phi of its arms' ownership bits, unless the callee keeps, consumes or
// hands it back (agora #174, h690–h695). Each loop below must leave the
// live allocation count where it found it.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

unsafe @ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

: S { String s i pad }

@ mk → String { ^ ( string_from `a string that owns a heap buffer` ) }

@ mkv i n → ( Vec i ) { : ( Vec i ) v ( vec_new [i] ) ( vec_push [i] v n ) ^ v }

@ use S h → i { ^ + ( string_len . h s ) . h pad }

@ pass S h → S { ^ h }

@ keep ( Vec S ) out S h → v { ( vec_push [S] out h ) }

@ main → i {
    : S held @ S { ( mk ) 5 }
    : ( Vec S ) ks ( vec_new [S] )
    : i before ( live )
    : ~ i sum 0
    : ~ i n 0
    ~ < n 8 {
        : b c == 0 % n 2
        = sum + sum ( use ? c @ S { ( mk ) 0 } @ S { ( mk ) 1 } )
        : String a ( mk )
        : String b ( mk )
        = sum + sum ( use ? c @ S { a 2 } @ S { b 3 } )
        = sum + sum ( use ? c held @ S { ( mk ) 4 } )
        = sum + sum ( use ?? ( vec_get [i] ( mkv n ) 0 ) { T x → @ S { ( mk ) x } F _ → @ S { ( mk ) 0 } } )
        : S p ( pass ? c @ S { ( mk ) 6 } @ S { ( mk ) 7 } )
        = sum + sum . p pad
        = n + n 1
    }
    ( nurl_println_int sum )
    ( nurl_println_int - ( live ) before )
    // A keeping callee takes the joined value: it lives in the Vec.
    ( keep ks ? T @ S { ( mk ) 8 } @ S { ( mk ) 9 } )
    ( nurl_println_int ( vec_len [S] ks ) )
    ( nurl_println_int . held pad )
    ^ 0
}
