// packages/f5tts/src/registry.nu — which models this machine can speak with.
//
// There is no built-in catalogue. This package names no checkpoint, ships no
// list of "known" models and has no default one, because a speech model is a
// choice about a language, a voice and a licence, and none of those are this
// program's to make. A model is named in one of three ways and they are tried
// in that order:
//
//   A PATH        an existing file or a directory holding a checkpoint and a
//                 vocab.txt. Whatever is on the disk.
//
//   A LOCAL ID    the name of a directory under ~/.f5tts/models. This is
//                 where a fine-tune lands, or a training run's output, or a
//                 file copied off another machine. `GET /models` lists these.
//
//   A REFERENCE   owner/repo/path-to-file, which the hub fetches into the
//                 shared ~/.nurl/models cache the first time and costs
//                 nothing after that. The vocabulary is taken to be
//                 `vocab.txt` beside the checkpoint in the same repository,
//                 which is how every F5-TTS release is laid out; name it with
//                 --vocab when it is not.
//
// A fresh machine has no local models and can reach any reference, which is
// the state this is designed around: `f5tts serve --model <reference>` on a
// machine that has just installed it works, and the first request pays the
// download.

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
    String ckpt  // a local path, or a Hugging Face reference
    String vocab  // the same
    b local  // a directory under the models dir rather than a reference
    b cached  // the files are on this machine already
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

// An owner/repo/file reference rather than a plain name: a separator makes it
// one, and `f5_id_ok` has already refused the separator to a local id, so the
// two can never be confused.
@ f5_is_reference s id → b {
    : i n ( nurl_str_len id )
    : ~ i k 0
    ~ < k n {
        : i c ( nurl_str_get id k )
        ? == c 47 { ^ T } {}
        = k + k 1
    }
    ^ F
}

// vocab.txt beside the checkpoint, in whatever names the checkpoint —
// a repository reference or a directory on this machine.
@ f5_vocab_beside s ckpt_ref → String {
    : i n ( nurl_str_len ckpt_ref )
    : ~ i cut -1
    : ~ i k 0
    ~ < k n {
        ? == ( nurl_str_get ckpt_ref k ) 47 { = cut k } {}
        = k + k 1
    }
    : String out ( string_new )
    : ~ i j 0
    ~ <= j cut {
        ( string_push_char out ( nurl_str_get ckpt_ref j ) )
        = j + j 1
    }
    ( string_push_str out `vocab.txt` )
    ^ out
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

// Everything this machine has on its own disk. A reference the machine has
// fetched is not here — it belongs to whoever asked for it, by name.
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

// Resolve a name to the two paths a model needs, fetching if the name is a
// repository reference this machine has not pulled yet. False = no such
// model, or the fetch failed (which is reported on stderr).
@ f5_registry_resolve s models_dir s id String ckpt_out String vocab_out → b {
    ? == 0 ( nurl_str_len id ) { ^ F } {}
    : ( Vec F5Entry ) reg ( f5_registry models_dir )
    : ~ b ok F
    : ~ i k 0
    ~ < k ( vec_len [F5Entry] reg ) {
        ?? ( vec_get [F5Entry] reg k ) {
            T e → {
                ? & ! ok != 0 ( nurl_str_eq ( string_data . e id ) id ) {
                    ( string_push_str ckpt_out ( string_data . e ckpt ) )
                    ( string_push_str vocab_out ( string_data . e vocab ) )
                    = ok T
                } {}
            }
            F → {}
        }
        = k + k 1
    }
    ( f5_registry_free reg )
    ? ok { ^ T } {}
    ? ( f5_is_reference id ) {} { ^ F }
    // a repository reference: the hub turns it into a path, downloading the
    // file the first time and nothing after that
    : String vref ( f5_vocab_beside id )
    ?? ( hub_get id ) {
        T cp → {
            ?? ( hub_get ( string_data vref ) ) {
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
    ( string_free vref )
    ^ ok
}
