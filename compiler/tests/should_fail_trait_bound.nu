// should_fail_trait_bound.nu — a generic instantiated at a type that
// does not implement the bound's trait must be a COMPILE FAIL with a
// clear diagnostic (not a cryptic unresolved-call link error).
% Ord i { @ ord_cmp i a i b → i { ^ 0 } }
@ my_max [A: Ord] A x A y → A { ? > ( ord_cmp x y ) 0 { ^ x } { ^ y } }
@ main → i {
    // f has no `% Ord f` impl → bound A: Ord violated.
    ( my_max [f] 1.0 2.0 )
    ^ 0
}
