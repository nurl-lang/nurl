// verify_test.nu — the quality gate's ears, without a model or a transcriber.
//
// The gate scores what the transcriber heard against what the model was
// asked to say. Every case below is a spelling the transcriber actually
// produced for audio that was right, or an error it must still count as one.
//
//   NURL_STDLIB=<repo> ../../nurl.sh tests/verify_test.nu /tmp/t5v && /tmp/t5v

$ `stdlib/core/io.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `src/verify.nu`
$ `src/run.nu`

: ~ i g_pass 0

: ~ i g_fail 0

@ __t_check b ok s label → v {
    ? ok { ( nurl_print `  ok   ` ) = g_pass + g_pass 1 } { ( nurl_print `  FAIL ` ) = g_fail + g_fail 1 }
    ( nurl_print label )
    ( nurl_print `\n` )
}

@ __t_errors s ref s hyp i want → v {
    : i got ( f5_errors ref hyp )
    : String label ( string_from ref )
    ( string_push_str label ` | ` )
    ( string_push_str label hyp )
    ( string_push_str label ` → ` )
    ( string_push_int label got )
    ? == got want {} {
        ( string_push_str label ` (want ` )
        ( string_push_int label want )
        ( string_push_str label `)` )
    }
    ( __t_check == got want ( string_data label ) )
    ( string_free label )
}

@ __t_number i n s want → v {
    : String got ( f5_number_words n )
    : String label ( string_new )
    ( string_push_int label n )
    ( string_push_str label ` → ` )
    ( string_push_str label ( string_data got ) )
    ( __t_check != 0 ( nurl_str_eq ( string_data got ) want ) ( string_data label ) )
    ( string_free label )
    ( string_free got )
}

@ __t_lead s text i want → v {
    : i got ( _f5r_lead_split text )
    : String label ( string_from `lead split of "` )
    ( string_push_str label text )
    ( string_push_str label `" at ` )
    ( string_push_int label got )
    ( __t_check == got want ( string_data label ) )
    ( string_free label )
}

@ main → i {
    ( nurl_println `numbers in words` )
    ( __t_number 0 `nolla` )
    ( __t_number 7 `seitsemän` )
    ( __t_number 10 `kymmenen` )
    ( __t_number 15 `viisitoista` )
    ( __t_number 20 `kaksikymmentä` )
    ( __t_number 99 `yhdeksänkymmentäyhdeksän` )
    ( __t_number 100 `sata` )
    ( __t_number 101 `satayksi` )
    ( __t_number 250 `kaksisataaviisikymmentä` )
    ( __t_number 1000 `tuhat` )
    ( __t_number 2026 `kaksituhattakaksikymmentäkuusi` )
    ( __t_number 1500011 `miljoonaviisisataatuhattayksitoista` )
    ( __t_number 3000000 `kolmemiljoonaa` )

    ( nurl_println `spellings of the same audio: no error` )
    ( __t_errors `Lepakon kosto kaksituhatta kaksikymmentäkuusi.` `Lepakonkosto 2026.` 0 )
    ( __t_errors `Vapaat Äänet podcastin pariin` `Vapaat Äänet-podcastin pariin` 0 )
    ( __t_errors `elin ja talvehtimispaikkoja` `elin- ja talvehtimispaikkoja` 0 )
    ( __t_errors `sata kaksikymmentä` `120` 0 )
    ( __t_errors `Kyllä, niiden kaikuluotaus.` `KYLLÄ NIIDEN KAIKULUOTAUS` 0 )
    ( __t_errors `Heh, no tavallaan.` `Heh… no tavallaan.` 0 )
    ( __t_errors `Ne ovat – tai olivat – täällä.` `Ne ovat, tai olivat, täällä.` 0 )
    ( __t_errors `tuholaistorjujiamme` `tuholais torjujiamme` 0 )
    ( __t_errors `` `` 0 )

    ( nurl_println `errors that are errors` )
    ( __t_errors `Aihe on hyvin` `Ei he on hyvin` 2 )
    ( __t_errors `Vapaat Äänet podcastin pariin` `Vapaat Vänet-podcastin pariin` 1 )
    ( __t_errors `Juuri. Seuraavaksi ne tuo` `Seuraavaksi ne tuo` 1 )
    ( __t_errors `moi` `` 1 )
    ( __t_errors `` `moi` 1 )
    ( __t_errors `Heh, no tavallaan.` `Heh no tavallaan tai ei.` 2 )
    ( __t_errors `lepakon kosto` `lepakonkosto 2026-luvulla` 2 )

    ( nurl_println `the opening sentence a short line loses` )
    ( __t_lead `Juuri. Seuraavaksi ne tuo mukanaan.` 7 )
    ( __t_lead `Eipä kestä. Täytyykin mennä.` 0 )
    ( __t_lead `Kiitos itsellenne.` 0 )
    ( __t_lead `Tervetuloa jälleen Vapaat Äänet podcastin pariin. Tänään.` 0 )
    ( __t_lead `Mitä?  Ei mitään.` 8 )

    : String s ( string_from `verify_test: ` )
    ( string_push_int s g_pass )
    ( string_push_str s ` ok, ` )
    ( string_push_int s g_fail )
    ( string_push_str s ` failed` )
    ( nurl_println ( string_data s ) )
    ( string_free s )
    ^ ? > g_fail 0 1 0
}
