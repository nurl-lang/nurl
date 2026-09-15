// packages/f5tts/src/store.nu — where a machine that has nothing keeps things.
//
// Installed from the registry onto a fresh machine, f5tts has no models and no
// voices. It makes itself somewhere to put them:
//
//   ~/.f5tts/voices/<id>/config.json   the transcript
//   ~/.f5tts/voices/<id>/reference.wav the recording the voice IS
//   ~/.f5tts/models/<id>/…             a checkpoint and its vocab.txt
//
// $F5TTS_HOME moves the lot. Models named as Hugging Face references are not
// copied here at all — they go to the shared ~/.nurl/models cache through
// packages/hub, so whisper, embed and f5tts share one copy of anything they
// happen to share. This directory is for what the machine ITSELF has: voices
// somebody recorded, and checkpoints somebody trained or downloaded by hand.

$ `stdlib/core/io.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/path.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/json.nu`

@ f5_home → String {
    ?? ( env_get `F5TTS_HOME` ) {
        T h → { ? > ( string_len h ) 0 { ^ h } { ( string_free h ) } }
        F → {}
    }
    : ~ String base ( string_new )
    ?? ( env_get `HOME` ) {
        T h → { ( string_push_str base ( string_data h ) ) ( string_free h ) }
        F → { ( string_push_char base 46 ) }
    }
    ( string_push_str base `/.f5tts` )
    ^ base
}

@ f5_voices_dir → String {
    : String p ( f5_home )
    ( string_push_str p `/voices` )
    ^ p
}

@ f5_models_dir → String {
    : String p ( f5_home )
    ( string_push_str p `/models` )
    ^ p
}

// Make them, quietly, every time the program starts. A directory that is
// already there is not an error, and a directory that cannot be made is
// reported once rather than at every use.
@ __f5st_need s path → b {
    ? ( file_exists path ) { ^ T } {}
    ?? ( dir_create path ) { T _ → {} F _e → {} }
    ^ ( file_exists path )
}

// Creating a directory that is already there is not a failure, and this runs
// on every start: only a directory that is still ABSENT afterwards is worth
// saying anything about.
@ f5_ensure_dirs → b {
    : String h ( f5_home )
    : String v ( f5_voices_dir )
    : String m ( f5_models_dir )
    : ~ b ok ( __f5st_need ( string_data h ) )
    = ok & ok ( __f5st_need ( string_data v ) )
    = ok & ok ( __f5st_need ( string_data m ) )
    ? ok {} {
        ( nurl_eprint `f5tts: cannot create ` )
        ( nurl_eprintln ( string_data h ) )
    }
    ( string_free h )
    ( string_free v )
    ( string_free m )
    ^ ok
}

// A name that may be joined onto a directory the server owns: a plain
// identifier, no separator, no dots, nothing a request could walk out of.
@ f5_id_ok s id → b {
    : i n ( nurl_str_len id )
    ? & > n 0 <= n 128 {} { ^ F }
    : ~ i k 0
    ~ < k n {
        : i c ( nurl_str_get id k )
        ? | == c 47 == c 92 { ^ F } {}
        ? == c 46 { ^ F } {}
        ? < c 33 { ^ F } {}
        = k + k 1
    }
    ^ T
}

@ f5_voice_path s voices_dir s id → String {
    : String p ( string_from voices_dir )
    ( string_push_char p 47 )
    ( string_push_str p id )
    ^ p
}

// The transcript a voice directory carries, or empty.
@ f5_voice_text s dir → String {
    : String cfg ( string_from dir )
    ( string_push_str cfg `/config.json` )
    : ~ String txt ( string_new )
    ?? ( read_file ( string_data cfg ) ) {
        T js → {
            ?? ( json_parse ( string_data js ) ) {
                T root → {
                    ?? ( json_obj_get root `ref_text` ) {
                        T node → { ( string_push_str txt ( json_as_str node ) ) }
                        F → {}
                    }
                    ( json_free root )
                }
                F _e → {}
            }
            ( string_free js )
        }
        F _e → {}
    }
    ( string_free cfg )
    ^ txt
}

// Write a voice: the directory, the transcript, and the recording as it
// arrived. Returns an empty string on success or the reason on failure.
@ f5_voice_write s voices_dir s id s ref_text ( Vec u ) wav → String {
    ? ( f5_id_ok id ) {} { ^ ( string_from `a voice id must be a plain name: no separator, no dots` ) }
    ? > ( vec_len [u] wav ) 44 {} { ^ ( string_from `the recording is empty or not a wav` ) }
    : String dir ( f5_voice_path voices_dir id )
    ?? ( dir_create ( string_data dir ) ) { T _ → {} F _e → {} }
    : String wp ( string_from ( string_data dir ) )
    ( string_push_str wp `/reference.wav` )
    : ~ String err ( string_new )
    ?? ( write_file_bytes ( string_data wp ) wav ) {
        T _ → {}
        F _e → { ( string_push_str err `cannot write the recording` ) }
    }
    ( string_free wp )
    ? == 0 ( string_len err ) {
        : Json o ( json_obj_new )
        : b _n ( json_obj_set o `name` ( json_str_lit id ) )
        : b _t ( json_obj_set o `ref_text` ( json_str_lit ref_text ) )
        : String js ( json_stringify o )
        ( json_free o )
        : String cp ( string_from ( string_data dir ) )
        ( string_push_str cp `/config.json` )
        ?? ( write_file ( string_data cp ) ( string_data js ) ) {
            T _ → {}
            F _e → { ( string_push_str err `cannot write config.json` ) }
        }
        ( string_free cp )
        ( string_free js )
    } {}
    ( string_free dir )
    ^ err
}

@ f5_voice_delete s voices_dir s id → b {
    ? ( f5_id_ok id ) {} { ^ F }
    : String dir ( f5_voice_path voices_dir id )
    : ~ b ok T
    : String wp ( string_from ( string_data dir ) )
    ( string_push_str wp `/reference.wav` )
    ?? ( file_delete ( string_data wp ) ) { T _ → {} F _e → {} }
    ( string_free wp )
    : String cp ( string_from ( string_data dir ) )
    ( string_push_str cp `/config.json` )
    ?? ( file_delete ( string_data cp ) ) { T _ → {} F _e → {} }
    ( string_free cp )
    : String sp ( string_from ( string_data dir ) )
    ( string_push_str sp `/sample.wav` )
    ?? ( file_delete ( string_data sp ) ) { T _ → {} F _e → {} }
    ( string_free sp )
    ?? ( dir_remove ( string_data dir ) ) { T _ → {} F _e → { = ok F } }
    ( string_free dir )
    ^ ok
}

// Every voice directory that actually holds a recording.
@ f5_voice_list s voices_dir → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    ?? ( dir_list voices_dir ) {
        T names → {
            : ~ i k 0
            ~ < k ( vec_len [String] names ) {
                ?? ( vec_get [String] names k ) {
                    T nm → {
                        : String wp ( f5_voice_path voices_dir ( string_data nm ) )
                        ( string_push_str wp `/reference.wav` )
                        ? ( file_exists ( string_data wp ) ) {
                            ( vec_push [String] out ( string_clone nm ) )
                        } {}
                        ( string_free wp )
                    }
                    F → {}
                }
                = k + k 1
            }
            : ( @ v String ) drop_s \ String s → v { ( string_free s ) }
            ( vec_free_with [String] names drop_s )
        }
        F _e → {}
    }
    ^ out
}
