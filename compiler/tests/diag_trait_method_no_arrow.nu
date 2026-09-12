// diag_trait_method_no_arrow.nu — a trait method header with no return
// arrow, in the spelling that produces it: the ASCII '->'.
//
// Every other function header requires the arrow. A plain `@ f i o { … }`
// and an IMPL method both say "expected a type, found '{'"; a TRAIT
// method header did not. The scan recorded a signature with no return
// type and nothing read it back unless the trait was used as a `dyn`
// object — a use the program may never make, so `% Sh [T] { @ area T o
// i }` simply compiled.
//
// It was reported, when it was reported at all, from the `<dynsig>`
// re-parse: a synthetic location, decorated with the trait and method
// names because it had no file to name. The declaration is where a
// declaration's mistakes belong, and this one now anchors on the method
// name in the real source. The impl-signature check dropped the skip it
// carried for exactly this case ("a header with no arrow is not a
// signature at all") in the same change.

% Speaker [T] {
    @ sound T self - > s
}

: Dog {
    i x
}

% Speaker Dog {
    @ sound Dog self → s {
        ^ `woof`
    }
}

@ main → i {
    : Dog d @ Dog { 1 }
    ^ . d x
}
