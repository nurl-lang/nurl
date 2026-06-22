// result_payload_unsigned.nu — the Ok/T arm of a `?? ` over a Result `! T E`
// must bind its payload with T's signedness, exactly as the Option `? T` arm
// already did. The match bound the Result payload by LLVM type only, so a
// `! u64 E` payload was treated as SIGNED: `% v 10` emitted `srem`, `# i v`
// sign-extended, comparisons used `icmp s*`. (Option `? u64` was already
// correct; only Result regressed.)
@ pr s l i v → v { ( nurl_print l ) ( nurl_print `=` ) ( nurl_print ( nurl_str_int v ) ) ( nurl_print `\n` ) }

@ prb s l b v → v { ( nurl_print l ) ( nurl_print `=` ) ( nurl_print ? v `true` `false` ) ( nurl_print `\n` ) }

@ mk_res → !u64 i { ^ @ !u64 i { T 18446744073709551615 } }  // all-ones
@ mk_opt → ?u64 { ^ @ ?u64 { T 18446744073709551615 } }

@ main → i {
    // bound Result
    : !u64 i r ( mk_res )
    ?? r { T v → {
            ( pr `res_mod10` # i % v 10 )  // 5  (urem, not srem -> -1)
            ( prb `res_gt` > v 1000 )  // true (unsigned)
        } F e → {} }

    // direct-call Result
    ?? ( mk_res ) { T v → ( pr `res_direct_mod10` # i % v 10 ) F e → {} }  // 5

    // Option still correct (regression guard)
    : ?u64 o ( mk_opt )
    ?? o { T v → ( pr `opt_mod10` # i % v 10 ) F → {} }  // 5
    ^ 0
}
