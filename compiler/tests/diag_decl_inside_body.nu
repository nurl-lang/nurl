// diag_decl_inside_body.nu — a function declaration swallowed into the
// previous function's body by a missing '}'. The parser reads the
// header's '@ name' as a struct-literal opener and used to die with
// "expected '{' but found 'b'" — blaming a missing operand on the
// wrong line entirely (263 of the probe's drop-close-brace mutants
// cascaded from exactly this misdiagnosis). The '→'-before-'{' probe
// now names the real cause: the unclosed brace above.

@ outer i n → i {
    ? > n 0 {
        ^ n

        @ inner b flag s name → v {
            ( nurl_print name )
        }

        @ main → i {
            ^ ( outer 3 )
        }
