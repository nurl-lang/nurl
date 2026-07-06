// tests/basic.nu — variables, escaping, filters, literals.
// Self-asserting: prints PASS/FAIL per case, exits non-zero on any FAIL.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/json.nu`
$ `src/template.nu`

@ check s name s tpl s cj s want → i {
    : ~ i rc 0
    : ~ Json ctx ( json_null )
    : ~ b ctxok T
    ? > ( nurl_str_len cj ) 0 {
        ?? ( json_parse cj ) {
            T j → { = ctx j }
            F e → {
                = ctxok F
                ( nurl_print `FAIL ` ) ( nurl_print name ) ( nurl_print ` (ctx parse error)\n` )
            }
        }
    } {}
    ? ctxok {
        ?? ( tpl_render tpl ctx ) {
            T got → {
                ? == ( nurl_str_eq ( string_data got ) want ) 1 {
                    ( nurl_print `PASS ` ) ( nurl_print name ) ( nurl_print `\n` )
                } {
                    = rc 1
                    ( nurl_print `FAIL ` ) ( nurl_print name )
                    ( nurl_print `\n  want: ` ) ( nurl_print want )
                    ( nurl_print `\n  got:  ` ) ( nurl_print ( string_data got ) )
                    ( nurl_print `\n` )
                }
                ( string_free got )
            }
            F m → {
                = rc 1
                ( nurl_print `FAIL ` ) ( nurl_print name )
                ( nurl_print ` (error: ` ) ( nurl_print ( string_data m ) ) ( nurl_print `)\n` )
                ( string_free m )
            }
        }
    } { = rc 1 }
    ( json_free ctx )
    ^ rc
}

// Expect a render ERROR whose message contains `frag`.
@ check_err s name s tpl s cj s frag → i {
    : ~ i rc 0
    : ~ Json ctx ( json_null )
    ? > ( nurl_str_len cj ) 0 {
        ?? ( json_parse cj ) { T j → { = ctx j } F e → {} }
    } {}
    ?? ( tpl_render tpl ctx ) {
        T got → {
            = rc 1
            ( nurl_print `FAIL ` ) ( nurl_print name ) ( nurl_print ` (expected error, got output: ` )
            ( nurl_print ( string_data got ) ) ( nurl_print `)\n` )
            ( string_free got )
        }
        F m → {
            ? ( string_contains m frag ) {
                ( nurl_print `PASS ` ) ( nurl_print name ) ( nurl_print `\n` )
            } {
                = rc 1
                ( nurl_print `FAIL ` ) ( nurl_print name ) ( nurl_print ` (wrong error: ` )
                ( nurl_print ( string_data m ) ) ( nurl_print `)\n` )
            }
            ( string_free m )
        }
    }
    ( json_free ctx )
    ^ rc
}

@ main → i {
    : ~ i rc 0

    // plain text passes through
    = rc + rc ( check `plain-text` `hello world` `` `hello world` )

    // simple variable + escaping
    = rc + rc ( check `var-str` `Hi {{ name }}!` `{"name":"Ada"}` `Hi Ada!` )
    = rc + rc ( check `var-escaped` `{{ x }}` `{"x":"<b>&'q'</b>"}` `&lt;b&gt;&amp;&#39;q&#39;&lt;/b&gt;` )
    = rc + rc ( check `var-raw` `{{ x | raw }}` `{"x":"<b>ok</b>"}` `<b>ok</b>` )

    // missing key → empty
    = rc + rc ( check `var-missing` `[{{ nope }}]` `{"name":"Ada"}` `[]` )

    // dotted path + array index
    = rc + rc ( check `path-nested` `{{ user.name }} ({{ user.age }})` `{"user":{"name":"Bo","age":7}}` `Bo (7)` )
    = rc + rc ( check `path-arr-idx` `{{ xs.1 }}` `{"xs":[10,20,30]}` `20` )

    // numbers and booleans render plainly
    = rc + rc ( check `num-out` `{{ n }}` `{"n":3.5}` `3.5` )
    = rc + rc ( check `bool-out` `{{ t }}/{{ f }}` `{"t":true,"f":false}` `true/false` )

    // null renders as empty
    = rc + rc ( check `null-out` `[{{ z }}]` `{"z":null}` `[]` )

    // filters
    = rc + rc ( check `filter-upper` `{{ s | upper }}` `{"s":"abc"}` `ABC` )
    = rc + rc ( check `filter-lower` `{{ s | lower }}` `{"s":"AbC"}` `abc` )
    = rc + rc ( check `filter-length-str` `{{ s | length }}` `{"s":"abcd"}` `4` )
    = rc + rc ( check `filter-length-arr` `{{ xs | length }}` `{"xs":[1,2,3]}` `3` )
    = rc + rc ( check `filter-json` `{{ xs | json | raw }}` `{"xs":[1,2]}` `[1,2]` )

    // string/number literals in output position
    = rc + rc ( check `lit-str` `{{ 'lit<' }}` `` `lit&lt;` )
    = rc + rc ( check `lit-num` `{{ 42 }}` `` `42` )

    // comments vanish
    = rc + rc ( check `comment` `a{# gone #}b` `` `ab` )

    // literal braces that are not tag openers pass through
    = rc + rc ( check `lone-brace` `a { b } c` `` `a { b } c` )

    // objects stringify
    = rc + rc ( check `obj-out` `{{ o | json | raw }}` `{"o":{"k":1}}` `{"k":1}` )

    // errors
    = rc + rc ( check_err `err-unclosed-out` `x {{ name` `{"name":"A"}` `unclosed '{{'` )
    = rc + rc ( check_err `err-unknown-filter` `{{ name | nope }}` `{"name":"A"}` `unknown filter` )
    = rc + rc ( check_err `err-bad-tag` `{% frob %}` `` `unknown tag` )
    = rc + rc ( check_err `err-stray-end` `x {% end %}` `` `without an open block` )

    ? == rc 0 { ( nurl_print `basic: all PASS\n` ) } {
        ( nurl_print `basic: FAILURES\n` )
    }
    ^ rc
}
