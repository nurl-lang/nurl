// f32_store_widening.nu — float↔double width adjustment at STORES, the
// exact mirror of the integer widths that have coerced since 2026-05-14.
// Before this, `: f a ( f32-returning-call )` fell through every branch of
// coerce_store_val (the never-valid-mix check fires only when exactly ONE
// side is a float), so nurlc emitted `store double %float_val` — invalid
// IR accepted by nurlc (rc 0) and rejected only by clang, with no source
// location. Found live by nurllama's finetune diagnostics
// (`: f x ( bits_to_f32 b )`).
//
// Covers: widen at let (call result, f32 var, cast chain), narrow at let
// (double literal into f32), widen and narrow at `=` reassignment.

@ f32ret → f32 { ^ # f32 1.5 }

@ pr s l f v → v {
    ( nurl_print l )
    ( nurl_print `=` )
    ( nurl_print ( nurl_str_float v ) )
    ( nurl_print `\n` )
}

@ main → i {
    : f a ( f32ret )  // f32 call result → f slot (fpext)
    ( pr `call_widen` a )
    : f32 s # f32 2.5
    : f b s  // f32 var → f slot
    ( pr `var_widen` b )
    : f c # f # f32 3.25  // explicit chain: double → float → double
    ( pr `cast_chain` c )
    : f32 g 1.25  // double literal → f32 slot (fptrunc)
    ( pr `lit_narrow` # f g )
    : ~ f32 d # f32 0.0
    = d a  // f value → f32 slot at reassignment
    ( pr `assign_narrow` # f d )
    : ~ f e 0.0
    = e s  // f32 value → f slot at reassignment
    ( pr `assign_widen` e )
    ^ 0
}
