// trait_bounds.nu — acceptance test for trait bounds on generic
// functions: `@ f [A: Trait] …`. Dispatch of a trait method inside a
// generic body already resolves to the concrete impl via
// monomorphisation; the bound records the requirement and is verified at
// each instantiation (see should_fail_trait_bound.nu for the negative).
//
// Determinism: pure. ASan-clean.

$ `stdlib/core/string.nu`

% Ord i {
    @ ord_cmp i a i b → i { ? < a b { ^ -1 } {} ? > a b { ^ 1 } {} ^ 0 }
}

% Ord String {
    @ ord_cmp String a String b → i { ^ ( nurl_str_cmp ( string_data a ) ( string_data b ) ) }
}

@ my_max [A : Ord] A x A y → A {
    ? > ( ord_cmp x y ) 0 { ^ x } { ^ y }
}

@ my_min [A : Ord] A x A y → A {
    ? < ( ord_cmp x y ) 0 { ^ x } { ^ y }
}

@ main → i {
    ( nurl_print `max(3,7)=` ) ( nurl_println_int ( my_max [i] 3 7 ) )
    ( nurl_print `min(3,7)=` ) ( nurl_println_int ( my_min [i] 3 7 ) )
    ( nurl_print `max(9,2)=` ) ( nurl_println_int ( my_max [i] 9 2 ) )
    : String a ( string_from `apple` )
    : String b ( string_from `pear` )
    ( nurl_print `max(apple,pear)=` ) ( nurl_print ( string_data ( my_max [String] a b ) ) ) ( nurl_print `\n` )
    ( nurl_print `min(apple,pear)=` ) ( nurl_print ( string_data ( my_min [String] a b ) ) ) ( nurl_print `\n` )
    ( string_free a ) ( string_free b )
    ^ 0
}
