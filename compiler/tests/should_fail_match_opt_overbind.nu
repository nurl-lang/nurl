// should_fail_match_opt_overbind.nu — an Option/Result `??` arm may bind at
// most one payload (the T-arm value / Ok payload, or the F-arm error). Binding
// more (`T a b`) used to emit an out-of-range `extractvalue { i1, T } v, 2`
// that only clang/llvm-as rejected. (Enums already validate per-variant
// payload arity; this closes the opt/res case.)
@ main → i { : ?i o @ ?i { T 5 }  ^ ?? o { T a b → a  F → 0 } }
