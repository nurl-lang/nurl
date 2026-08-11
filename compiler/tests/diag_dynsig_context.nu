// diag_dynsig_context.nu — an error raised while re-parsing a trait
// method's signature for dynamic dispatch used to speak from
// '<dynsig>:1:C' with no trait, method, or file named — the reader had
// nothing to open. The location is still synthetic (the buffer is a
// reconstructed, Self-substituted signature), but the message now
// carries the trait, the method, the Self type, and where the fix
// goes. The '->' here is the classic ASCII-arrow mistake, inside a
// trait method header only the dyn path re-parses.

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
    : %Speaker obj # % Speaker d
    ( nurl_print ( sound obj ) )
    ^ 0
}
