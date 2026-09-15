// packages/f5tts/src/registry.nu — which models this machine can speak with.
//
// Two kinds, and a request naming either by id gets the same answer:
//
//   LOCAL — a directory under ~/.f5tts/models holding a checkpoint and its
//           vocab.txt. This is where a finetune lands, or a training run's
//           output, or a file somebody copied off another machine. The id is
//           the directory's name.
//
//   KNOWN — a Hugging Face reference this package ships the address of. The
//           id is a short name; asking for it fetches the checkpoint and its
//           vocabulary into the shared ~/.nurl/models cache the first time
//           and costs nothing after that.
//
// A fresh machine has no local models and every known one available, which is
// the state this is designed around: `f5tts serve` on a machine that has just
// installed it works, and the first request pays the download.

$ `stdlib/core/io.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/path.nu`
$ `deps/hub/src/store.nu`
$ `deps/hub/src/hf.nu`
$ `deps/hub/src/pull.nu`
$ `deps/hub/src/hub.nu`
$ `store.nu`

: F5Entry {
    String id
    String ckpt  // a local path, or a Hugging Face ref
    String vocab  // the same
    b local
    b cached  // a known model whose files are already on the machine
}

@ f5_entry_free F5Entry e → v {
    ( string_free . e id )
    ( string_free . e ckpt )
    ( string_free . e vocab )
}

@ __f5g_push ( Vec F5Entry ) v s id s ckpt s vocab b local b cached → v {
    ( vec_push [F5Entry] v @ F5Entry {
        ( string_from id ) ( string_from ckpt ) ( string_from vocab ) local cached
    } )
}

// The addresses this package knows. Each names ONE file in a repo, so the
// hub fetches a file rather than a whole tree — an F5-TTS repo carries every
// release it ever made and most of them are not wanted.
@ f5_known ( Vec F5Entry ) out → v {
    ( __f5g_push out `F5TTS_v1_Base`
    `SWivid/F5-TTS/F5TTS_v1_Base/model_1250000.safetensors`
    `SWivid/F5-TTS/F5TTS_v1_Base/vocab.txt` F F )
    ( __f5g_push out `F5TTS_Base`
    `SWivid/F5-TTS/F5TTS_Base/model_1200000.safetensors`
    `SWivid/F5-TTS/F5TTS_Base/vocab.txt` F F )
    ( __f5g_push out `E2TTS_Base`
    `SWivid/E2-TTS/E2TTS_Base/model_1200000.safetensors`
    `SWivid/E2-TTS/E2TTS_Base/vocab.txt` F F )
    ( __f5g_push out `Finnish_Model_v2_20250323`
    `AsmoKoskinen/F5-TTS_Finnish_Model/model_commonvoice_fi_librivox_fi_vox_populi_fi_20250323/model_last_20250323.safetensors`
    `AsmoKoskinen/F5-TTS_Finnish_Model/model_commonvoice_fi_librivox_fi_vox_populi_fi_20250323/vocab.txt` F F )
    ( __f5g_push out `Finnish_Model_v1_20241217`
    `AsmoKoskinen/F5-TTS_Finnish_Model/model_commonvoice_fi_librivox_fi_vox_populi_fi_20241217/model_last_20241217.safetensors`
    `AsmoKoskinen/F5-TTS_Finnish_Model/model_commonvoice_fi_librivox_fi_vox_populi_fi_20241217/vocab.txt` F F )
}

@ __f5g_find_ckpt s dir → String {
    : String found ( string_new )
    ?? ( dir_list dir ) {
        T names → {
            : ~ i k 0
            ~ < k ( vec_len [String] names ) {
                ?? ( vec_get [String] names k ) {
                    T nm → {
                        ? == 0 ( string_len found ) {
                            : b is ? ( string_ends_with nm `.safetensors` ) T
                            ? ( string_ends_with nm `.pt` ) T
                            ? ( string_ends_with nm `.pth` ) T F
                            ? is {
                                ( string_push_str found dir )
                                ( string_push_char found 47 )
                                ( string_push_str found ( string_data nm ) )
                            } {}
                        } {}
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
    ^ found
}

// Everything this machine can speak with right now, local first.
@ f5_registry s models_dir → ( Vec F5Entry ) {
    : ( Vec F5Entry ) out ( vec_new [F5Entry] )
    ?? ( dir_list models_dir ) {
        T names → {
            : ~ i k 0
            ~ < k ( vec_len [String] names ) {
                ?? ( vec_get [String] names k ) {
                    T nm → {
                        : String dir ( string_from models_dir )
                        ( string_push_char dir 47 )
                        ( string_push_str dir ( string_data nm ) )
                        : String ck ( __f5g_find_ckpt ( string_data dir ) )
                        ? > ( string_len ck ) 0 {
                            : String vo ( string_from ( string_data dir ) )
                            ( string_push_str vo `/vocab.txt` )
                            ? ( file_exists ( string_data vo ) ) {
                                ( __f5g_push out ( string_data nm ) ( string_data ck )
                                ( string_data vo ) T T )
                            } {}
                            ( string_free vo )
                        } {}
                        ( string_free ck )
                        ( string_free dir )
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
    : ( Vec F5Entry ) known ( vec_new [F5Entry] )
    ( f5_known known )
    : ~ i k 0
    ~ < k ( vec_len [F5Entry] known ) {
        ?? ( vec_get [F5Entry] known k ) {
            T e → {
                // a local model of the same name wins: it is the one somebody
                // put on this machine on purpose
                ? ( f5_registry_has out ( string_data . e id ) ) {} {
                    : b have ?? ( hub_path ( string_data . e ckpt ) ) {
                        T p → { ( string_free p ) T }
                        F → { F }
                    }
                    ( __f5g_push out ( string_data . e id ) ( string_data . e ckpt )
                    ( string_data . e vocab ) F have )
                }
                ( f5_entry_free e )
            }
            F → {}
        }
        = k + k 1
    }
    ( vec_free [F5Entry] known )
    ^ out
}

@ f5_registry_has ( Vec F5Entry ) v s id → b {
    : ~ i k 0
    ~ < k ( vec_len [F5Entry] v ) {
        ?? ( vec_get [F5Entry] v k ) {
            T e → { ? != 0 ( nurl_str_eq ( string_data . e id ) id ) { ^ T } {} }
            F → {}
        }
        = k + k 1
    }
    ^ F
}

@ f5_registry_free ( Vec F5Entry ) v → v {
    : ~ i k 0
    ~ < k ( vec_len [F5Entry] v ) {
        ?? ( vec_get [F5Entry] v k ) { T e → { ( f5_entry_free e ) } F → {} }
        = k + k 1
    }
    ( vec_free [F5Entry] v )
}

// Resolve an id to the two local paths a model needs, fetching if the id
// names a known model this machine has not pulled yet. Empty ckpt = no such
// model, or the fetch failed (which is reported on stderr).
@ f5_registry_resolve s models_dir s id String ckpt_out String vocab_out → b {
    : ( Vec F5Entry ) reg ( f5_registry models_dir )
    : ~ b ok F
    : ~ i k 0
    ~ < k ( vec_len [F5Entry] reg ) {
        ?? ( vec_get [F5Entry] reg k ) {
            T e → {
                ? & ! ok != 0 ( nurl_str_eq ( string_data . e id ) id ) {
                    ? . e local {
                        ( string_push_str ckpt_out ( string_data . e ckpt ) )
                        ( string_push_str vocab_out ( string_data . e vocab ) )
                        = ok T
                    } {
                        // a known model: the hub turns the reference into a path,
                        // downloading it the first time
                        ?? ( hub_get ( string_data . e ckpt ) ) {
                            T cp → {
                                ?? ( hub_get ( string_data . e vocab ) ) {
                                    T vp → {
                                        ( string_push_str ckpt_out ( string_data cp ) )
                                        ( string_push_str vocab_out ( string_data vp ) )
                                        = ok T
                                        ( string_free vp )
                                    }
                                    F ve → {
                                        ( nurl_eprintln ( string_data ve ) )
                                        ( string_free ve )
                                    }
                                }
                                ( string_free cp )
                            }
                            F ce → {
                                ( nurl_eprintln ( string_data ce ) )
                                ( string_free ce )
                            }
                        }
                    }
                } {}
            }
            F → {}
        }
        = k + k 1
    }
    ( f5_registry_free reg )
    ^ ok
}
