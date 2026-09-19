// Regression: std/args.nu CLI parser. Drives an explicit token list
// (so the test is deterministic, independent of real argv) covering:
//   --flag, --opt VALUE, --opt=VALUE, -s, -sVALUE clusters, the `--`
//   terminator, positional collection, and the unknown-option error
//   path. Prints PASS / a FAIL line per failed check and returns the
//   failure count (non-zero exit surfaces in failures.txt).

$ `stdlib/std/args.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ push_tok ( Vec String ) v s lit → v {
    ( vec_push [String] v ( string_from lit ) )
}

// Compare an owned ?String to an expected literal; frees the payload.
@ expect_val ? String got s exp s label → i {
    : ~ i bad 1
    ?? got {
        T s → {
            : String e ( string_from exp )
            ? ( string_eq s e ) { = bad 0 } {}
            ( string_free s )
            ( string_free e )
        }
        F → {}
    }
    ? > bad 0 { ( nurl_print `  FAIL val ` ) ( nurl_print label ) ( nurl_print `\n` ) } {}
    ^ bad
}

@ expect_int i got i want s label → i {
    ? == got want { ^ 0 } {}
    ( nurl_print `  FAIL int ` ) ( nurl_print label )
    ( nurl_print ` got ` ) ( nurl_print ( nurl_str_int got ) )
    ( nurl_print ` want ` ) ( nurl_print ( nurl_str_int want ) )
    ( nurl_print `\n` )
    ^ 1
}

@ main → i {
    : ~ i fails 0

    : ArgParser p ( args_new `demo` `a demo tool` )
    ( args_flag p `verbose` 118 `be loud` )  // -v
    ( args_opt p `output` 111 `FILE` `out path` )  // -o
    ( args_opt p `count` 99 `N` `repeat count` )  // -c
    ( args_flag p `aa` 97 `flag a` )  // -a
    ( args_flag p `bb` 98 `flag b` )  // -b

    : ( Vec String ) toks ( vec_new [String] )
    ( push_tok toks `-v` )
    ( push_tok toks `--output` )
    ( push_tok toks `out.txt` )
    ( push_tok toks `--count=3` )
    ( push_tok toks `-ab` )
    ( push_tok toks `file1` )
    ( push_tok toks `--` )
    ( push_tok toks `--weird` )
    ( push_tok toks `file2` )

    : b ok ( args_parse p toks )
    ? ! ok { ( nurl_print `  FAIL parse returned F\n` ) = fails + fails 1 } {}
    ? ( args_has_error p ) { ( nurl_print `  FAIL unexpected error\n` ) = fails + fails 1 } {}

    = fails + fails ( expect_int ( args_count p `verbose` ) 1 `verbose` )
    = fails + fails ( expect_int ( args_count p `aa` ) 1 `aa` )
    = fails + fails ( expect_int ( args_count p `bb` ) 1 `bb` )
    = fails + fails ( expect_val ( args_value p `output` ) `out.txt` `output` )
    = fails + fails ( expect_val ( args_value p `count` ) `3` `count` )

    = fails + fails ( expect_int ( args_positional_count p ) 3 `npos` )
    : ( Vec String ) pos ( args_positionals p )
    : s p0 ?? ( vec_get [String] pos 0 ) { T s → ( string_data s ) F → `` }
    : s p1 ?? ( vec_get [String] pos 1 ) { T s → ( string_data s ) F → `` }
    : s p2 ?? ( vec_get [String] pos 2 ) { T s → ( string_data s ) F → `` }
    ? != 1 ( nurl_str_eq p0 `file1` ) { ( nurl_print `  FAIL pos0\n` ) = fails + fails 1 } {}
    ? != 1 ( nurl_str_eq p1 `--weird` ) { ( nurl_print `  FAIL pos1\n` ) = fails + fails 1 } {}
    ? != 1 ( nurl_str_eq p2 `file2` ) { ( nurl_print `  FAIL pos2\n` ) = fails + fails 1 } {}

    // value_or falls back to the default for an unset option
    : String mv ( args_value_or p `missing` `dflt` )
    ? != 1 ( nurl_str_eq ( string_data mv ) `dflt` ) { ( nurl_print `  FAIL value_or\n` ) = fails + fails 1 } {}
    ( string_free mv )

    // usage generation must produce non-empty, prog-bearing text
    : String u ( args_usage p )
    ? < ( string_len u ) 10 { ( nurl_print `  FAIL usage too short\n` ) = fails + fails 1 } {}
    ? < ( nurl_str_find ( string_data u ) `--output` ) 0 { ( nurl_print `  FAIL usage missing option\n` ) = fails + fails 1 } {}
    ( string_free u )

    ( vec_free_with [String] toks \ String s → v { ( string_free s ) } )
    ( args_free p )

    // ── glued short value: -ofoo → output == "foo" ──
    : ArgParser p2 ( args_new `demo2` `` )
    ( args_opt p2 `output` 111 `FILE` `out` )
    : ( Vec String ) t2 ( vec_new [String] )
    ( push_tok t2 `-ofoo` )
    : b ok2 ( args_parse p2 t2 )
    ? ! ok2 { ( nurl_print `  FAIL parse2\n` ) = fails + fails 1 } {}
    = fails + fails ( expect_val ( args_value p2 `output` ) `foo` `glued` )
    ( vec_free_with [String] t2 \ String s → v { ( string_free s ) } )
    ( args_free p2 )

    // ── a repeated value option keeps every occurrence ──
    //
    // `args_value` answers with the last one, which is what `--output`
    // wants. An option that MEANS "again" — `--include a --include b` is
    // two filters, not a correction — needs all of them, and before
    // `args_values` the earlier ones were recorded and unreachable.
    : ArgParser p4 ( args_new `demo4` `` )
    ( args_opt p4 `include` 105 `PREFIX` `filter` )
    : ( Vec String ) t4 ( vec_new [String] )
    ( push_tok t4 `--include` )
    ( push_tok t4 `alpha` )
    ( push_tok t4 `--include=beta` )
    ( push_tok t4 `-igamma` )
    : b ok4 ( args_parse p4 t4 )
    ? ! ok4 { ( nurl_print `  FAIL parse4\n` ) = fails + fails 1 } {}
    = fails + fails ( expect_int ( args_count p4 `include` ) 3 `include count` )
    = fails + fails ( expect_val ( args_value p4 `include` ) `gamma` `include last` )
    : ( Vec String ) vals ( args_values p4 `include` )
    = fails + fails ( expect_int ( vec_len [String] vals ) 3 `include values` )
    : s v0 ?? ( vec_get [String] vals 0 ) { T s → ( string_data s ) F → `` }
    : s v1 ?? ( vec_get [String] vals 1 ) { T s → ( string_data s ) F → `` }
    : s v2 ?? ( vec_get [String] vals 2 ) { T s → ( string_data s ) F → `` }
    ? != 1 ( nurl_str_eq v0 `alpha` ) { ( nurl_print `  FAIL include0\n` ) = fails + fails 1 } {}
    ? != 1 ( nurl_str_eq v1 `beta` ) { ( nurl_print `  FAIL include1\n` ) = fails + fails 1 } {}
    ? != 1 ( nurl_str_eq v2 `gamma` ) { ( nurl_print `  FAIL include2\n` ) = fails + fails 1 } {}
    ( vec_free_with [String] vals \ String s → v { ( string_free s ) } )
    // An option that was never given has no values, and asking is not an error.
    : ( Vec String ) none4 ( args_values p4 `missing` )
    = fails + fails ( expect_int ( vec_len [String] none4 ) 0 `absent values` )
    ( vec_free [String] none4 )
    ( vec_free_with [String] t4 \ String s → v { ( string_free s ) } )
    ( args_free p4 )

    // ── unknown option must error ──
    : ArgParser p3 ( args_new `demo3` `` )
    ( args_flag p3 `verbose` 118 `` )
    : ( Vec String ) t3 ( vec_new [String] )
    ( push_tok t3 `--nope` )
    : b ok3 ( args_parse p3 t3 )
    ? ok3 { ( nurl_print `  FAIL: accepted unknown option\n` ) = fails + fails 1 } {}
    ? ! ( args_has_error p3 ) { ( nurl_print `  FAIL: no error set\n` ) = fails + fails 1 } {}
    ( vec_free_with [String] t3 \ String s → v { ( string_free s ) } )
    ( args_free p3 )

    ? == fails 0 {
        ( nurl_print `args: all checks PASS\n` )
    } {
        ( nurl_print `args: ` ) ( nurl_print ( nurl_str_int fails ) ) ( nurl_print ` FAILURES\n` )
    }
    ^ fails
}
