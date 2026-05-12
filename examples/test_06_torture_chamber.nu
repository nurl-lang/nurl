// ============================================================
// test_06_torture_chamber.nu
// Tarkoitus: Testata AST:n rakentumisen, tyyppipäättelyn ja muistilayoutin
// ääritapauksia v0.8 kieliopin sallimissa puitteissa.
//
// 1. Array of closures (funktio-osoittimet heapissa)
// 2. Prefix-operaattoreiden syvä sisäkkäisyys ilman sulkeita
// 3. Ketjutettu member_expr ja set_stmt
// 4. Try-operaattorin (\) ja complement-operaattorin (~) disambiguaatio
// ============================================================

: | Token {
    Num i
    Op s
    Nested ? [ Token
}

: State {
    [ Token tokens
    i pos
}

@ get_multiplier i factor → (@ i i) {
    ^ \ i x → i { ^ * x factor }
}

@ main → i {
    ( nurl_print `== Torture chamber ==\n` )

    // 1. Slice of Closures: Kääntäjän tulee osata varata oikea tila
    // closure-structeille { function_ptr, env_ptr } slicen sisään.
    : [ (@ i i) ops [ (@ i i) | ( get_multiplier 2 ) ( get_multiplier 3 ) ]
    ( nurl_print `[1] slice-of-closures ops.length=` )
    ( nurl_print ( nurl_str_int . ops length ) )
    ( nurl_print `\n` )

    // Lexical disambiguation -testi: mutatoitava muuttuja (~), jonka
    // alkuarvo on bittitason komplementti (~) nollasta.
    : ~ i mask ~ 0

    // 2. Prefix-helvetti: Yhdistetään cond_expr (?), bin_expr (>),
    // match_expr (??) ja complement_expr (~) peräkkäin ilman sulkeita.
    // Oikea jäsennyspuu: result = (mask > 0) ? (match t {...}) : (~mask)
    : | Token t @ Token { Num 42 }
    : ~ i result 0

    = result ? > mask 0
        ?? t {
            Num n → * n 2
            Op  s → 0
            _     → ~ mask
        }
        ~ mask
    ( nurl_print `[2] mask=` )
    ( nurl_print ( nurl_str_int mask ) )
    ( nurl_print ` result-after-match=` )
    ( nurl_print ( nurl_str_int result ) )
    ( nurl_print `\n` )

    // 3. Ketjutettu field access & mutaatio
    // Luodaan tila, jossa on slice enum-arvoja
    : State st @ State { [ Token | @ Token { Num 1 } @ Token { Op `+` } ] 0 }

    // Haetaan indeksi erilliseen muuttujaan (katso huomio 2 alempaa)
    : i current_pos . st pos

    // Kirjoitetaan arvo structin sisällä olevaan sliceen.
    // Jäsennys: set_stmt(=) -> member_expr(.) -> member_expr(.) -> expr(@)
    // Toisin sanoen: st.tokens[current_pos] = Token::Num(99)
    = . . st tokens current_pos @ Token { Num 99 }
    ( nurl_print `[3] st.pos=` )
    ( nurl_print ( nurl_str_int current_pos ) )
    ( nurl_print ` st.tokens.length=` )
    ( nurl_print ( nurl_str_int . . st tokens length ) )
    ( nurl_print `\n` )

    // 4. Try-operaattori (\) epätavallisessa paikassa: loopin alustuksessa.
    // Purkaa 7:n suoraan loop_cnt-muuttujaan.
    : ? i opt_num @ ? i { T 7 }
    : ~ i loop_cnt \ opt_num
    ( nurl_print `[4] loop_cnt start=` )
    ( nurl_print ( nurl_str_int loop_cnt ) )
    ( nurl_print `\n` )

    ~ > loop_cnt 0 {
        = loop_cnt - loop_cnt 1
        // Nostetaan tulosta, jotta sitä käytetään
        = result + result loop_cnt
    }

    ( nurl_print `[final] result=` )
    ( nurl_print ( nurl_str_int result ) )
    ( nurl_print `\n` )
    ^ result
}