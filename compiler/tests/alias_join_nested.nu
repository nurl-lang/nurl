// Test: alias provenance must travel THROUGH a join. A `:`/`=`
// statement's value is the pointer just stored into the binding, so an
// arm holding one needs no copy (the binding's own drop owns that
// buffer, and the join publishes "not owned" so nothing would consume a
// copy). That much was already locked; this test covers the NESTED
// shape, where the alias-valued statement is a `?`/`??` that is itself
// the last statement of an enclosing arm.
//
// Before the fix, gen_cond/gen_match cleared the alias channel at the
// join, so the enclosing arm saw a plain tracked i8* and strdup'd it.
// The enclosing join degrades to void — the outer `?` is a statement —
// so that copy had NO consumer and leaked once per execution. In the
// compiler's own gen_match this was 804 orphaned buffers per
// import-heavy compile.
//
// Leak-freedom is observable under LSan (run_san_tests.sh); this golden
// locks compile + run + output, and the ABSENCE of manual frees locks
// single ownership — adding one would double-free under the sanitizer.

$ `stdlib/core/string.nu`

@ pick i n → s {
    : ~ s acc ``
    : ~ i i 0
    ~ < i 2 {
        // Enclosing `?` whose then-arm ENDS in another `?` whose arms
        // are both `=` statements: the inner join is an alias, so the
        // outer arm must not copy it.
        ? > n 0
        { ? > n 1
            { = acc ( nurl_str_cat `big-` `n` ) }
            { = acc ( nurl_str_cat `one-` `n` ) } }
        {}
        = i + i 1
    }
    // Same shape through a `??` join.
    : ?i opt @ ?i { T n }
    ? > n 0
    { ?? opt {
            T v → { = acc ( nurl_str_cat `opt-` `hit` ) }
            F → { = acc ( nurl_str_cat `opt-` `miss` ) }
        } }
    {}
    ^ ( nurl_str_cat acc `` )
}

@ main → i {
    : s a ( pick 2 ) ( nurl_print a ) ( nurl_print `\n` )
    : s b ( pick 1 ) ( nurl_print b ) ( nurl_print `\n` )
    : s c ( pick 0 ) ( nurl_print c ) ( nurl_print `\n` )

    // A join that is NOT all-alias must still copy: the then-arm's value
    // is a tracked binding read (not a `:`/`=` statement), so the phi
    // consumer gets its own buffer and `kept` stays valid afterwards.
    : s kept ( nurl_str_cat `kept-` `value` )
    : s sel ? 1 kept ( nurl_str_cat `other` `` )
    ( nurl_print sel ) ( nurl_print `\n` )
    ( nurl_print kept ) ( nurl_print `\n` )

    ( nurl_print `done\n` )
    ^ 0
}
