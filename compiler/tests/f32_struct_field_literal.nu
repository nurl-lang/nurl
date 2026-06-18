// f32_struct_field_literal.nu — an `f32` (LLVM `float`) struct/aggregate field
// initialised from a float LITERAL must be coerced. A float literal is always
// emitted as `double`, and gen_agg_lit only coerced INTEGER field widths — so
// `@ Vec3 { 1.5 2.5 3.5 }` inserted a `double` into a `float` field, which
// nurlc accepted (rc 0) but clang rejected: "insertvalue operand and field
// disagree in type: 'double' instead of 'float'". gen_agg_lit now fptrunc's
// double→float (and fpext's float→double) using the field's declared type.
@ pr s l i v → v { ( nurl_print l ) ( nurl_print `=` ) ( nurl_print ( nurl_str_int v ) ) ( nurl_print `\n` ) }
: Vec3 { f32 x  f32 y  f32 z }
: Mixed { f d  f32 g }

@ main → i {
    : Vec3 v @ Vec3 { 1.5 2.5 4.0 }
    ( pr `x_plus_y` # i + . v x . v y )     // 4   (1.5 + 2.5)
    ( pr `z`        # i . v z )             // 4
    ( pr `dot_ish`  # i + + * . v x . v x * . v y . v y * . v z . v z )  // 2.25+6.25+16 = 24
    : Mixed m @ Mixed { 10.0 7.0 }
    ( pr `d_plus_f` # i + . m d # f . m g )  // 17  (f64 + f32-widened)
    ^ 0
}
