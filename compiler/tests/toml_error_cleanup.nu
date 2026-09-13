// Malformed-input ownership: all parser payloads and partial ASTs must be
// reclaimed, including failed keys, headers and nested table collisions.
$ `stdlib/ext/toml.nu`

@ malformed s input → b {
    ?? ( toml_parse input ) {
        F _ → ^ T
        T value → {
            ( toml_value_free value )
            ( nurl_eprint `unexpected TOML success: ` ) ( nurl_eprintln input )
            ^ F
        }
    }
}

@ prefixes s text → v {
    : i length ( nurl_str_len text )
    : ~ i count 0
    ~ <= count length {
        : String prefix ( string_with_cap count )
        ( string_push_bytes prefix text count )
        ?? ( toml_parse ( string_data prefix ) ) {
            T value → ( toml_value_free value )
            F _ → {}
        }
        ( string_free prefix )
        = count + count 1
    }
}

@ main → i {
    : ( Vec s ) inputs ( vec_new [s] )
    ( vec_push [s] inputs `[` )
    ( vec_push [s] inputs `[[package` )
    ( vec_push [s] inputs `[[package]` )
    ( vec_push [s] inputs `[one.two.` )
    ( vec_push [s] inputs `[one."unfinished` )
    ( vec_push [s] inputs `[one."bad\\q"]` )
    ( vec_push [s] inputs `=` )
    ( vec_push [s] inputs `"unfinished` )
    ( vec_push [s] inputs `"bad\\q" = 1` )
    ( vec_push [s] inputs `valid_key` )
    ( vec_push [s] inputs `value =` )
    ( vec_push [s] inputs `value = "unfinished` )
    ( vec_push [s] inputs `value = "bad\\q"` )
    ( vec_push [s] inputs `value = unknown` )
    ( vec_push [s] inputs `value = +` )
    ( vec_push [s] inputs `value = 1_` )
    ( vec_push [s] inputs `value = 1.2_` )
    ( vec_push [s] inputs `value = 1e2_` )
    ( vec_push [s] inputs `value = 999999999999999999999999999999999` )
    ( vec_push [s] inputs `value = 1.2e999999999` )
    ( vec_push [s] inputs `value = [` )
    ( vec_push [s] inputs `value = ["kept", "unfinished` )
    ( vec_push [s] inputs `value = ["kept" false]` )
    ( vec_push [s] inputs `value = [{ good = "kept" }, { bad = "unfinished` )
    ( vec_push [s] inputs `value = {` )
    ( vec_push [s] inputs `value = { = 1 }` )
    ( vec_push [s] inputs `value = { "unfinished` )
    ( vec_push [s] inputs `value = { "bad\\q" = 1 }` )
    ( vec_push [s] inputs `value = { key }` )
    ( vec_push [s] inputs `value = { key = }` )
    ( vec_push [s] inputs `value = { good = ["kept"], bad = [ }` )
    ( vec_push [s] inputs `value = { key = "kept" false }` )
    ( vec_push [s] inputs `a = 1\n[[a]]\nx = "detached"` )
    ( vec_push [s] inputs `a = "scalar"\n[a.nested]\nx = "wrong scope"` )
    ( vec_push [s] inputs `a = []\n[[a]]` )
    ( vec_push [s] inputs `a = [1]\n[[a]]` )
    ( vec_push [s] inputs `a = []\n[a.nested]` )
    ( vec_push [s] inputs `a = [1]\n[a.nested]` )
    ( vec_push [s] inputs `[a]\nx = 1\n[[a]]` )
    : ~ i failures 0
    : ~ i index 0
    ~ < index ( vec_len [s] inputs ) {
        ? ! ( malformed . ( vec_data [s] inputs ) index ) { = failures + failures 1 } {}
        = index + index 1
    }
    ( vec_free [s] inputs )
    ( prefixes `[package]\nname = "prefix\\\" value"\nvalues = ["one", { nested = [1,2,3] }]\n[[other]]\nname = "ok"\n` )
    ( prefixes `[one.two."quoted section"]\nkey = { first = true, second = 1.25e-3 }\n` )
    // Valid descent through an array of tables remains rooted in its latest
    // element, including when a later malformed header tears the AST down.
    ( prefixes `[[a]]\nname = "first"\n[a.child]\nvalue = "nested"\n[[a]]\nname = "second"\n` )
    ( nurl_println ? == failures 0 `TOML error cleanup: ok` `TOML error cleanup: FAIL` )
    ^ ? == failures 0 0 1
}
