// result_err_arm_unsigned.nu — the Err arm (`F e`) of a `?? ` over `! T E` binds
// the ERROR payload E and must carry E's signedness, just as the Ok arm binds T
// (fixed earlier). An `! T u64` error treated `e` as SIGNED: `% e 10` emitted
// `srem`, `# i e` sign-extended, etc.
@ pr s l i v → v { ( nurl_print l ) ( nurl_print `=` ) ( nurl_print ( nurl_str_int v ) ) ( nurl_print `\n` ) }

@ mk_err → !i u64 { ^ @ !i u64 { F 18446744073709551615 } }  // Err(all-ones)
@ mk_ok → !u64 i { ^ @ !u64 i { T 18446744073709551615 } }  // Ok(all-ones)

@ main → i {
    // Err arm, unsigned E (bound + direct)
    : !i u64 r ( mk_err )
    ?? r { T v → {} F e → ( pr `err_mod10` # i % e 10 ) }  // 5
    ?? ( mk_err ) { T v → {} F e → ( pr `err_direct_mod10` # i % e 10 ) }  // 5
    ?? r { T v → {} F e → ( pr `err_gt` ? > e 1000 1 0 ) }  // 1 (unsigned)

    // Ok arm, unsigned T (regression guard for #211)
    : !u64 i k ( mk_ok )
    ?? k { T v → ( pr `ok_mod10` # i % v 10 ) F e → {} }  // 5
    ^ 0
}
