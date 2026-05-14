// Test: stdlib/std/cmp.nu + stdlib/std/sort.nu
//
// Covers: cmp_int / cmp_str / cmp_string, min/max/clamp scalar +
// generic, sort_by ascending + descending + by-key, sort on empty /
// singleton / pre-sorted Vec, binary_search hit / miss / empty.

$ `stdlib/core/string.nu`
$ `stdlib/std/cmp.nu`
$ `stdlib/std/sort.nu`

@ print_vec_i ( Vec i ) v → v {
    ( nurl_print `[` )
    : i n ( vec_len [i] v )
    : ~ i i 0
    ~ < i n {
        : ?i got ( vec_get [i] v i )
        ?? got {
            T x → { ( nurl_print ( nurl_str_int x ) ) }
            F → {}
        }
        ? < i - n 1 { ( nurl_print `,` ) } {}
        = i + i 1
    }
    ( nurl_print `]\n` )
}

@ print_vec_s ( Vec s ) v → v {
    ( nurl_print `[` )
    : i n ( vec_len [s] v )
    : ~ i i 0
    ~ < i n {
        : ?s got ( vec_get [s] v i )
        ?? got {
            T x → { ( nurl_print x ) }
            F → {}
        }
        ? < i - n 1 { ( nurl_print `,` ) } {}
        = i + i 1
    }
    ( nurl_print `]\n` )
}

@ print_opt_i ? i o s label → v {
    ( nurl_print label )
    ?? o {
        T x → { ( nurl_print `=Some(` ) ( nurl_print ( nurl_str_int x ) ) ( nurl_print `)\n` ) }
        F → { ( nurl_print `=None\n` ) }
    }
}

@ main → i {
    // ── cmp_int / cmp_str ──
    ( nurl_print `cmp_int(3,7)=` ) ( nurl_print ( nurl_str_int ( cmp_int 3 7 ) ) ) ( nurl_print `\n` )
    ( nurl_print `cmp_int(7,3)=` ) ( nurl_print ( nurl_str_int ( cmp_int 7 3 ) ) ) ( nurl_print `\n` )
    ( nurl_print `cmp_int(5,5)=` ) ( nurl_print ( nurl_str_int ( cmp_int 5 5 ) ) ) ( nurl_print `\n` )
    ( nurl_print `cmp_str(ab,ac)=` ) ( nurl_print ( nurl_str_int ( cmp_str `ab` `ac` ) ) ) ( nurl_print `\n` )
    ( nurl_print `cmp_str(ab,ab)=` ) ( nurl_print ( nurl_str_int ( cmp_str `ab` `ab` ) ) ) ( nurl_print `\n` )
    ( nurl_print `cmp_str(ac,ab)=` ) ( nurl_print ( nurl_str_int ( cmp_str `ac` `ab` ) ) ) ( nurl_print `\n` )

    // ── scalar min/max/clamp ──
    ( nurl_print `min_i(3,7)=` ) ( nurl_print ( nurl_str_int ( min_i 3 7 ) ) ) ( nurl_print `\n` )
    ( nurl_print `max_i(3,7)=` ) ( nurl_print ( nurl_str_int ( max_i 3 7 ) ) ) ( nurl_print `\n` )
    ( nurl_print `clamp_i(5,0,10)=` ) ( nurl_print ( nurl_str_int ( clamp_i 5 0 10 ) ) ) ( nurl_print `\n` )
    ( nurl_print `clamp_i(-3,0,10)=` ) ( nurl_print ( nurl_str_int ( clamp_i -3 0 10 ) ) ) ( nurl_print `\n` )
    ( nurl_print `clamp_i(99,0,10)=` ) ( nurl_print ( nurl_str_int ( clamp_i 99 0 10 ) ) ) ( nurl_print `\n` )

    // ── min_by via closure ──
    : ( @ i i i ) c_int \ i a i b → i { ^ ( cmp_int a b ) }
    ( nurl_print `min_by(8,4)=` ) ( nurl_print ( nurl_str_int ( min_by [i] 8 4 c_int ) ) ) ( nurl_print `\n` )
    ( nurl_print `max_by(8,4)=` ) ( nurl_print ( nurl_str_int ( max_by [i] 8 4 c_int ) ) ) ( nurl_print `\n` )
    ( nurl_print `clamp_by(15,0,10)=` ) ( nurl_print ( nurl_str_int ( clamp_by [i] 15 0 10 c_int ) ) ) ( nurl_print `\n` )

    // ── sort_by ascending integers ──
    : ( Vec i ) v1 ( vec_new [i] )
    ( vec_push [i] v1 5 ) ( vec_push [i] v1 1 ) ( vec_push [i] v1 4 )
    ( vec_push [i] v1 2 ) ( vec_push [i] v1 3 ) ( vec_push [i] v1 5 )
    ( vec_push [i] v1 0 )
    ( nurl_print `before=` ) ( print_vec_i v1 )
    ( sort_by [i] v1 c_int )
    ( nurl_print `asc=` ) ( print_vec_i v1 )

    // ── sort_by descending — reverse comparator ──
    : ( Vec i ) v2 ( vec_new [i] )
    ( vec_push [i] v2 5 ) ( vec_push [i] v2 1 ) ( vec_push [i] v2 4 )
    ( vec_push [i] v2 2 ) ( vec_push [i] v2 3 )
    : ( @ i i i ) c_desc \ i a i b → i { ^ ( cmp_int b a ) }
    ( sort_by [i] v2 c_desc )
    ( nurl_print `desc=` ) ( print_vec_i v2 )

    // ── empty + singleton + already-sorted ──
    : ( Vec i ) v_empty ( vec_new [i] )
    ( sort_by [i] v_empty c_int )
    ( nurl_print `empty=` ) ( print_vec_i v_empty )
    ( vec_free [i] v_empty )

    : ( Vec i ) v_one ( vec_new [i] )
    ( vec_push [i] v_one 42 )
    ( sort_by [i] v_one c_int )
    ( nurl_print `singleton=` ) ( print_vec_i v_one )
    ( vec_free [i] v_one )

    : ( Vec i ) v_sorted ( vec_new [i] )
    ( vec_push [i] v_sorted 1 ) ( vec_push [i] v_sorted 2 )
    ( vec_push [i] v_sorted 3 ) ( vec_push [i] v_sorted 4 )
    ( sort_by [i] v_sorted c_int )
    ( nurl_print `presorted=` ) ( print_vec_i v_sorted )
    ( vec_free [i] v_sorted )

    // ── sort_by raw strings — exercises nurl_str_cmp ──
    : ( Vec s ) words ( vec_new [s] )
    ( vec_push [s] words `pear` )
    ( vec_push [s] words `apple` )
    ( vec_push [s] words `cherry` )
    ( vec_push [s] words `banana` )
    : ( @ i s s ) c_str \ s a s b → i { ^ ( cmp_str a b ) }
    ( sort_by [s] words c_str )
    ( nurl_print `words=` ) ( print_vec_s words )
    ( vec_free [s] words )

    // ── sort_by_key style: sort integers by absolute value via custom cmp ──
    : ( Vec i ) v_abs ( vec_new [i] )
    ( vec_push [i] v_abs -3 ) ( vec_push [i] v_abs 1 ) ( vec_push [i] v_abs -7 )
    ( vec_push [i] v_abs 4 ) ( vec_push [i] v_abs -2 )
    : ( @ i i i ) c_abs \ i a i b → i {
        : i aa ? < a 0 - 0 a a
        : i bb ? < b 0 - 0 b b
        ^ ( cmp_int aa bb )
    }
    ( sort_by [i] v_abs c_abs )
    ( nurl_print `byabs=` ) ( print_vec_i v_abs )
    ( vec_free [i] v_abs )

    // ── binary_search on the sorted v1 ──
    ( print_opt_i ( binary_search [i] v1 4 c_int ) `bs(4)` )
    ( print_opt_i ( binary_search [i] v1 0 c_int ) `bs(0)` )
    ( print_opt_i ( binary_search [i] v1 5 c_int ) `bs(5)` )
    ( print_opt_i ( binary_search [i] v1 6 c_int ) `bs(6)` )
    ( print_opt_i ( binary_search [i] v1 -1 c_int ) `bs(-1)` )

    // ── binary_search on empty Vec ──
    : ( Vec i ) v_bs_empty ( vec_new [i] )
    ( print_opt_i ( binary_search [i] v_bs_empty 7 c_int ) `bs_empty(7)` )
    ( vec_free [i] v_bs_empty )

    ( vec_free [i] v1 )
    ( vec_free [i] v2 )

    ( nurl_print `done\n` )
    ^ 0
}
