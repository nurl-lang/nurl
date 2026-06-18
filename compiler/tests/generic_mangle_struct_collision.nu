// generic_mangle_struct_collision.nu — a NAMED struct whose bare name equals a
// builtin / compound mangle slug (`str`, `f64`, `ptr_*`, …) must NOT share a
// generic monomorphisation with the builtin type.
//
// Regression for a silent, layout-corrupting miscompile: `mangle_type` lowered
// the string type `s` (LLVM `i8*`) to the slug `str`, and a struct literally
// named `str` (LLVM `%str`) to the SAME slug `str` (it just stripped the `%`).
// `str`, `f64`, `i1`, `i64`, `void` are all LEGAL struct names (not lexer
// reserved), and a struct may start with `opt_` / `ptr_`. The monomorphiser
// dedupes by slug, so `( Box str )` silently reused `( Box s )`'s monomorph —
// `box_size [str]` returned 8 (sizeof Box<i8*>) instead of 24. No diagnostic,
// valid IR, wrong answer at runtime. `mangle_type` is now injective over LLVM
// type strings (colliding named-struct slugs are escaped `S__<name>`).
: str { i a  i b  i c }          // 24-byte struct; collided with s (i8*)

: Box [T] { T val }
@ box_size [T] → i { ^ Z ( Box T ) }
@ box_make [T] T v → ( Box T ) { ^ @ ( Box T ) { v } }
@ box_get  [T] ( Box T ) bx → T { ^ . bx val }

@ main → i {
    // sizeof must reflect the ACTUAL element type, not whichever instantiation
    // was emitted first.
    ( nurl_print ( nurl_str_int ( box_size [s]   ) ) ) ( nurl_print `\n` )   // 8
    ( nurl_print ( nurl_str_int ( box_size [str] ) ) ) ( nurl_print `\n` )   // 24

    // The struct-typed Box must round-trip its real fields (would read garbage
    // through the 8-byte i8* layout under the old collision).
    : str three @ str { 11 22 33 }
    : ( Box str ) tb ( box_make [str] three )
    : str got ( box_get [str] tb )
    ( nurl_print ( nurl_str_int + + . got a . got b . got c ) ) ( nurl_print `\n` )  // 66

    // The string-typed Box still works alongside it.
    : ( Box s ) sb ( box_make [s] `hi` )
    ( nurl_print ( box_get [s] sb ) ) ( nurl_print `\n` )                    // hi
    ^ 0
}
