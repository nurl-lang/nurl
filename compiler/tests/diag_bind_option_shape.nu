// diag_bind_option_shape.nu — binding a '?f' value to a ': ?i'
// declaration. The store between the differently-spelled aggregates
// ('{ i1, double }' into '{ i1, i64 }') was invalid IR that only clang
// saw; the cure is matching shapes or '??' destructuring, not a cast.
@ main → i {
    : ?f a @ ?f { T 1.5 }
    : ?i b a
    ^ 0
}
