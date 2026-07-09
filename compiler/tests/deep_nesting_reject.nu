// deep_nesting_reject.nu — the XML and YAML-flow parsers must REJECT
// pathologically deep nesting (a crafted-input stack-overflow DoS) instead of
// recursing into a C-stack overflow. Regression for the XML_MAX_DEPTH /
// YAML_MAX_DEPTH guards. Shallow documents must still parse.

$ `stdlib/ext/xml.nu`
$ `stdlib/ext/yaml.nu`
$ `stdlib/core/string.nu`

@ deep_rep s unit i times → String {
    : String s ( string_new )
    : ~ i i 0
    ~ < i times { ( string_push_str s unit ) = i + i 1 }
    ^ s
}

@ main → i {
    // XML: 5000 nested <a> … </a> exceeds XML_MAX_DEPTH (256).
    : String xopen ( deep_rep `<a>` 5000 )
    : String xclose ( deep_rep `</a>` 5000 )
    ( string_push_str xopen ( string_data xclose ) )
    : !Xml XmlErr xr ( xml_parse ( string_data xopen ) )
    ?? xr {
        T nd → { ( nurl_print `xml: parsed deep (unexpected!)\n` ) ( xml_free nd ) }
        F _ → ( nurl_print `xml: deep rejected\n` )
    }
    ( string_free xopen )
    ( string_free xclose )

    // YAML flow: 5000 nested [ exceeds YAML_MAX_DEPTH (256).
    : String yopen ( deep_rep `[` 5000 )
    : String yclose ( deep_rep `]` 5000 )
    ( string_push_str yopen ( string_data yclose ) )
    : !Json YamlErr yr ( yaml_parse ( string_data yopen ) )
    ?? yr {
        T j → { ( nurl_print `yaml: parsed deep (unexpected!)\n` ) ( json_free j ) }
        F _ → ( nurl_print `yaml: deep rejected\n` )
    }
    ( string_free yopen )
    ( string_free yclose )

    // Shallow documents still parse.
    : !Xml XmlErr sx ( xml_parse `<a><b>hi</b></a>` )
    ?? sx {
        T nd → { ( nurl_print `xml: shallow ok\n` ) ( xml_free nd ) }
        F _ → ( nurl_print `xml: shallow rejected (unexpected!)\n` )
    }
    : !Json YamlErr sy ( yaml_parse `[1, [2, 3], 4]` )
    ?? sy {
        T j → { ( nurl_print `yaml: shallow ok\n` ) ( json_free j ) }
        F _ → ( nurl_print `yaml: shallow rejected (unexpected!)\n` )
    }
    ^ 0
}
