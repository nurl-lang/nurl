// text_test.nu — the text front-end's gate.
//
// F5-TTS's `convert_char_to_pinyin` is jieba segmentation plus a space in
// front of every multi-character ASCII segment, and on Latin-script text that
// combination does something surprising: it breaks words at every non-ASCII
// letter and then inserts a space into the break. "Yöllä" is read as
// "Yö llä". The Finnish checkpoint was fine-tuned through exactly that, so
// these expectations are the model's own spelling of the language, not a
// convenience.
//
// Every expectation below was produced by the reference implementation
// (rjieba + f5_tts.model.utils.convert_char_to_pinyin) over the vocabulary
// this test writes: one character per line, the line number is the id.
//
//   NURL_STDLIB=<repo> ../../nurl.sh tests/text_test.nu /tmp/t5 && /tmp/t5 <workdir>

$ `stdlib/core/io.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/fs.nu`
$ `src/text.nu`

: ~ i g_pass 0

: ~ i g_fail 0

@ __t_check b ok s label → v {
    ? ok { ( nurl_print `  ok   ` ) = g_pass + g_pass 1 } { ( nurl_print `  FAIL ` ) = g_fail + g_fail 1 }
    ( nurl_print label )
    ( nurl_print `\n` )
}

@ __t_geti ( Vec i ) v i k → i {
    ?? ( vec_get [i] v k ) { T x → { ^ x } F → { ^ -1 } }
}

// " " then every printable ASCII then äöåÄÖÅ — one per line, id = line number.
@ __t_vocab_text → String {
    : String s ( string_new )
    ( string_push_char s 32 )
    ( string_push_char s 10 )
    : ~ i c 33
    ~ < c 127 {
        ( string_push_char s c )
        ( string_push_char s 10 )
        = c + c 1
    }
    // ä ö å Ä Ö Å as UTF-8: c3 a4, c3 b6, c3 a5, c3 84, c3 96, c3 85
    : ( Vec i ) tails ( vec_new [i] )
    ( vec_push [i] tails 164 )
    ( vec_push [i] tails 182 )
    ( vec_push [i] tails 165 )
    ( vec_push [i] tails 132 )
    ( vec_push [i] tails 150 )
    ( vec_push [i] tails 133 )
    : ~ i k 0
    ~ < k 6 {
        ( string_push_char s 195 )
        ( string_push_char s ( __t_geti tails k ) )
        ( string_push_char s 10 )
        = k + k 1
    }
    ( vec_free [i] tails )
    ^ s
}

@ __t_case * F5Vocab v s text s want → v {
    : ( Vec i ) ids ( vec_new [i] )
    ( f5_text_ids v text ids )
    : String got ( string_new )
    : i n ( vec_len [i] ids )
    : ~ i k 0
    ~ < k n {
        ? > k 0 { ( string_push_char got 44 ) } {}
        ( string_push_int got ( __t_geti ids k ) )
        = k + k 1
    }
    : b ok ( string_eq got ( string_from want ) )
    ( __t_check ok text )
    ? ok {} {
        ( nurl_print `       want ` ) ( nurl_println want )
        ( nurl_print `       got  ` ) ( nurl_println ( string_data got ) )
    }
    ( string_free got )
    ( vec_free [i] ids )
}

@ __t_chunks s text i mx s want → v {
    : ( Vec String ) cs ( f5_chunk_text text mx )
    : String got ( string_new )
    : i n ( vec_len [String] cs )
    : ~ i k 0
    ~ < k n {
        ( string_push_char got 124 )
        ?? ( vec_get [String] cs k ) { T c → { ( string_push_str got ( string_data c ) ) } F → {} }
        = k + k 1
    }
    : b ok ( string_eq got ( string_from want ) )
    ( __t_check ok text )
    ? ok {} {
        ( nurl_print `       want ` ) ( nurl_println want )
        ( nurl_print `       got  ` ) ( nurl_println ( string_data got ) )
    }
    ( string_free got )
    : ( @ v String ) drop_c \ String s → v { ( string_free s ) }
    ( vec_free_with [String] cs drop_c )
}

@ main → i {
    : ~ s work `/tmp`
    ? > ( nurl_argv_count ) 1 { = work ( nurl_argv_get 1 ) } {}
    : String vpath ( string_from work )
    ( string_push_str vpath `/f5tts_text_test_vocab.txt` )
    : String vtxt ( __t_vocab_text )
    ?? ( write_file ( string_data vpath ) ( string_data vtxt ) ) {
        T _ → {}
        F _e → {
            ( nurl_eprintln `text_test: cannot write the temporary vocabulary` )
            ^ 1
        }
    }
    ( string_free vtxt )

    ?? ( f5_vocab_load ( string_data vpath ) ) {
        T v → {
            ( nurl_println `vocabulary` )
            ( __t_check == ( f5_vocab_size v ) 101 `101 entries` )

            ( nurl_println `characters (against the reference front-end)` )
            ( __t_case v `Yöllä hiljaisessa mökissä.` `57,96,0,76,76,95,0,72,73,76,74,65,73,83,69,83,83,65,0,77,96,0,75,73,83,83,95,14` )
            ( __t_case v `Hei.` `40,69,73,14` )
            ( __t_case v `Tämä on testi; katsotaan, miten se menee.` `52,95,77,95,0,79,78,0,84,69,83,84,73,12,0,75,65,84,83,79,84,65,65,78,12,0,77,73,84,69,78,0,83,69,0,77,69,78,69,69,14` )
            ( __t_case v `Åke söi pöydällä 3 omenaa.` `100,0,75,69,0,83,96,73,0,80,96,0,89,68,95,0,76,76,95,0,19,0,79,77,69,78,65,65,14` )
            ( __t_case v `aaa-bbb_ccc` `65,65,65,13,0,66,66,66,63,0,67,67,67` )
            ( __t_case v `x1 y2.5 z%` `88,17,0,89,18,14,21,0,90,5` )
            ( __t_case v `c# ja C++ ja AT&T` `67,3,0,74,65,0,35,11,11,0,74,65,0,33,52,6,52` )
            ( __t_case v `Han sanoi: "ei koskaan", ja lahti.` `40,65,78,0,83,65,78,79,73,26,0,2,69,73,0,75,79,83,75,65,65,78,2,12,0,74,65,0,76,65,72,84,73,14` )

            ( nurl_println `chunking` )
            ( __t_chunks `Yksi. Kaksi. Kolme.` 12 `|Yksi. Kaksi.|Kolme.` )
            ( __t_chunks `Yksi. Kaksi. Kolme.` 40 `|Yksi. Kaksi. Kolme.` )
            ( __t_chunks `Ei taukoja tässä` 10 `|Ei taukoja tässä` )
            ( __t_chunks `Hei! Mitä kuuluu? Kaikki hyvin, kiitos.` 20 `|Hei! Mitä kuuluu?|Kaikki hyvin,|kiitos.` )
            ( __t_chunks `Yöllä hiljaisessa mökissä kuuntelin, kuinka tuuli ujeltaa ja järven aallot lyövät rantaan.` 40 `|Yöllä hiljaisessa mökissä kuuntelin,|kuinka tuuli ujeltaa ja järven aallot lyövät rantaan.` )

            ( f5_vocab_free v )
        }
        F e → {
            ( nurl_eprintln ( string_data e ) )
            ( string_free e )
            ^ 1
        }
    }
    ?? ( file_delete ( string_data vpath ) ) { T _ → {} F _e → {} }
    ( string_free vpath )

    ( nurl_print `\n` )
    ( nurl_print `passed ` )
    ( nurl_print_int g_pass )
    ( nurl_print `, failed ` )
    ( nurl_print_int g_fail )
    ( nurl_print `\n` )
    ? > g_fail 0 { ^ 1 } {}
    ^ 0
}
