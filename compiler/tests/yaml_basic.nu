// Regression: stdlib/ext/yaml.nu — parse into the shared Json model +
// block-style serialize. Covers block mappings/sequences, nested blocks,
// the "sequence under key at same indent" idiom, compact `- key: val`,
// plain/quoted scalars, scalar type resolution (null/bool/int/float/str),
// flow collections, comments, document markers, round-trip, and rejects
// (tab indent, unterminated flow). Returns failure count.

$ `stdlib/ext/yaml.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/core/string.nu`

// Probe a dotted path and assert the leaf renders to `want` via json.
@ chk_str Json root s path s want s label → i {
    : ?Json got ( json_get root path )
    : ~ i bad 1
    ?? got {
        T j → { ? == 1 ( nurl_str_eq ( json_as_str j ) want ) { = bad 0 } {} }
        F → {}
    }
    ? > bad 0 { ( nurl_print `  FAIL ` ) ( nurl_print label ) ( nurl_print `\n` ) } {}
    ^ bad
}

@ chk_int Json root s path i want s label → i {
    : ?Json got ( json_get root path )
    : ~ i bad 1
    ?? got {
        T j → { ? == ( json_as_int j ) want { = bad 0 } {} }
        F → {}
    }
    ? > bad 0 { ( nurl_print `  FAIL ` ) ( nurl_print label ) ( nurl_print `\n` ) } {}
    ^ bad
}

@ chk_bool Json root s path b want s label → i {
    : ?Json got ( json_get root path )
    : ~ i bad 1
    ?? got {
        T j → { ? == ( json_as_bool j ) want { = bad 0 } {} }
        F → {}
    }
    ? > bad 0 { ( nurl_print `  FAIL ` ) ( nurl_print label ) ( nurl_print `\n` ) } {}
    ^ bad
}

@ chk_null Json root s path s label → i {
    : ?Json got ( json_get root path )
    : ~ i bad 1
    ?? got { T j → { ? ( json_is_null j ) { = bad 0 } {} } F → {} }
    ? > bad 0 { ( nurl_print `  FAIL ` ) ( nurl_print label ) ( nurl_print `\n` ) } {}
    ^ bad
}

@ main → i {
    : ~ i fails 0

    // ── Block mapping + nested map + block sequence (same-indent) +
    //    nested-indent sequence + compact `- k: v` + scalar types ──
    : s doc `name: widget
count: 42
ratio: 3.14
enabled: true
disabled: false
empty: null
tilde: ~
quoted: "a: b # c"
single: 'it''s ok'
tags:
- alpha
- beta
nested:
  host: localhost
  port: 8080
matrix:
  - - 1
    - 2
  - - 3
    - 4
people:
  - name: ann
    age: 30
  - name: bob
    age: 25
flowlist: [10, 20, 30]
flowmap: {x: 1, y: two}
# trailing comment line
`

    : !Json YamlErr pr ( yaml_parse doc )
    ?? pr {
        T root → {
            = fails + fails ( chk_str root `name` `widget` `name` )
            = fails + fails ( chk_int root `count` 42 `count` )
            // 3.14 resolves to a JNum (not a string): json_as_int truncates it.
            = fails + fails ( chk_int root `ratio` 3 `ratio-num` )
            = fails + fails ( chk_bool root `enabled` T `enabled` )
            = fails + fails ( chk_bool root `disabled` F `disabled` )
            = fails + fails ( chk_null root `empty` `null` )
            = fails + fails ( chk_null root `tilde` `tilde` )
            // quoted scalar keeps the colon/hash literally
            = fails + fails ( chk_str root `quoted` `a: b # c` `quoted` )
            = fails + fails ( chk_str root `single` `it's ok` `single` )
            // block sequence at the key's own indent
            = fails + fails ( chk_str root `tags.0` `alpha` `tags-0` )
            = fails + fails ( chk_str root `tags.1` `beta` `tags-1` )
            // nested map
            = fails + fails ( chk_str root `nested.host` `localhost` `nested-host` )
            = fails + fails ( chk_int root `nested.port` 8080 `nested-port` )
            // nested sequence of sequences
            = fails + fails ( chk_int root `matrix.0.0` 1 `m-00` )
            = fails + fails ( chk_int root `matrix.0.1` 2 `m-01` )
            = fails + fails ( chk_int root `matrix.1.0` 3 `m-10` )
            = fails + fails ( chk_int root `matrix.1.1` 4 `m-11` )
            // compact `- key: val` list of maps
            = fails + fails ( chk_str root `people.0.name` `ann` `p0-name` )
            = fails + fails ( chk_int root `people.0.age` 30 `p0-age` )
            = fails + fails ( chk_str root `people.1.name` `bob` `p1-name` )
            = fails + fails ( chk_int root `people.1.age` 25 `p1-age` )
            // flow collections
            = fails + fails ( chk_int root `flowlist.0` 10 `fl-0` )
            = fails + fails ( chk_int root `flowlist.2` 30 `fl-2` )
            = fails + fails ( chk_int root `flowmap.x` 1 `fm-x` )
            = fails + fails ( chk_str root `flowmap.y` `two` `fm-y` )

            // ── Round-trip: stringify → re-parse → structure survives ──
            : String s1 ( yaml_stringify root )
            : !Json YamlErr pr2 ( yaml_parse ( string_data s1 ) )
            ?? pr2 {
                T root2 → {
                    = fails + fails ( chk_str root2 `name` `widget` `rt-name` )
                    = fails + fails ( chk_int root2 `nested.port` 8080 `rt-port` )
                    = fails + fails ( chk_str root2 `tags.1` `beta` `rt-tags` )
                    = fails + fails ( chk_str root2 `people.1.name` `bob` `rt-people` )
                    = fails + fails ( chk_int root2 `matrix.1.1` 4 `rt-matrix` )
                    = fails + fails ( chk_str root2 `quoted` `a: b # c` `rt-quoted` )
                    ( json_free root2 )
                }
                F e → { ( nurl_print `  FAIL re-parse: ` ) ( nurl_print ( yaml_err_name e ) ) ( nurl_print `\n` ) = fails + fails 1 }
            }
            ( string_free s1 )

            ( json_free root )
        }
        F e → { ( nurl_print `  FAIL parse: ` ) ( nurl_print ( yaml_err_name e ) ) ( nurl_print `\n` ) = fails + fails 1 }
    }

    // ── Top-level flow document ──
    : !Json YamlErr fr ( yaml_parse `[1, "two", {k: v}]` )
    ?? fr {
        T r → {
            ? != ( json_arr_len r ) 3 { ( nurl_print `  FAIL top-flow len\n` ) = fails + fails 1 } {}
            = fails + fails ( chk_str r `2.k` `v` `top-flow-k` )
            ( json_free r )
        }
        F → { ( nurl_print `  FAIL top-flow parse\n` ) = fails + fails 1 }
    }

    // ── Empty document → null ──
    : !Json YamlErr er ( yaml_parse `# only a comment\n` )
    ?? er { T r → { ? ! ( json_is_null r ) { ( nurl_print `  FAIL empty not null\n` ) = fails + fails 1 } {} ( json_free r ) } F → { ( nurl_print `  FAIL empty parse\n` ) = fails + fails 1 } }

    // ── Reject: tab used for indentation ──
    : !Json YamlErr tr ( yaml_parse `a:\n\tb: 1` )
    ?? tr { T r → { ( nurl_print `  FAIL accepted tab indent\n` ) ( json_free r ) = fails + fails 1 } F → {} }

    // ── Reject: unterminated flow sequence ──
    : !Json YamlErr ur ( yaml_parse `x: [1, 2` )
    ?? ur { T r → { ( nurl_print `  FAIL accepted unterminated flow\n` ) ( json_free r ) = fails + fails 1 } F → {} }

    // ── Serializer quoting: a string that looks like a number/bool or
    //    carries a colon must come back as a string, not get reinterpreted ──
    : Json o ( json_obj_new )
    ( json_obj_set o `a` ( json_str_lit `123` ) )
    ( json_obj_set o `b` ( json_str_lit `true` ) )
    ( json_obj_set o `c` ( json_str_lit `x: y` ) )
    ( json_obj_set o `d` ( json_int 7 ) )
    : String os ( yaml_stringify o )
    : !Json YamlErr orp ( yaml_parse ( string_data os ) )
    ?? orp {
        T r → {
            = fails + fails ( chk_str r `a` `123` `q-num-str` )
            = fails + fails ( chk_str r `b` `true` `q-bool-str` )
            = fails + fails ( chk_str r `c` `x: y` `q-colon` )
            = fails + fails ( chk_int r `d` 7 `q-real-int` )
            ( json_free r )
        }
        F → { ( nurl_print `  FAIL quoting re-parse\n` ) = fails + fails 1 }
    }
    ( string_free os )
    ( json_free o )

    ? == fails 0 { ( nurl_print `yaml: all checks PASS\n` ) } {
        ( nurl_print `yaml: ` ) ( nurl_print ( nurl_str_int fails ) ) ( nurl_print ` FAILURES\n` )
    }
    ^ fails
}
