// Test: stdlib/std/fmt.nu — `{}` placeholder substitution
//
// Covers: simple substitution, all four arities, missing/surplus args,
// `{{` / `}}` escapes, stray braces, owned String input, integer input.

$ `stdlib/std/fmt.nu`

@ main → i {
    // simple 1-arg
    ( println_fmt1 `Hello, {}!` `World` )

    // 2-arg ordering
    ( println_fmt2 `{} = {}` `answer` `42` )

    // 3-arg
    ( println_fmt3 `[{}|{}|{}]` `a` `b` `c` )

    // 4-arg
    ( println_fmt4 `{}-{}-{} :: {}` `2026` `04` `30` `OK` )

    // integer + owned String mixed
    : String name ( string_from `Alice` )
    : i age 30
    ( println_fmt2 `{} is {} years old` ( string_data name ) ( nurl_str_int age ) )
    ( string_free name )

    // brace escapes
    ( println_fmt1 `before {{}} after = {}` `mid` )

    // missing arg → literal {}
    : String r ( fmt1 `a={} b={}` `1` )
    ( nurl_print ( string_data r ) )
    ( nurl_print `\n` )
    ( string_free r )

    // surplus args silently dropped
    ( println_fmt2 `only one {}` `kept` `dropped` )

    // stray closing brace stays verbatim
    ( println_fmt1 `} ok {}` `tail` )

    // dynamic-arity fmt with Vec[s]
    : ( Vec s ) v ( vec_with_cap [s] 3 )
    ( vec_push [s] v `x` )
    ( vec_push [s] v `y` )
    ( vec_push [s] v `z` )
    : String r2 ( fmt `({}, {}, {})` v )
    ( nurl_print ( string_data r2 ) )
    ( nurl_print `\n` )
    ( string_free r2 )
    ( vec_free [s] v )

    // empty template
    : String r3 ( fmt1 `` `unused` )
    ( nurl_print `empty=[` )
    ( nurl_print ( string_data r3 ) )
    ( nurl_print `]\n` )
    ( string_free r3 )

    // template that's all braces
    ( println_fmt1 `{{{}}}` `inside` )

    // stderr variant
    ( eprintln_fmt2 `warn: {} ({})` `disk full` `/tmp` )

    ( nurl_print `done\n` )
    ^ 0
}
