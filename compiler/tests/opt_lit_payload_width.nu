// Regression: constructing an option/result whose payload is a SIZED
// integer, from an integer LITERAL (or any wider-typed value), must
// coerce the value to the payload field's width.
//
// Bug (discovered 2026-05-31): `@ ?u { T 0x86 }` emitted
//   insertvalue { i1, i8 } %r1, i64 134, 1
// — an i64 value into the i8 field. clang rejected it ("operand and
// field disagree in type"). gen_agg_lit's opt/res payload coercion only
// folded i8*/i1/enum/struct/double values to the i64 slot used by
// `! T E`; an OPTION `? T` payload carries T's real width (i8/i16/i32),
// so an i64 literal fell through to the "use as-is" branch untouched.
//
// Fix: gen_agg_lit now coerces between integer widths — trunc when the
// value is wider than the payload field, sext/zext (per the value's
// unsigned flag) when narrower.
//
// Deterministic output so it is baselined.

@ main → i {
    : ?u a @ ?u { T 0x86 }
    ?? a { T b → ( nurl_print ( nurl_str_int # i b ) ) F → ( nurl_print `-` ) }
    ( nurl_print ` ` )
    : ?u16 c @ ?u16 { T 0x1234 }
    ?? c { T b → ( nurl_print ( nurl_str_int # i b ) ) F → ( nurl_print `-` ) }
    ( nurl_print ` ` )
    : ?i32 d @ ?i32 { T -5 }
    ?? d { T b → ( nurl_print ( nurl_str_int # i b ) ) F → ( nurl_print `-` ) }
    ( nurl_print `\n` )
    // Result payload slot is always i64 — a sized-int value widens into it.
    : !u s r @ !u s { T 0x86 }
    ?? r { T b → ( nurl_print ( nurl_str_int # i b ) ) F e → ( nurl_print e ) }
    ( nurl_print `\n` )
    ^ 0
}
