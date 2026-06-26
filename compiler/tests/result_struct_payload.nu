// result_struct_payload.nu — a multi-field value struct carried through a
// Result (`! T E`) must round-trip ALL fields, not just field 0.
//
// Regression: the `! T E` payload-store discriminated on "is field 0 a
// pointer?" to choose between storing f0 inline vs heap-boxing the struct.
// A multi-field struct whose f0 is a pointer (e.g. `{ s raw i a i b … }`,
// like net.nu's TcpListener) wrongly took the f0-inline path, so fields
// 1.. were dropped and read back as garbage / field 0's value. The fix
// keys on field COUNT (== 1) instead. Option already round-tripped these.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | E { Bad }
// f0 is a pointer (s), but there are more fields — the tricky case.
: Rec { s raw i a i b i c i d i e }

@ mk_res → !Rec E {
    : s rp # s 777
    ^ @ !Rec E { T @ Rec { rp 11 22 33 44 55 } }
}

@ mk_opt → ?Rec {
    : s rp # s 777
    ^ @ ?Rec { T @ Rec { rp 11 22 33 44 55 } }
}

@ __show s tag Rec g → i {
    : b ok & & & & == # i . g raw 777 == . g a 11 == . g b 22 == . g c 33 == . g e 55
    ( nurl_print tag )
    ( nurl_print ? ok `: PASS\n` `: FAIL\n` )
    ^ ? ok 0 1
}

@ main → i {
    : ~ i fails 0
    ?? ( mk_res ) { T g → { = fails + fails ( __show `result` g ) } F _ → { = fails + fails 1 } }
    ?? ( mk_opt ) { T g → { = fails + fails ( __show `option` g ) } F _ → { = fails + fails 1 } }
    ( nurl_print ? == fails 0 `ALL PASS\n` `SOME FAILED\n` )
    ^ 0
}
