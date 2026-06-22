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
