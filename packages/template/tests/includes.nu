// tests/includes.nu — TplSet, {% include %}, tset_render, tset_load_dir.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/json.nu`
$ `src/template.nu`
$ `src/loader.nu`

@ report s name b good → i {
    ? good {
        ( nurl_print `PASS ` ) ( nurl_print name ) ( nurl_print `\n` )
        ^ 0
    } {
        ( nurl_print `FAIL ` ) ( nurl_print name ) ( nurl_print `\n` )
        ^ 1
    }
}

@ render_eq * TplSet t s name s cj s want → b {
    : ~ Json ctx ( json_null )
    ? > ( nurl_str_len cj ) 0 {
        ?? ( json_parse cj ) { T j → { = ctx j } F e → {} }
    } {}
    : ~ b good F
    ?? ( tset_render t name ctx ) {
        T got → {
            ? == ( nurl_str_eq ( string_data got ) want ) 1 { = good T } {
                ( nurl_print `  got:  ` ) ( nurl_print ( string_data got ) ) ( nurl_print `\n` )
                ( nurl_print `  want: ` ) ( nurl_print want ) ( nurl_print `\n` )
            }
            ( string_free got )
        }
        F m → {
            ( nurl_print `  error: ` ) ( nurl_print ( string_data m ) ) ( nurl_print `\n` )
            ( string_free m )
        }
    }
    ( json_free ctx )
    ^ good
}

@ main → i {
    : ~ i rc 0
    : *TplSet t ( tset_new )

    ( tset_add t `head` `<h1>{{ title }}</h1>` )
    ( tset_add t `page` `{% include 'head' %}<p>{{ body }}</p>` )
    ( tset_add t `item` `[{{ x }}]` )
    ( tset_add t `list` `{% for x in xs %}{% include 'item' %}{% end %}` )
    ( tset_add t `cyc_a` `{% include 'cyc_b' %}` )
    ( tset_add t `cyc_b` `{% include 'cyc_a' %}` )

    // tset_has / replace
    = rc + rc ( report `tset-has` ( tset_has t `head` ) )
    = rc + rc ( report `tset-has-not` == ( tset_has t `nope` ) F )
    ( tset_add t `head` `<h2>{{ title }}</h2>` )
    = rc + rc ( report `tset-replace`
    ( render_eq t `head` `{"title":"T"}` `<h2>T</h2>` ) )

    // include inherits context
    = rc + rc ( report `include-ctx`
    ( render_eq t `page` `{"title":"Hi","body":"b"}` `<h2>Hi</h2><p>b</p>` ) )

    // include inside a for sees the loop variable
    = rc + rc ( report `include-loopvar`
    ( render_eq t `list` `{"xs":[1,2]}` `[1][2]` ) )

    // include cycle is caught, not a stack overflow
    : ~ b cyc_caught F
    : Json e0 ( json_null )
    ?? ( tset_render t `cyc_a` e0 ) {
        T got → { ( string_free got ) }
        F m → {
            ? ( string_contains m `depth` ) { = cyc_caught T } {}
            ( string_free m )
        }
    }
    = rc + rc ( report `include-cycle` cyc_caught )

    // missing template name
    : ~ b miss_caught F
    : Json e1 ( json_null )
    ?? ( tset_render t `ghost` e1 ) {
        T got → { ( string_free got ) }
        F m → {
            ? ( string_contains m `not found` ) { = miss_caught T } {}
            ( string_free m )
        }
    }
    = rc + rc ( report `tset-missing` miss_caught )

    // include without a set fails cleanly
    : ~ b noset_caught F
    : Json e2 ( json_null )
    ?? ( tpl_render `{% include 'head' %}` e2 ) {
        T got → { ( string_free got ) }
        F m → {
            ? ( string_contains m `template set` ) { = noset_caught T } {}
            ( string_free m )
        }
    }
    = rc + rc ( report `include-no-set` noset_caught )

    // tpl_render_with: one-shot source resolving includes from the set
    : ~ b withok F
    : ~ Json c3 ( json_null )
    ?? ( json_parse `{"title":"W"}` ) { T j → { = c3 j } F e → {} }
    ?? ( tpl_render_with t `pre {% include 'head' %} post` c3 ) {
        T got → {
            ? == ( nurl_str_eq ( string_data got ) `pre <h2>W</h2> post` ) 1 { = withok T } {}
            ( string_free got )
        }
        F m → { ( string_free m ) }
    }
    ( json_free c3 )
    = rc + rc ( report `render-with` withok )

    ( tset_free t )

    // tset_load_dir over a scratch directory
    : s tdir `/tmp/nurl_tpl_loader_test`
    ?? ( dir_create_all tdir ) { T _ → {} F _ → {} }
    ?? ( write_file `/tmp/nurl_tpl_loader_test/hello.html` `Hello {{ who }}` ) { T _ → {} F _ → {} }
    ?? ( write_file `/tmp/nurl_tpl_loader_test/bye.html` `Bye {{ who }}` ) { T _ → {} F _ → {} }
    : *TplSet t2 ( tset_new )
    : i nl ( tset_load_dir t2 tdir `.html` )
    = rc + rc ( report `load-dir-count` == nl 2 )
    = rc + rc ( report `load-dir-render`
    ( render_eq t2 `hello` `{"who":"you"}` `Hello you` ) )
    ( tset_free t2 )

    ? == rc 0 { ( nurl_print `includes: all PASS\n` ) } {
        ( nurl_print `includes: FAILURES\n` )
    }
    ^ rc
}
