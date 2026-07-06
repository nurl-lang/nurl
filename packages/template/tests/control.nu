// tests/control.nu — if/elif/else, for + loop.*, nesting, conditions.

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

@ check_err s name s tpl s cj s frag → i {
    : ~ i rc 0
    : ~ Json ctx ( json_null )
    ? > ( nurl_str_len cj ) 0 {
        ?? ( json_parse cj ) { T j → { = ctx j } F e → {} }
    } {}
    ?? ( tpl_render tpl ctx ) {
        T got → {
            = rc 1
            ( nurl_print `FAIL ` ) ( nurl_print name ) ( nurl_print ` (expected error)\n` )
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

    // if / else on truthiness
    = rc + rc ( check `if-true` `{% if on %}Y{% end %}` `{"on":true}` `Y` )
    = rc + rc ( check `if-false` `{% if on %}Y{% end %}` `{"on":false}` `` )
    = rc + rc ( check `if-else` `{% if on %}Y{% else %}N{% end %}` `{"on":false}` `N` )
    = rc + rc ( check `if-missing-falsy` `{% if nope %}Y{% else %}N{% end %}` `{"a":1}` `N` )
    = rc + rc ( check `if-empty-str` `{% if s %}Y{% else %}N{% end %}` `{"s":""}` `N` )
    = rc + rc ( check `if-empty-arr` `{% if xs %}Y{% else %}N{% end %}` `{"xs":[]}` `N` )
    = rc + rc ( check `if-nonzero` `{% if n %}Y{% else %}N{% end %}` `{"n":2}` `Y` )
    = rc + rc ( check `if-zero` `{% if n %}Y{% else %}N{% end %}` `{"n":0}` `N` )

    // not / == / !=
    = rc + rc ( check `if-not` `{% if not on %}N{% end %}` `{"on":false}` `N` )
    = rc + rc ( check `if-eq-str` `{% if role == 'admin' %}A{% else %}U{% end %}` `{"role":"admin"}` `A` )
    = rc + rc ( check `if-neq-str` `{% if role != 'admin' %}U{% else %}A{% end %}` `{"role":"guest"}` `U` )
    = rc + rc ( check `if-eq-num` `{% if n == 3 %}three{% end %}` `{"n":3}` `three` )
    = rc + rc ( check `if-eq-paths` `{% if a == b %}same{% else %}diff{% end %}` `{"a":"x","b":"x"}` `same` )
    = rc + rc ( check `if-eq-bool-lit` `{% if on == true %}Y{% end %}` `{"on":true}` `Y` )
    = rc + rc ( check `if-eq-kind-mismatch` `{% if a == b %}same{% else %}diff{% end %}` `{"a":"1","b":1}` `diff` )

    // elif chain
    = rc + rc ( check `elif-first` `{% if n == 1 %}a{% elif n == 2 %}b{% else %}c{% end %}` `{"n":1}` `a` )
    = rc + rc ( check `elif-mid` `{% if n == 1 %}a{% elif n == 2 %}b{% else %}c{% end %}` `{"n":2}` `b` )
    = rc + rc ( check `elif-else` `{% if n == 1 %}a{% elif n == 2 %}b{% else %}c{% end %}` `{"n":9}` `c` )

    // endif/endfor aliases
    = rc + rc ( check `endif-alias` `{% if on %}Y{% endif %}` `{"on":true}` `Y` )

    // for over arrays
    = rc + rc ( check `for-basic` `{% for x in xs %}{{ x }},{% end %}` `{"xs":[1,2,3]}` `1,2,3,` )
    = rc + rc ( check `for-objs` `{% for u in users %}{{ u.name }};{% end %}` `{"users":[{"name":"A"},{"name":"B"}]}` `A;B;` )
    = rc + rc ( check `for-empty` `[{% for x in xs %}{{ x }}{% end %}]` `{"xs":[]}` `[]` )
    = rc + rc ( check `for-missing` `[{% for x in nope %}{{ x }}{% end %}]` `{"a":1}` `[]` )
    = rc + rc ( check `endfor-alias` `{% for x in xs %}{{ x }}{% endfor %}` `{"xs":[7]}` `7` )

    // loop.* attributes
    = rc + rc ( check `loop-index` `{% for x in xs %}{{ loop.index }}:{{ x }} {% end %}` `{"xs":["a","b"]}` `0:a 1:b ` )
    = rc + rc ( check `loop-first-last` `{% for x in xs %}{% if loop.first %}[{% end %}{{ x }}{% if loop.last %}]{% else %},{% end %}{% end %}` `{"xs":[1,2,3]}` `[1,2,3]` )
    = rc + rc ( check `loop-length` `{% for x in xs %}{{ loop.length }}{% end %}` `{"xs":[5,6]}` `22` )

    // nested for + inner loop shadows loop.*
    = rc + rc ( check `for-nested` `{% for row in grid %}{% for c in row %}{{ c }}{% end %};{% end %}` `{"grid":[[1,2],[3,4]]}` `12;34;` )
    = rc + rc ( check `for-nested-loopvar` `{% for row in grid %}{% for c in row %}{{ loop.index }}{% end %}|{% end %}` `{"grid":[[9,9],[9]]}` `01|0|` )

    // loop var shadows a context key
    = rc + rc ( check `loopvar-shadows-ctx` `{% for x in xs %}{{ x }}{% end %}{{ x }}` `{"xs":[1],"x":"ctx"}` `1ctx` )

    // if nested in for, for nested in if
    = rc + rc ( check `if-in-for` `{% for x in xs %}{% if x == 2 %}<{{ x }}>{% else %}{{ x }}{% end %}{% end %}` `{"xs":[1,2,3]}` `1<2>3` )
    = rc + rc ( check `for-in-if-skipped` `{% if off %}{% for x in xs %}{{ x }}{% end %}{% else %}skipped{% end %}` `{"off":false,"xs":[1,2]}` `skipped` )

    // errors
    = rc + rc ( check_err `err-unclosed-if` `{% if on %}Y` `{"on":true}` `without matching` )
    = rc + rc ( check_err `err-unclosed-for` `{% for x in xs %}{{ x }}` `{"xs":[1]}` `without matching` )
    = rc + rc ( check_err `err-for-nonarray` `{% for x in s %}{{ x }}{% end %}` `{"s":"str"}` `non-array` )
    = rc + rc ( check_err `err-for-malformed` `{% for %}x{% end %}` `` `malformed` )
    = rc + rc ( check_err `err-bad-op` `{% if a < b %}x{% end %}` `{"a":1,"b":2}` `unsupported operator` )

    ? == rc 0 { ( nurl_print `control: all PASS\n` ) } {
        ( nurl_print `control: FAILURES\n` )
    }
    ^ rc
}
