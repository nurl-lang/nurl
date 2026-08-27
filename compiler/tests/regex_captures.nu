// regex_captures.nu — capture groups: regex_find_caps / regex_expand.
//
// Pins the Pike-VM capture layer: group numbering by opening paren,
// nesting, a group that does not participate, leftmost-longest
// alternation, and the `&` / `\N` replacement template.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/regex.nu`

@ show s pat s text s tmpl → v {
    ( nurl_print pat )
    ( nurl_print ` | ` )
    ( nurl_print text )
    ( nurl_print ` | ` )
    ?? ( regex_compile pat ) {
        T r → {
            : ( Vec i ) slots ( vec_new [i] )
            ?? ( regex_find_caps r text slots ) {
                T m → {
                    ( nurl_print ( nurl_str_int ( regex_ngroups r ) ) )
                    ( nurl_print ` groups @` )
                    ( nurl_print ( nurl_str_int . m start ) )
                    ( nurl_print `+` )
                    ( nurl_print ( nurl_str_int . m len ) )
                    ( nurl_print ` → ` )
                    : String e ( regex_expand text slots tmpl )
                    ( nurl_print ( string_data e ) )
                    ( string_free e )
                }
                F _ → ( nurl_print `no match` )
            }
            ( vec_free [i] slots )
            ( regex_free r )
        }
        F _ → ( nurl_print `compile error` )
    }
    ( nurl_print `\n` )
}

@ main → i {
    ( show `(a+)(b+)` `xxaaabbyy` `<\1|\2>` )
    ( show `([a-z]+)@([a-z]+)` `mail ada@example org` `\2:\1` )
    ( show `foo` `a foo b` `[&]` )
    ( show `(x)?(y)` `y` `1=[\1] 2=[\2]` )
    ( show `((a)(b))c` `abc` `\1 \2 \3` )
    ( show `a|ab` `abc` `&` )
    ( show `^(\w+)\s+(\w+)$` `hello world` `\2 \1` )
    ( show `(a)(b)(c)(d)(e)(f)(g)(h)(i)` `abcdefghi` `\9\8\7\6\5\4\3\2\1` )
    ( show `(no)` `yes` `\1` )
    ( show `x(y*)z` `xz` `[\1]` )
    ( show `(a|b)+` `abab` `&/\1` )
    ( show `q` `q` `\&amp \\\\ slash \n newline` )
    ^ 0
}
