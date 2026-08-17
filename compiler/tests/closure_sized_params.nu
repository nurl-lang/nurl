// closure_sized_params.nu — a closure whose PARAMETERS are sized /
// unsigned types.
//
// Both places that print a closure's parameter types printed them RAW,
// straight out of the internal `param_types` list, while every other
// type in the IR goes through `nurl_llty`. For `i`/`f`/handles the two
// spellings coincide, so the hole stayed invisible; for a byte
// parameter they do not, and the compiler emitted
//
//     define i1 @__closure_7(i8* %__env, u8 %a, u8 %b)
//     %r23 = insertvalue { i1(i8*, i8, i8)*, i8* } undef,
//            i1(i8*, u8, u8)* @__closure_7, 0
//
// — `u8` is not an LLVM type, and the value's type disagreed with the
// struct's. nurlc exited 0 and clang rejected the file. Surfaced by
// `( vec_eq [u] a b \ u x u y → b { ^ == x y } )`, the obvious way to
// compare two byte vectors.

$ `stdlib/core/vec.nu`

@ main → i {
    // The shape that found it: a byte-vector comparison.
    : ( Vec u ) a ( vec_new [u] )
    : ( Vec u ) b ( vec_new [u] )
    : ( Vec u ) c ( vec_new [u] )
    : ~ i k 0
    ~ < k 4 {
        ( vec_push [u] a # u + 250 k )  // 250..253: high bit set
        ( vec_push [u] b # u + 250 k )
        ( vec_push [u] c # u + 251 k )
        = k + k 1
    }
    ( nurl_print `eq_same=` )
    ( nurl_print ? ( vec_eq [u] a b \ u x u y → b { ^ == x y } ) `T` `F` )
    ( nurl_print `\n` )
    ( nurl_print `eq_diff=` )
    ( nurl_print ? ( vec_eq [u] a c \ u x u y → b { ^ == x y } ) `T` `F` )
    ( nurl_print `\n` )

    // Every sized width, as a directly-called closure value.
    : ( @ i u ) f8 \ u x → i { ^ * # i x 2 }
    ( nurl_print `f8=` ) ( nurl_print ( nurl_str_int ( f8 # u 200 ) ) ) ( nurl_print `\n` )

    : ( @ i u16 u32 ) f1632 \ u16 x u32 y → i { ^ + # i x # i y }
    ( nurl_print `f1632=` )
    ( nurl_print ( nurl_str_int ( f1632 # u16 60000 # u32 4000000000 ) ) )
    ( nurl_print `\n` )

    : ( @ i u64 ) f64 \ u64 x → i { ^ >> # u64 x 1 }
    ( nurl_print `f64=` )
    ( nurl_print ( nurl_str_int ( f64 # u64 0xF000000000000000 ) ) )
    ( nurl_print `\n` )

    // A capture alongside a byte parameter: the env pointer and the
    // lowered parameter list have to agree.
    : i bias 7
    : ( @ i u ) fcap \ u x → i { ^ + # i x bias }
    ( nurl_print `fcap=` ) ( nurl_print ( nurl_str_int ( fcap # u 255 ) ) ) ( nurl_print `\n` )

    ( vec_free [u] a ) ( vec_free [u] b ) ( vec_free [u] c )
    ^ 0
}
