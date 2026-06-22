// enum_f32_payload.nu — an enum variant with an `f32` payload must round-trip.
// Construction picked the slot width from the VALUE's type, but a float literal
// is always `double`, so `@ N { F32 2.25 }` bitcast the whole double to i64
// while the match arm (emit_enum_float_extract) read the LOW 32 bits back as a
// float — a silent miscompile that returned 0. Construction now picks f32-vs-f
// from the variant's DECLARED payload type and fptrunc's the literal to float.
@ prf s l f v → v { ( nurl_print l ) ( nurl_print `=` ) ( nurl_print ( float_to_string v ) ) ( nurl_print `\n` ) }

$ `stdlib/std/float.nu`

: | NumA { F32 f32 }
: | NumB { F64 f }
: | P { Two f32 f32 Mix i f32 }  // f32 at payload index 0 and 1

@ main → i {
    : NumA a @ NumA { F32 2.25 }
    ?? a { F32 q → ( prf `f32_single` # f q ) }  // 2.25

    : NumB b @ NumB { F64 3.5 }
    ?? b { F64 q → ( prf `f64_single` q ) }  // 3.5  (regression guard)

    : P p @ P { Two 1.25 2.75 }
    ?? p { Two x y → { ( prf `two_x` # f x ) ( prf `two_y` # f y ) } Mix _ _ → {} }  // 1.25 / 2.75

    : P m @ P { Mix 7 9.5 }
    ?? m { Mix n z → ( prf `mix_z` # f z ) Two _ _ → {} }  // 9.5  (f32 at index 1, int at 0)
    ^ 0
}
