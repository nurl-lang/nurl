// stdlib/ext/xml.nu — a pragmatic XML parser + serializer
//
// Parses the common XML subset into an `Xml` tree and serializes it
// back. Handles: elements, attributes (single- or double-quoted),
// nested children, self-closing tags, text content, comments
// (`<!-- … -->`), the XML declaration / processing instructions
// (`<?…?>`, skipped), `<![CDATA[…]]>` sections, and the five predefined
// entities plus numeric character references (`&#NN;` / `&#xHH;`).
//
// NOT handled (out of scope for a config/data-interchange parser):
// DTDs / `<!DOCTYPE …>` internal subsets, namespace resolution (prefixes
// are kept verbatim in the tag/attr name), and entity declarations
// beyond the predefined five.
//
//   ( xml_parse src )            → ! Xml XmlErr   parse a document
//   ( xml_elem tag )             → Xml            empty element node
//   ( xml_text s )               → Xml            text node
//   ( xml_is_elem x ) / _is_text → b
//   ( xml_tag x )                → ? String       element tag (owned copy)
//   ( xml_text_value x )         → ? String       text-node content (owned)
//   ( xml_attr x name )          → ? String       attribute value (owned)
//   ( xml_child_count x )        → i
//   ( xml_child_at x i )         → ? Xml          BORROW — do not free
//   ( xml_find x tag )           → ? Xml          first element child w/ tag (BORROW)
//   ( xml_inner_text x )         → String         concatenated descendant text
//   ( xml_set_attr x name val )  → v              set/replace (builder)
//   ( xml_add_child x child )    → v              append (CONSUMES child)
//   ( xml_stringify x )          → String         serialize (entity-encoded)
//   ( xml_free x )               → v
//
//   ( xml_err_name e )           → s
//
// Ownership: the tree owns its Strings / child nodes; xml_free cascades.
// Accessors that return ? Xml hand back a BORROW into the tree (do not
// free); accessors that return ? String / String return owned copies the
// caller frees.
//
// Node representation: a tagged struct with a `kind` discriminator
// (text nodes leave the element fields empty and vice-versa). This was
// ORIGINALLY a workaround — NURL used to heap-box a multi-field struct
// carried inside an enum variant and never reclaim the box. That box
// leak is now fixed at the compiler level: a boxed-payload enum gets a
// compiler-generated recursive Drop that reclaims the box (and the
// payload's owned String/Vec/nested fields) when an owned value goes out
// of scope, so an `: | Xml { XText String  XElem XmlElem }` enum tree
// self-frees with no manual `xml_free` (see compiler/tests/enum_tree_drop.nu
// for the proof). The flat struct is retained here because the parser's
// incremental, error-path-heavy construction is simpler with explicit
// `xml_free` control than with pure scope-exit auto-drop — a style
// choice now, no longer a forced workaround.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: XmlAttr { String name String value }

: Xml {
    i kind                  // 0 = text, 1 = element
    String text             // text content (kind 0)
    String tag              // element tag (kind 1)
    ( Vec XmlAttr ) attrs
    ( Vec Xml ) children
}

: | XmlErr { XmlSyntax XmlUnterminated XmlBadName XmlOther }

// Parse-state carrier: a parsed node plus the cursor after it. ok: 1 =
// node produced, 0 = none (hit `</` or EOF), -1 = error.
: __XmlNode { Xml node i endpos i ok }

@ xml_err_name XmlErr e → s {
    ^ ?? e {
        XmlSyntax → `XmlSyntax`
        XmlUnterminated → `XmlUnterminated`
        XmlBadName → `XmlBadName`
        XmlOther → `XmlOther`
    }
}

// ── Node helpers ──────────────────────────────────────────────────────

@ __xml_mk_text String txt → Xml {
    ^ @ Xml { 0 txt ( string_new ) ( vec_new [XmlAttr] ) ( vec_new [Xml] ) }
}

@ __xml_mk_elem String tag ( Vec XmlAttr ) attrs ( Vec Xml ) children → Xml {
    ^ @ Xml { 1 ( string_new ) tag attrs children }
}

@ __xml_empty → Xml {
    ^ ( __xml_mk_text ( string_new ) )
}

// ── Character classes / small helpers ─────────────────────────────────

@ __xml_is_space i c → b {
    ^ | | == c 32 == c 9 | == c 10 == c 13
}

@ __xml_is_name_start i c → b {
    ^ | | & >= c 65 <= c 90 & >= c 97 <= c 122 | == c 95 == c 58
}

@ __xml_is_name i c → b {
    ^ | ( __xml_is_name_start c ) | & >= c 48 <= c 57 | == c 45 == c 46
}

@ __xml_skip_ws s src i pos i n → i {
    : ~ i p pos
    ~ & < p n ( __xml_is_space ( nurl_str_get src p ) ) { = p + p 1 }
    ^ p
}

@ __xml_substr s src i start i len → String {
    : String out ( string_with_cap len )
    : ~ i k 0
    ~ < k len {
        ( string_push_char out ( nurl_str_get src + start k ) )
        = k + k 1
    }
    ^ out
}

// True when src[pos..] begins with `lit`.
@ __xml_match s src i pos i n s lit → b {
    : i ln ( nurl_str_len lit )
    ? > + pos ln n { ^ F } {}
    : ~ i k 0
    : ~ b ok T
    ~ & ok < k ln {
        ? != ( nurl_str_get src + pos k ) ( nurl_str_get lit k ) { = ok F } {}
        = k + k 1
    }
    ^ ok
}

// Find the index where `lit` next occurs at or after pos, or -1.
@ __xml_find_lit s src i pos i n s lit → i {
    : i ln ( nurl_str_len lit )
    : ~ i p pos
    : ~ i res -1
    ~ & < res 0 <= + p ln n {
        ? ( __xml_match src p n lit ) { = res p } { = p + p 1 }
    }
    ^ res
}

// ── Entity decoding (text + attribute values) ─────────────────────────

@ __xml_push_cp String out i cp → v {
    ? < cp 128 {
        ( string_push_char out cp )
    } {
        ? < cp 2048 {
            ( string_push_char out + 192 / cp 64 )
            ( string_push_char out + 128 & cp 63 )
        } {
            ? < cp 65536 {
                ( string_push_char out + 224 / cp 4096 )
                ( string_push_char out + 128 & / cp 64 63 )
                ( string_push_char out + 128 & cp 63 )
            } {
                ( string_push_char out + 240 / cp 262144 )
                ( string_push_char out + 128 & / cp 4096 63 )
                ( string_push_char out + 128 & / cp 64 63 )
                ( string_push_char out + 128 & cp 63 )
            }
        }
    }
}

// Decode src[start..start+len) into an owned String, expanding the five
// predefined entities and numeric char refs. An unrecognized `&…` is
// passed through verbatim (lenient).
@ __xml_decode_text s src i start i len → String {
    : String out ( string_with_cap len )
    : i end + start len
    : ~ i p start
    ~ < p end {
        : i c ( nurl_str_get src p )
        ? != c 38 {   // not '&'
            ( string_push_char out c )
            = p + p 1
        } {
            : i semi ( __xml_find_lit src p end `;` )
            ? | < semi 0 > - semi p 10 {
                ( string_push_char out 38 )
                = p + p 1
            } {
                : i inner + p 1
                ? == ( nurl_str_get src inner ) 35 {   // '#'
                    : ~ i cp 0
                    : ~ i q + inner 1
                    ? == ( nurl_str_get src q ) 120 {   // 'x' hex
                        = q + q 1
                        ~ < q semi {
                            : i hc ( nurl_str_get src q )
                            : i hv ? & >= hc 48 <= hc 57 - hc 48 ? & >= hc 97 <= hc 102 + 10 - hc 97 ? & >= hc 65 <= hc 70 + 10 - hc 65 0
                            = cp + * cp 16 hv
                            = q + q 1
                        }
                    } {
                        ~ < q semi {
                            : i dc ( nurl_str_get src q )
                            = cp + * cp 10 - dc 48
                            = q + q 1
                        }
                    }
                    ( __xml_push_cp out cp )
                    = p + semi 1
                } {
                    : b is_lt ( __xml_match src inner end `lt;` )
                    : b is_gt ( __xml_match src inner end `gt;` )
                    : b is_amp ( __xml_match src inner end `amp;` )
                    : b is_quot ( __xml_match src inner end `quot;` )
                    : b is_apos ( __xml_match src inner end `apos;` )
                    ? is_lt { ( string_push_char out 60 ) } {
                        ? is_gt { ( string_push_char out 62 ) } {
                            ? is_amp { ( string_push_char out 38 ) } {
                                ? is_quot { ( string_push_char out 34 ) } {
                                    ? is_apos { ( string_push_char out 39 ) } {
                                        ( string_push_char out 38 )
                                        : ~ i z inner
                                        ~ <= z semi { ( string_push_char out ( nurl_str_get src z ) ) = z + z 1 }
                                    }
                                }
                            }
                        }
                    }
                    = p + semi 1
                }
            }
        }
    }
    ^ out
}

// ── Entity encoding (serialize) ───────────────────────────────────────

@ __xml_encode_into String out s raw b in_attr → v {
    : i n ( nurl_str_len raw )
    : ~ i k 0
    ~ < k n {
        : i c ( nurl_str_get raw k )
        ? == c 60 { ( string_push_str out `&lt;` ) } {
            ? == c 62 { ( string_push_str out `&gt;` ) } {
                ? == c 38 { ( string_push_str out `&amp;` ) } {
                    ? & in_attr == c 34 { ( string_push_str out `&quot;` ) } {
                        ( string_push_char out c )
                    }
                }
            }
        }
        = k + k 1
    }
}

// ── Constructors / accessors ──────────────────────────────────────────

@ xml_elem s tag → Xml {
    ^ ( __xml_mk_elem ( string_from tag ) ( vec_new [XmlAttr] ) ( vec_new [Xml] ) )
}

@ xml_text s txt → Xml {
    ^ ( __xml_mk_text ( string_from txt ) )
}

@ xml_is_elem Xml x → b {
    ^ == . x kind 1
}

@ xml_is_text Xml x → b {
    ^ == . x kind 0
}

@ xml_tag Xml x → ?String {
    ? != . x kind 1 { ^ @ ?String { F # String 0 } } {}
    ^ @ ?String { T ( string_from ( string_data . x tag ) ) }
}

@ xml_text_value Xml x → ?String {
    ? != . x kind 0 { ^ @ ?String { F # String 0 } } {}
    ^ @ ?String { T ( string_from ( string_data . x text ) ) }
}

@ xml_child_count Xml x → i {
    ^ ( vec_len [Xml] . x children )
}

// BORROW: the returned Xml aliases the tree — do not free it.
@ xml_child_at Xml x i idx → ?Xml {
    ^ ( vec_get [Xml] . x children idx )
}

@ xml_attr Xml x s name → ?String {
    ? != . x kind 1 { ^ @ ?String { F # String 0 } } {}
    : i n ( vec_len [XmlAttr] . x attrs )
    : ~ i k 0
    : ~ i hit -1
    ~ < k n {
        : ?XmlAttr ao ( vec_get [XmlAttr] . x attrs k )
        ?? ao { T a → { ? == 1 ( nurl_str_eq ( string_data . a name ) name ) { = hit k } {} } F → {} }
        = k + k 1
    }
    ? < hit 0 { ^ @ ?String { F # String 0 } } {}
    : ?XmlAttr ho ( vec_get [XmlAttr] . x attrs hit )
    ^ ?? ho {
        T a → @ ?String { T ( string_from ( string_data . a value ) ) }
        F → @ ?String { F # String 0 }
    }
}

// First element child whose tag == `tag`. BORROW.
@ xml_find Xml x s tag → ?Xml {
    : i n ( vec_len [Xml] . x children )
    : ~ i k 0
    : ~ i hit -1
    ~ < k n {
        : ?Xml co ( vec_get [Xml] . x children k )
        ?? co {
            T c → { ? & == . c kind 1 == 1 ( nurl_str_eq ( string_data . c tag ) tag ) { = hit k } {} }
            F → {}
        }
        = k + k 1
    }
    ? < hit 0 { ^ @ ?Xml { F # Xml 0 } } {}
    ^ ( vec_get [Xml] . x children hit )
}

@ __xml_inner_into String out Xml x → v {
    ? == . x kind 0 {
        ( string_push_str out ( string_data . x text ) )
    } {
        : i n ( vec_len [Xml] . x children )
        : ~ i k 0
        ~ < k n {
            : ?Xml co ( vec_get [Xml] . x children k )
            ?? co { T c → ( __xml_inner_into out c ) F → {} }
            = k + k 1
        }
    }
}

@ xml_inner_text Xml x → String {
    : String out ( string_new )
    ( __xml_inner_into out x )
    ^ out
}

// ── Builders ──────────────────────────────────────────────────────────

@ xml_set_attr Xml x s name s val → v {
    ? != . x kind 1 { ^ v } {}
    : i n ( vec_len [XmlAttr] . x attrs )
    : ~ i k 0
    : ~ i hit -1
    ~ < k n {
        : ?XmlAttr ao ( vec_get [XmlAttr] . x attrs k )
        ?? ao { T a → { ? == 1 ( nurl_str_eq ( string_data . a name ) name ) { = hit k } {} } F → {} }
        = k + k 1
    }
    ? >= hit 0 {
        : ?XmlAttr ho ( vec_get [XmlAttr] . x attrs hit )
        ?? ho { T a → { ( string_free . a value ) = . a value ( string_from val ) ( vec_set [XmlAttr] . x attrs hit a ) } F → {} }
    } {
        ( vec_push [XmlAttr] . x attrs @ XmlAttr { ( string_from name ) ( string_from val ) } )
    }
}

@ xml_add_child Xml x Xml child → v {
    ? == . x kind 1 { ( vec_push [Xml] . x children child ) } { ( xml_free child ) }
}

// ── Free ──────────────────────────────────────────────────────────────

@ xml_free Xml x → v {
    ( string_free . x text )
    ( string_free . x tag )
    ( vec_free_with [XmlAttr] . x attrs \ XmlAttr a → v { ( string_free . a name ) ( string_free . a value ) } )
    ( vec_free_with [Xml] . x children \ Xml c → v { ( xml_free c ) } )
}

// ── Serialize ─────────────────────────────────────────────────────────

@ __xml_write Xml x String out → v {
    ? == . x kind 0 {
        ( __xml_encode_into out ( string_data . x text ) F )
    } {
        ( string_push_char out 60 )   // '<'
        ( string_push_str out ( string_data . x tag ) )
        : i an ( vec_len [XmlAttr] . x attrs )
        : ~ i ai 0
        ~ < ai an {
            : ?XmlAttr ao ( vec_get [XmlAttr] . x attrs ai )
            ?? ao {
                T a → {
                    ( string_push_char out 32 )
                    ( string_push_str out ( string_data . a name ) )
                    ( string_push_str out `="` )
                    ( __xml_encode_into out ( string_data . a value ) T )
                    ( string_push_char out 34 )   // '"'
                }
                F → {}
            }
            = ai + ai 1
        }
        : i cn ( vec_len [Xml] . x children )
        ? == cn 0 {
            ( string_push_str out `/>` )
        } {
            ( string_push_char out 62 )   // '>'
            : ~ i ci 0
            ~ < ci cn {
                : ?Xml co ( vec_get [Xml] . x children ci )
                ?? co { T c → ( __xml_write c out ) F → {} }
                = ci + ci 1
            }
            ( string_push_str out `</` )
            ( string_push_str out ( string_data . x tag ) )
            ( string_push_char out 62 )
        }
    }
}

@ xml_stringify Xml x → String {
    : String out ( string_new )
    ( __xml_write x out )
    ^ out
}

// ── Parser ────────────────────────────────────────────────────────────

// Skip whitespace, comments, PIs and the XML declaration. Returns the
// next significant position (or n).
@ __xml_skip_misc s src i pos i n → i {
    : ~ i p pos
    : ~ b again T
    ~ & again < p n {
        = p ( __xml_skip_ws src p n )
        ? ( __xml_match src p n `<!--` ) {
            : i close ( __xml_find_lit src + p 4 n `-->` )
            ? < close 0 { = p n } { = p + close 3 }
        } {
            ? & | ( __xml_match src p n `<?` ) ( __xml_match src p n `<!` ) ! ( __xml_match src p n `<![CDATA[` ) {
                : i close ( __xml_find_lit src p n `>` )
                ? < close 0 { = p n } { = p + close 1 }
            } {
                = again F
            }
        }
    }
    ^ p
}

// Parse attributes into `attrs`, starting just after the tag name.
// Returns the position of the tag-close marker ('>' or '/'), or -1.
@ __xml_parse_attrs s src i pos i n ( Vec XmlAttr ) attrs → i {
    : ~ i p pos
    : ~ b done F
    : ~ i res -1
    ~ & ! done < p n {
        = p ( __xml_skip_ws src p n )
        : i c ( nurl_str_get src p )
        ? | == c 62 == c 47 {   // '>' or '/'
            = res p
            = done T
        } {
            ? ! ( __xml_is_name_start c ) { = done T } {
                : i nstart p
                ~ & < p n ( __xml_is_name ( nurl_str_get src p ) ) { = p + p 1 }
                : String aname ( __xml_substr src nstart - p nstart )
                = p ( __xml_skip_ws src p n )
                ? != ( nurl_str_get src p ) 61 {   // '='
                    ( string_free aname )
                    = done T
                } {
                    = p + p 1
                    = p ( __xml_skip_ws src p n )
                    : i q ( nurl_str_get src p )
                    ? & != q 34 != q 39 {   // not a quote
                        ( string_free aname )
                        = done T
                    } {
                        = p + p 1
                        : i vstart p
                        ~ & < p n != ( nurl_str_get src p ) q { = p + p 1 }
                        ? >= p n {
                            ( string_free aname )
                            = done T
                        } {
                            : String aval ( __xml_decode_text src vstart - p vstart )
                            ( vec_push [XmlAttr] attrs @ XmlAttr { aname aval } )
                            = p + p 1   // skip closing quote
                        }
                    }
                }
            }
        }
    }
    ^ res
}

// Parse one element starting at the '<' at pos.
@ __xml_parse_element s src i pos i n → __XmlNode {
    : i nstart + pos 1
    ? ! ( __xml_is_name_start ( nurl_str_get src nstart ) ) {
        ^ @ __XmlNode { ( __xml_empty ) pos -1 }
    } {}
    : ~ i p nstart
    ~ & < p n ( __xml_is_name ( nurl_str_get src p ) ) { = p + p 1 }
    : String tag ( __xml_substr src nstart - p nstart )
    : ( Vec XmlAttr ) attrs ( vec_new [XmlAttr] )
    : i close ( __xml_parse_attrs src p n attrs )
    ? < close 0 {
        ( string_free tag )
        ( vec_free_with [XmlAttr] attrs \ XmlAttr a → v { ( string_free . a name ) ( string_free . a value ) } )
        ^ @ __XmlNode { ( __xml_empty ) pos -1 }
    } {}
    : ( Vec Xml ) children ( vec_new [Xml] )
    : ~ i after close
    ? == ( nurl_str_get src close ) 47 {   // '/>' self-closing
        = after + close 2
    } {
        : ~ i cp + close 1
        : ~ b cdone F
        : ~ b cerr F
        ~ & ! cdone < cp n {
            ? ( __xml_match src cp n `</` ) {
                = cdone T
            } {
                : __XmlNode nd ( __xml_parse_node src cp n )
                ? < . nd ok 0 {
                    = cerr T
                    = cdone T
                } {
                    ? == . nd ok 0 {
                        = cdone T
                    } {
                        ( vec_push [Xml] children . nd node )
                        = cp . nd endpos
                    }
                }
            }
        }
        ? cerr {
            ( string_free tag )
            ( vec_free_with [XmlAttr] attrs \ XmlAttr a → v { ( string_free . a name ) ( string_free . a value ) } )
            ( vec_free_with [Xml] children \ Xml c → v { ( xml_free c ) } )
            ^ @ __XmlNode { ( __xml_empty ) pos -1 }
        } {}
        : i gt ( __xml_find_lit src cp n `>` )
        ? < gt 0 { = after n } { = after + gt 1 }
    }
    ^ @ __XmlNode { ( __xml_mk_elem tag attrs children ) after 1 }
}

// Parse the next node (element, text, or CDATA) at pos. ok: 1 produced,
// 0 = at `</` or EOF (no node), -1 = error.
@ __xml_parse_node s src i pos i n → __XmlNode {
    : i p ( __xml_skip_misc src pos n )
    ? >= p n { ^ @ __XmlNode { ( __xml_empty ) p 0 } } {}
    ? ( __xml_match src p n `</` ) { ^ @ __XmlNode { ( __xml_empty ) p 0 } } {}
    ? ( __xml_match src p n `<![CDATA[` ) {
        : i cstart + p 9
        : i cend ( __xml_find_lit src cstart n `]]>` )
        ? < cend 0 { ^ @ __XmlNode { ( __xml_empty ) p -1 } } {}
        : String txt ( __xml_substr src cstart - cend cstart )
        ^ @ __XmlNode { ( __xml_mk_text txt ) + cend 3 1 }
    } {}
    ? == ( nurl_str_get src p ) 60 {   // '<' → element
        ^ ( __xml_parse_element src p n )
    } {}
    // text run up to the next '<'
    : i lt ( __xml_find_lit src p n `<` )
    : i tend ? < lt 0 n lt
    : String txt ( __xml_decode_text src p - tend p )
    ^ @ __XmlNode { ( __xml_mk_text txt ) tend 1 }
}

@ xml_parse s src → !Xml XmlErr {
    : i n ( nurl_str_len src )
    : i p ( __xml_skip_misc src 0 n )
    ? >= p n { ^ @ !Xml XmlErr { F @ XmlErr { XmlOther } } } {}
    ? != ( nurl_str_get src p ) 60 { ^ @ !Xml XmlErr { F @ XmlErr { XmlSyntax } } } {}
    : __XmlNode nd ( __xml_parse_element src p n )
    ? < . nd ok 0 {
        ( xml_free . nd node )
        ^ @ !Xml XmlErr { F @ XmlErr { XmlSyntax } }
    } {}
    ^ @ !Xml XmlErr { T . nd node }
}
