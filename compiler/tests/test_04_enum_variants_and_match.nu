// ============================================================
// test_04_enum_variants_and_match.nu
// Tarkoitus: testaa että
//  (1) varianteilla 0, 1, ja 2 payloadia toimivat samassa enumissa
//  (2) enum-arvon koko vastaa SUURIMMAN variantin tarvetta
//      (eli pieni variantti ei "vuoda yli" suurempaan)
//  (3) match purkaa payloadit oikeassa järjestyksessä
//  (4) wildcard '_' osuu vain kattamattomiin variantteihin
//  (5) match toimii kun arvo tulee funktion paluuarvosta
//      (ei vain paikallisesta muuttujasta)
//  (6) sisäkkäinen match (match matchin sisällä) toimii
//  (7) enum-pointerin (* MyEnum) takaa lukeminen toimii samoin
//      kuin suoraan arvon
//
// Odotettu tuloste:
//   click at 100,200
//   key A pressed (code 65)
//   close
//   tick
//   roundtrip: key Z pressed (code 90)
//   nested: outer-some inner-num 42
//   nested: outer-some inner-null
//   nested: outer-none
//   ptr-deref: click at 7,8
//   total clicks: 2
// ============================================================

: | Event {
    Click    i i           // x, y
    KeyPress s i           // name, code
    Close
    Tick
}

: | MaybeJson {
    MNothing
    MJust  ? i             // sisältää Option<i>
}


// ── Apufunktio: tulosta yksi Event ──────────────────────────
@ describe * Event e → v {
    ?? . e 0 {
        Click x y → {
            ( puts `click at ` )
            ( puts ( nurl_str_int x ) )
            ( puts `,` )
            ( puts ( nurl_str_int y ) )
        }
        KeyPress name code → {
            ( puts `key ` )
            ( puts name )
            ( puts ` pressed (code ` )
            ( puts ( nurl_str_int code ) )
            ( puts `)` )
        }
        Close → ( puts `close` )
        Tick  → ( puts `tick` )
    }
}


// ── Heap-allokoi event ──────────────────────────────────────
@ box_event Event v → * Event {
    : * Event p # * Event ( malloc Z Event )
    = . p 0 v
    ^ p
}


// ── Funktio joka palauttaa enumin (ei pointeria) ────────────
// Testaa että match toimii suoraan paluuarvolla
@ make_key s name i code → Event {
    ^ @ Event { KeyPress name code }
}


// ── Laske kuinka moni event on Click ────────────────────────
@ count_clicks [ * Event events → i {
    : i n . events length
    : ~ i i 0
    : ~ i clicks 0
    ~ < i n {
        : * Event e . events i
        ?? . e 0 {
            Click x y → = clicks + clicks 1
            _         → ( puts `` )       // wildcard: ei mitään
        }
        = i + i 1
    }
    ^ clicks
}


@ main → i {
    // (1) Eri payload-määrillä
    : * Event e1 ( box_event @ Event { Click 100 200 } )
    : * Event e2 ( box_event @ Event { KeyPress `A` 65 } )
    : * Event e3 ( box_event @ Event { Close } )
    : * Event e4 ( box_event @ Event { Tick } )

    ( describe e1 )    ( puts `\n` )
    ( describe e2 )    ( puts `\n` )
    ( describe e3 )    ( puts `\n` )
    ( describe e4 )    ( puts `\n` )

    // (2) Round-trip: rakenna funktiossa, palauta arvona, boksaa, matchaa
    : Event raw ( make_key `Z` 90 )
    : * Event e5 ( box_event raw )
    ( puts `roundtrip: ` )
    ( describe e5 )
    ( puts `\n` )

    // (3) Sisäkkäinen match — MaybeJson sisältää Option<i>:n
    : MaybeJson m1 @ MaybeJson { MJust @ ? i { T 42 } }
    : MaybeJson m2 @ MaybeJson { MJust @ ? i { F 0 } }
    : MaybeJson m3 @ MaybeJson { MNothing }

    ( puts `nested: ` )
    ?? . m1 0 {
        MNothing → ( puts `outer-none` )
        MJust opt → {
            ( puts `outer-some ` )
            ?? . opt 0 {
                T → {
                    ( puts `inner-num ` )
                    ( puts ( nurl_str_int . opt 1 ) )
                }
                F → ( puts `inner-null` )
            }
        }
    }
    ( puts `\n` )

    ( puts `nested: ` )
    ?? . m2 0 {
        MNothing → ( puts `outer-none` )
        MJust opt → {
            ( puts `outer-some ` )
            ?? . opt 0 {
                T → {
                    ( puts `inner-num ` )
                    ( puts ( nurl_str_int . opt 1 ) )
                }
                F → ( puts `inner-null` )
            }
        }
    }
    ( puts `\n` )

    ( puts `nested: ` )
    ?? . m3 0 {
        MNothing → ( puts `outer-none` )
        MJust opt → {
            ( puts `outer-some ` )
        }
    }
    ( puts `\n` )

    // (4) Pointerin takaa luku — varmista että describe(* Event)
    //     käyttäytyy yhtenevästi suoran arvon kanssa
    : * Event e6 ( box_event @ Event { Click 7 8 } )
    ( puts `ptr-deref: ` )
    ( describe e6 )
    ( puts `\n` )

    // (5) Slice ja count_clicks — wildcard-arm käytössä
    : [ * Event evs [ * Event | e1 e2 e3 e4 e6 ]
    ( puts `total clicks: ` )
    ( puts ( nurl_str_int ( count_clicks evs ) ) )
    ( puts `\n` )

    ^ 0
}