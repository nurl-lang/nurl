// H117: a callee that may hand its argument back as is, given an owned local; its result bound and handed back — on that path the result is the local, which the function drops on the way out.
$ `stdlib/core/string.nu`

@ clone_or_lend s v i flag → s {
    ? == flag 1 { ^ ( nurl_str_cat v `` ) } {}
    ^ v
}

@ dup_it s a i flag → s {
    : s v ( nurl_str_cat a `x` )
    : s r ( clone_or_lend v flag )
    ^ r
}

@ main → i {
    : s q ( dup_it `cd` 0 )
    ( nurl_print q ) ( nurl_print `\n` )
    ^ 0
}
