// should_fail_stdlib_helper_no_import.nu — a pure-NURL stdlib helper
// (nurl_str_cat / _cat3 / _cat4 / _slice) used WITHOUT importing its module
// must be diagnosed at the call site.
//
// These are pre-registered in init_syms for cross-module typing but have no
// C body (unlike nurl_str_int / _float / read_*), so with no `$` import of
// stdlib/core/string.nu the symbol is undefined at link. The frontend now
// names the missing import instead of leaking clang's
// "use of undefined value '@nurl_str_cat'".

@ main → i {
    ( nurl_print ( nurl_str_cat `a` `b` ) )
    ^ 0
}
