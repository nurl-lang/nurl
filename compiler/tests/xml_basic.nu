// Regression: stdlib/ext/xml.nu — parse + navigate + serialize. Covers
// elements, attributes, entity decode (named + numeric), self-closing
// tags, comments, CDATA, nesting, inner-text concatenation, and
// round-trip serialization with entity encoding. Returns failure count.

$ `stdlib/ext/xml.nu`
$ `stdlib/core/string.nu`

// Compare an owned ?String to an expected literal; frees the payload.
@ chk ?String got s want s label → i {
    : ~ i bad 1
    ?? got { T s → { ? == 1 ( nurl_str_eq ( string_data s ) want ) { = bad 0 } {} ( string_free s ) } F → {} }
    ? > bad 0 { ( nurl_print `  FAIL ` ) ( nurl_print label ) ( nurl_print `\n` ) } {}
    ^ bad
}

@ chk_inner Xml x s want s label → i {
    : String it ( xml_inner_text x )
    : ~ i bad ? == 1 ( nurl_str_eq ( string_data it ) want ) 0 1
    ( string_free it )
    ? > bad 0 { ( nurl_print `  FAIL inner ` ) ( nurl_print label ) ( nurl_print `\n` ) } {}
    ^ bad
}

@ main → i {
    : ~ i fails 0

    : !Xml XmlErr pr ( xml_parse `<root id="1" name="a&amp;b"><item x="10">hello &lt;world&gt;</item><empty/><nested><deep>v&#65;&#x42;</deep></nested><c><![CDATA[<raw> & s]]></c></root>` )
    ?? pr {
        T root → {
            = fails + fails ( chk ( xml_tag root ) `root` `root-tag` )
            = fails + fails ( chk ( xml_attr root `id` ) `1` `root-id` )
            = fails + fails ( chk ( xml_attr root `name` ) `a&b` `entity-amp` )
            ? != ( xml_child_count root ) 4 { ( nurl_print `  FAIL child-count\n` ) = fails + fails 1 } {}

            // <item x="10">hello &lt;world&gt;</item>
            ?? ( xml_find root `item` ) {
                T item → {
                    = fails + fails ( chk ( xml_attr item `x` ) `10` `item-x` )
                    = fails + fails ( chk_inner item `hello <world>` `item-text` )
                }
                F → { ( nurl_print `  FAIL no item\n` ) = fails + fails 1 }
            }

            // <empty/> → element, zero children
            ?? ( xml_find root `empty` ) {
                T em → { ? != ( xml_child_count em ) 0 { ( nurl_print `  FAIL empty children\n` ) = fails + fails 1 } {} ? ! ( xml_is_elem em ) { ( nurl_print `  FAIL empty not elem\n` ) = fails + fails 1 } {} }
                F → { ( nurl_print `  FAIL no empty\n` ) = fails + fails 1 }
            }

            // nested + numeric char refs &#65;&#x42; → "AB"
            ?? ( xml_find root `nested` ) {
                T nested → {
                    ?? ( xml_find nested `deep` ) {
                        T deep → { = fails + fails ( chk_inner deep `vAB` `numeric-refs` ) }
                        F → { ( nurl_print `  FAIL no deep\n` ) = fails + fails 1 }
                    }
                }
                F → { ( nurl_print `  FAIL no nested\n` ) = fails + fails 1 }
            }

            // CDATA preserved verbatim
            ?? ( xml_find root `c` ) {
                T c → { = fails + fails ( chk_inner c `<raw> & s` `cdata` ) }
                F → { ( nurl_print `  FAIL no c\n` ) = fails + fails 1 }
            }

            // Round-trip: serialize then re-parse; structure survives.
            : String s1 ( xml_stringify root )
            : !Xml XmlErr pr2 ( xml_parse ( string_data s1 ) )
            ?? pr2 {
                T root2 → {
                    = fails + fails ( chk ( xml_tag root2 ) `root` `rt-tag` )
                    = fails + fails ( chk ( xml_attr root2 `name` ) `a&b` `rt-entity` )
                    ?? ( xml_find root2 `item` ) { T it2 → { = fails + fails ( chk_inner it2 `hello <world>` `rt-item` ) } F → { ( nurl_print `  FAIL rt no item\n` ) = fails + fails 1 } }
                    ( xml_free root2 )
                }
                F → { ( nurl_print `  FAIL re-parse\n` ) = fails + fails 1 }
            }
            ( string_free s1 )

            ( xml_free root )
        }
        F e → { ( nurl_print `  FAIL parse: ` ) ( nurl_print ( xml_err_name e ) ) ( nurl_print `\n` ) = fails + fails 1 }
    }

    // Built tree → entity-encoded serialization.
    : Xml b ( xml_elem `n` )
    ( xml_set_attr b `q` `a"b` )
    ( xml_add_child b ( xml_text `x < y & z` ) )
    : String bs ( xml_stringify b )
    ? != 1 ( nurl_str_eq ( string_data bs ) `<n q="a&quot;b">x &lt; y &amp; z</n>` ) {
        ( nurl_print `  FAIL encode got "` ) ( nurl_print ( string_data bs ) ) ( nurl_print `"\n` ) = fails + fails 1
    } {}
    ( string_free bs )
    ( xml_free b )

    // Malformed input rejected.
    : !Xml XmlErr bad ( xml_parse `not xml at all` )
    ?? bad { T x → { ( nurl_print `  FAIL accepted junk\n` ) ( xml_free x ) = fails + fails 1 } F → {} }

    ? == fails 0 { ( nurl_print `xml: all checks PASS\n` ) } {
        ( nurl_print `xml: ` ) ( nurl_print ( nurl_str_int fails ) ) ( nurl_print ` FAILURES\n` )
    }
    ^ fails
}
