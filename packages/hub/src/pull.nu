// packages/hub/src/pull.nu — the transfer engine: stream a URL into a
// content-addressed blob, constant-memory, parallel and resumable.
//
// A file of known size larger than one chunk is fetched in RANGES: it is
// cut into fixed chunks (HubOpts.chunk, 32 MiB by default) and up to
// HubOpts.conns connections at once each take the next chunk not yet on
// disk, ask for it with `Range: bytes=a-b` and write what arrives straight
// into the staging file at the chunk's offset (positional writes on one
// shared descriptor, stdlib/std/pfile.nu — no buffering beyond the HTTP
// read). A chunk that has landed is flushed to the device and recorded in
// a sidecar next to the staging file:
//
//   blobs/<stage>.part           the file being assembled, full length
//   blobs/<stage>.part.ranges    "hub-ranges 1 <size> <chunk>", then one
//                                finished chunk index a line
//
// so an interrupted transfer — killed, crashed, a dropped connection —
// resumes with exactly the chunks the sidecar does not list. Inside one
// run a broken connection is retried from the first byte of its chunk not
// yet written, with back-off; a stalled one times out. When every chunk
// is in, the whole file is hashed in order, and the bytes must hash to the
// sha256 the source published: a corrupted or substituted range is an
// INTEGRITY FAILURE and the staging state is discarded.
//
// A file of unknown size (a plain URL), or one chunk or smaller, takes one
// connection: it streams into blobs/<stage>.part with an incremental
// sha256, and an interrupted pull resumes with `Range: bytes=<size>-` (a
// 206 re-hashes the existing part and appends; a 200, from a server
// without Range, restarts cleanly).
//
// Either way the finished file is renamed to its content address
// (blobs/sha256-<hex>) and the hex is returned. When `expected` is a
// 64-hex sha256 (Hugging Face publishes one for every LFS file) an
// already-cached blob is returned without touching the network.
//
// The staging name is the blob's own address when the sha256 is known
// (sha256-<hex>.part), else the file's name plus a digest of its URL, so
// two files of one repository that share a basename never share a staging
// file. A partial download hub 0.2 left (blobs/<basename>.part) is taken
// over as the prefix it is.
//
// Several files at once: hub_fetch_all runs HubOpts.jobs transfers side by
// side (each with its own connections) and draws ONE progress line with
// the total rate. A failure raises a stop flag every transfer watches, so
// a pull ends promptly with the first error — and whatever finished stays
// recorded for the next run.
//
//   ( hub_opts_default )                                  → HubOpts
//   ( hub_fetch_blob root url stage legacy expected size opts got stop )
//                                                         → !String String
//   ( hub_fetch_all root jobs opts label )                → !( Vec String ) String

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/pfile.nu`
$ `stdlib/std/path.nu`
$ `stdlib/std/hash_sha256.nu`
$ `stdlib/std/progress.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/time.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/http.nu`
$ `store.nu`
$ `hf.nu`
// siblings (store: hub_blob_path, _hub_safe_name, hub_hash_file) are
// provided by the entry point that imports every hub file — see the note
// in hub.nu.

// ---- tuning ----------------------------------------------------------

// How a pull spends connections: `jobs` files at once, each over up to
// `conns` connections, in chunks of `chunk` bytes. The defaults (2 × 8)
// keep 16 connections busy on a repository of large files.
: HubOpts {
    i jobs
    i conns
    i chunk
}

: i HUB_JOBS_DEFAULT 2

: i HUB_CONNS_DEFAULT 8

: i HUB_CHUNK_DEFAULT 33554432

// A socket read or write that waits this long is a stalled connection:
// it fails, and the range is asked for again.
: i HUB_IO_TIMEOUT_MS 60000

// Attempts at one range in a row that bring no new byte before the
// transfer gives up (it stays resumable).
: i HUB_RANGE_TRIES 6

@ __hub_env_int s name i dflt i lo i hi → i {
    ?? ( env_get name ) {
        T v → {
            ?? ( string_to_int v ) {
                T n → { ? & >= n lo <= n hi { ^ n } {} }
                F _ → {}
            }
        }
        F → {}
    }
    ^ dflt
}

// $HUB_JOBS, $HUB_CONNS and $HUB_CHUNK (bytes) override the defaults.
@ hub_opts_default → HubOpts {
    : i j ( __hub_env_int `HUB_JOBS` HUB_JOBS_DEFAULT 1 64 )
    : i c ( __hub_env_int `HUB_CONNS` HUB_CONNS_DEFAULT 1 64 )
    : i k ( __hub_env_int `HUB_CHUNK` HUB_CHUNK_DEFAULT 65536 1073741824 )
    ^ @ HubOpts { j c k }
}

// A file is fetched in ranges when its size is known and above one chunk.
@ _hub_is_ranged i size i chunk → b { ^ > size chunk }

@ _hub_nchunks i size i chunk → i { ^ / - + size chunk 1 chunk }

// Bytes in chunk `idx` (the last one may be short).
@ _hub_chunk_len i idx i size i chunk → i {
    : i a * idx chunk
    : ~ i e + a chunk
    ? > e size { = e size } {}
    ^ - e a
}

// ---- small helpers ---------------------------------------------------

// case-insensitive response-header lookup → owned value ("" if absent)
@ __hub_find_header HttpStream st s want → String {
    : ~ String out ( string_new )
    : i hc ( http_stream_header_count st )
    : ~ i k 0
    ~ < k hc {
        : s nm ( http_stream_header_name st k )
        : String low ( string_from nm )
        : String lowc ( string_to_lower low )
        ? ( nurl_str_eq ( string_data lowc ) want ) {
            = out ( string_from ( http_stream_header_value st k ) )
            = k hc
        } { = k + k 1 }
    }
    ^ out
}

@ __hub_msg s head i n s tail → String {
    : String m ( string_from head )
    ( string_push_int m n )
    ( string_push_str m tail )
    ^ m
}

// The staging name of a download: the blob's address when its sha256 is
// known, else `<name>.<16 hex of sha256(url)>` — unique per source.
@ hub_stage_name s url s name s expected → String {
    ? == ( nurl_str_len expected ) 64 {
        : String st ( string_from `sha256-` )
        ( string_push_str st expected )
        ^ st
    } {}
    : ~ String base ( _hub_safe_name name )
    ? == ( string_len base ) 0 { = base ( string_from `download` ) } {}
    : Sha256 h ( sha256_init )
    ( sha256_update h ( bytes_from_str url ) )
    : String hex ( bytes_to_hex ( sha256_final h ) )
    : String tag ( string_substr hex 0 16 )
    ( string_push_char base 46 )
    ( string_push_str base ( string_data tag ) )
    ^ base
}

@ _hub_part_path String root s stage → String {
    : String bdir ( path_join ( string_data root ) `blobs` )
    : String p ( path_join ( string_data bdir ) stage )
    ( string_push_str p `.part` )
    ^ p
}

@ __hub_map_path s part → String {
    : String m ( string_from part )
    ( string_push_str m `.ranges` )
    ^ m
}

@ __hub_size_or0 s path → i {
    ?? ( file_size path ) {
        T sz → { ^ sz }
        F _ → { ^ 0 }
    }
}

// The finished chunks a sidecar records, as one flag per chunk of size
// `chunk` (1 = on disk). A record kept in another chunk size counts a
// chunk as on disk when every recorded chunk it overlaps is. None when
// there is no sidecar or it describes a file of another size — the
// staging file then vouches for nothing. A torn last line (a crash while
// appending) is skipped.
@ _hub_map_read s map i size i chunk → ?( Vec i ) {
    ?? ( read_file map ) {
        T txt → {
            : ( Vec String ) lines ( string_split txt `\n` )
            : i nl ( vec_len [String] lines )
            ? == nl 0 { ^ @ ?( Vec i ) { F } } {}
            : String want ( string_from `hub-ranges 1 ` )
            ( string_push_int want size )
            ( string_push_char want 32 )
            : ~ i c0 0
            ?? ( vec_get [String] lines 0 ) {
                T h → {
                    ? ( string_starts_with h ( string_data want ) ) {
                        : String rest ( string_substr h ( string_len want ) - ( string_len h ) ( string_len want ) )
                        ?? ( string_to_int rest ) { T c → { = c0 c } F _ → {} }
                    } {}
                }
                F → {}
            }
            ? <= c0 0 { ^ @ ?( Vec i ) { F } } {}
            : i n0 ( _hub_nchunks size c0 )
            : ( Vec i ) rec ( vec_new [i] )
            : ~ i k 0
            ~ < k n0 { ( vec_push [i] rec 0 ) = k + k 1 }
            = k 1
            ~ < k nl {
                ?? ( vec_get [String] lines k ) {
                    T ln → {
                        ?? ( string_to_int ln ) {
                            T idx → { ? & >= idx 0 < idx n0 { ( vec_put [i] rec idx 1 ) } {} }
                            F _ → {}
                        }
                    }
                    F → {}
                }
                = k + k 1
            }
            : i nc ( _hub_nchunks size chunk )
            : ( Vec i ) done ( vec_new [i] )
            = k 0
            ~ < k nc {
                : i a * k chunk
                : i e + a ( _hub_chunk_len k size chunk )
                : ~ i on 1
                : ~ i j / a c0
                ~ & < j n0 < * j c0 e {
                    ? == ( vec_at [i] rec j ) 0 { = on 0 } {}
                    = j + j 1
                }
                ( vec_push [i] done on )
                = k + k 1
            }
            ^ @ ?( Vec i ) { T done }
        }
        F _ → { ^ @ ?( Vec i ) { F } }
    }
}

// A fresh sidecar recording the chunks `done` flags — written aside and
// renamed over the old one, so a crash leaves one or the other whole.
@ _hub_map_write s map i size i chunk ( Vec i ) done → !v String {
    : String txt ( string_from `hub-ranges 1 ` )
    ( string_push_int txt size )
    ( string_push_char txt 32 )
    ( string_push_int txt chunk )
    ( string_push_char txt 10 )
    : ~ i k 0
    ~ < k ( vec_len [i] done ) {
        ? == ( vec_at [i] done k ) 1 {
            ( string_push_int txt k )
            ( string_push_char txt 10 )
        } {}
        = k + k 1
    }
    : String tmp ( string_from map )
    ( string_push_str tmp `.new` )
    : ~ b ok F
    ?? ( write_file ( string_data tmp ) ( string_data txt ) ) {
        T _ → { ?? ( fs_rename ( string_data tmp ) map ) { T _ → { = ok T } F _ → {} } }
        F _ → {}
    }
    ? ok { ^ @ !v String { T 0 } } {}
    ^ @ !v String { F ( string_from `hub: cannot write the download's range record` ) }
}

// Bytes of a pending download already on disk — what a progress line
// shows as done before the first network byte. Mirrors what the transfer
// itself will keep: recorded chunks for a ranged one, the prefix for a
// single stream.
@ _hub_have String root s stage s legacy s expected i size i chunk → i {
    ? == ( nurl_str_len expected ) 64 {
        : String bp ( hub_blob_path root expected )
        ? ( file_exists ( string_data bp ) ) { ^ size } {}
    } {}
    : String part ( _hub_part_path root stage )
    : String map ( __hub_map_path ( string_data part ) )
    : ~ i pre ( __hub_size_or0 ( string_data part ) )
    ? & == pre 0 > ( nurl_str_len legacy ) 0 { = pre ( __hub_size_or0 legacy ) } {}
    ? ( _hub_is_ranged size chunk ) {} { ^ pre }
    ?? ( _hub_map_read ( string_data map ) size chunk ) {
        T done → {
            : ~ i have 0
            : ~ i k 0
            ~ < k ( vec_len [i] done ) {
                ? == ( vec_at [i] done k ) 1 { = have + have ( _hub_chunk_len k size chunk ) } {}
                = k + k 1
            }
            ^ have
        }
        F → {}
    }
    ? > pre size { ^ 0 } {}
    ^ * / pre chunk chunk
}

// Rename the partial download hub 0.2 left (blobs/<basename>.part) to
// this download's staging name, when there is one and nothing newer.
@ __hub_adopt_legacy s part s legacy → v {
    ? == ( nurl_str_len legacy ) 0 { ^ } {}
    ? ( nurl_str_eq part legacy ) { ^ } {}
    ? ( file_exists part ) { ^ } {}
    ? ( file_exists legacy ) {
        : !v IoErr _r ( fs_rename legacy part )
    } {}
}

// The finished staging file → its content address. Checks the sha256
// against `expected` first; a mismatch discards the staging state.
@ __hub_publish String root s part s map String hex s expected → !String String {
    ? & == ( nurl_str_len expected ) 64 == ( nurl_str_eq ( string_data hex ) expected ) 0 {
        ( file_delete part )
        ( file_delete map )
        : String msg ( string_from `hub: INTEGRITY FAILURE — downloaded bytes do not match the published sha256 (` )
        : String short ( string_substr hex 0 12 )
        ( string_push_str msg ( string_data short ) )
        ( string_push_str msg ` vs expected)` )
        ^ @ !String String { F msg }
    } {}
    : String bp ( hub_blob_path root ( string_data hex ) )
    ?? ( fs_rename part ( string_data bp ) ) {
        T _ → {
            ( file_delete map )
            ^ @ !String String { T ( string_from ( string_data hex ) ) }
        }
        F _ → {
            ^ @ !String String { F ( string_from `hub: cannot move the finished blob into place` ) }
        }
    }
}

// ---- one range -------------------------------------------------------

// The outcome of one request for a range: how far it got (`pos`), and
// whether asking again could help.
: HubTry {
    i pos
    b fatal
    String err
}

// One request for bytes [a, e) of `url`, written into `pf` at their
// offsets as they arrive. Every byte written is added to `got`.
@ __hub_range_once s url PFile pf i a i e i size Atomic got Atomic stop → HubTry {
    : String hdrs ( string_from `Range: bytes=` )
    ( string_push_int hdrs a )
    ( string_push_char hdrs 45 )
    ( string_push_int hdrs - e 1 )
    ( string_push_str hdrs `\r\n` )
    : !HttpStream HttpErr sr ( http_stream_open_to `GET` url `` ( string_data hdrs ) HUB_IO_TIMEOUT_MS HUB_IO_TIMEOUT_MS )
    ?? sr {
        T st → {
            : i status ( http_stream_pump_headers st )
            ? != status 206 {
                ( http_stream_close st )
                // 200 is a server that ignores Range, a 4xx (but a timeout
                // or rate limit) a request it will not serve: neither
                // changes on a retry.
                : b client | == status 200 & & >= status 400 < status 500 & != status 408 != status 429
                ^ @ HubTry { a client ( __hub_msg `hub: a range request was answered HTTP ` status `` ) }
            } {}
            // The answer must be the range asked for, of a file of the size
            // the listing gave: `bytes a-(e-1)/size` exactly.
            : String cr ( __hub_find_header st `content-range` )
            : String want ( string_from `bytes ` )
            ( string_push_int want a )
            ( string_push_char want 45 )
            ( string_push_int want - e 1 )
            ( string_push_char want 47 )
            ( string_push_int want size )
            ? ( string_eq cr want ) {} {
                ( http_stream_close st )
                : String m ( string_from `hub: the server answered another range than asked (` )
                ( string_push_str m ( string_data cr ) )
                ( string_push_str m `)` )
                ^ @ HubTry { a T m }
            }
            : ~ i pos a
            : ~ b more T
            : ~ b fatal F
            : ~ String err ( string_new )
            ~ more {
                ?? ( http_stream_next_bytes st ) {
                    T piece → {
                        : i pn ( vec_len [u] piece )
                        ? > pn 0 {
                            ? > + pos pn e {
                                = more F
                                = fatal T
                                = err ( string_from `hub: the server sent more than the range asked for` )
                            } {
                                ?? ( pfile_write_at pf ( slice_from_vec [u] piece ) pos ) {
                                    T _ → {
                                        = pos + pos pn
                                        : i _g ( atomic_add got pn )
                                    }
                                    F _ → {
                                        = more F
                                        = fatal T
                                        = err ( string_from `hub: disk write failed mid-download` )
                                    }
                                }
                            }
                            ? != ( atomic_load stop ) 0 { = more F } {}
                        } {}
                    }
                    F → { = more F }
                }
            }
            ( http_stream_close st )
            ? & < pos e ! fatal {
                = err ( string_from `hub: the connection ended inside a range` )
            } {}
            ^ @ HubTry { pos fatal err }
        }
        F _ → {
            ^ @ HubTry { a F ( string_from `hub: cannot reach the download URL` ) }
        }
    }
}

// Bytes [a, e) of `url` into `pf`, asking again after a broken or
// stalled connection — from the first byte not yet written, after a
// back-off — until HUB_RANGE_TRIES attempts in a row bring nothing.
@ __hub_fetch_range s url PFile pf i a i e i size Atomic got Atomic stop → !v String {
    : ~ i pos a
    : ~ i tries 0
    : ~ String last ( string_from `hub: the range could not be fetched` )
    ~ & < pos e < tries HUB_RANGE_TRIES {
        ? != ( atomic_load stop ) 0 {
            ^ @ !v String { F ( string_from `hub: stopped` ) }
        } {}
        : HubTry t ( __hub_range_once url pf pos e size got stop )
        ? > . t pos pos { = tries 0 } { = tries + tries 1 }
        = pos . t pos
        ? < pos e {
            = last ( string_from ( string_data . t err ) )
            ? . t fatal { = tries HUB_RANGE_TRIES } {
                ? & > tries 0 < tries HUB_RANGE_TRIES {
                    : ~ i wait * 1000 * tries tries
                    ? > wait 30000 { = wait 30000 } {}
                    ( sleep_ms wait )
                } {}
            }
        } {}
    }
    ? >= pos e { ^ @ !v String { T 0 } } {}
    ^ @ !v String { F last }
}

// ---- a ranged transfer -----------------------------------------------

// What a range worker tells its transfer: chunk `idx` is on the device
// (kind 0), the transfer failed (kind 1, `err`), the worker is done
// (kind 2).
: HubMsg {
    i kind
    i idx
    String err
}

// One connection of a ranged transfer: takes the next pending chunk
// until none is left or `stop` is raised.
@ __hub_range_worker s url PFile pf ( Vec i ) pending Atomic next i size i chunk Atomic got Atomic stop ( Channel HubMsg ) ch → v {
    : i np ( vec_len [i] pending )
    : ~ b go T
    ~ go {
        ? != ( atomic_load stop ) 0 { = go F } {
            : i k ( atomic_add next 1 )
            ? >= k np { = go F } {
                : i idx ( vec_at [i] pending k )
                : i a * idx chunk
                : i e + a ( _hub_chunk_len idx size chunk )
                : !v String r ( __hub_fetch_range url pf a e size got stop )
                ?? r {
                    T _ → {
                        // on the device before the record says so
                        ?? ( pfile_datasync pf ) {
                            T _ → { : b _s ( chan_send [HubMsg] ch @ HubMsg { 0 idx ( string_new ) } ) }
                            F _ → {
                                : b _s ( chan_send [HubMsg] ch @ HubMsg { 1 idx ( string_from `hub: cannot flush the download to disk` ) } )
                                = go F
                            }
                        }
                    }
                    F msg → {
                        : b _s ( chan_send [HubMsg] ch @ HubMsg { 1 idx msg } )
                        = go F
                    }
                }
            }
        }
    }
    : b _x ( chan_send [HubMsg] ch @ HubMsg { 2 0 ( string_new ) } )
}

@ __hub_fetch_ranged String root s url s part s legacy s expected i size HubOpts o Atomic got Atomic stop → !String String {
    // One transfer per staging file: the lock is held as long as the
    // descriptor is open, and the kernel lets go of it when the process
    // dies, killed or not.
    ( __hub_adopt_legacy part legacy )
    ?? ( pfile_open part PFILE_CREATE ) {
        T pf → {
            ?? ( pfile_try_lock pf ) {
                T held → {
                    ? held {} {
                        : String m ( string_from `hub: another hub is downloading this file right now (` )
                        ( string_push_str m part )
                        ( string_push_str m `)` )
                        ^ @ !String String { F m }
                    }
                }
                F _ → { ^ @ !String String { F ( string_from `hub: cannot lock the staging file` ) } }
            }
            ^ ( __hub_ranged_locked root url part expected size o got stop pf )
        }
        F _ → { ^ @ !String String { F ( string_from `hub: cannot create the staging file` ) } }
    }
}

@ __hub_ranged_locked String root s url s part s expected i size HubOpts o Atomic got Atomic stop PFile pf → !String String {
    : i chunk . o chunk
    : String map ( __hub_map_path part )
    : i nc ( _hub_nchunks size chunk )

    // What is on disk: the chunks the sidecar records, else — a staging
    // file without one, from a single-stream pull or hub 0.2 — the
    // chunks its contiguous prefix covers whole. A sidecar that cannot be
    // read vouches for nothing. The record is rewritten in this layout
    // either way.
    : ~ ( Vec i ) done ( vec_new [i] )
    : ~ b known F
    ?? ( _hub_map_read ( string_data map ) size chunk ) {
        T d → { = done d = known T }
        F → {}
    }
    ? known {} {
        : ~ i pre 0
        ? ( file_exists ( string_data map ) ) {} { = pre ( __hub_size_or0 part ) }
        ? > pre size { = pre 0 } {}
        : ~ i k 0
        ~ < k nc {
            : i e + * k chunk ( _hub_chunk_len k size chunk )
            ( vec_push [i] done ? <= e pre 1 0 )
            = k + k 1
        }
    }
    : !v String mw ( _hub_map_write ( string_data map ) size chunk done )
    ?? mw { T _ → {} F e → { ^ @ !String String { F e } } }
    ?? ( pfile_set_len pf size ) {
        T _ → {}
        F _ → { ^ @ !String String { F ( string_from `hub: cannot size the staging file (disk full?)` ) } }
    }

    : ( Vec i ) pending ( vec_new [i] )
    : ~ i k 0
    ~ < k nc {
        ? == ( vec_at [i] done k ) 0 { ( vec_push [i] pending k ) } {}
        = k + k 1
    }
    : i np ( vec_len [i] pending )

    : ~ b failed F
    : ~ String ferr ( string_new )
    ? > np 0 {
        : ~ i nw . o conns
        ? > nw np { = nw np } {}
        ? < nw 1 { = nw 1 } {}
        : Atomic next ( atomic_new 0 )
        : ( Channel HubMsg ) ch ( chan_new [HubMsg] )
        : ( Vec Thread ) ts ( vec_new [Thread] )
        : ~ i w 0
        ~ < w nw {
            : String wurl ( string_from url )
            : ( Vec i ) wpend ( vec_clone [i] pending )
            : ( @ v ) body \ → v { ( __hub_range_worker ( string_data wurl ) pf wpend next size chunk got stop ch ) }
            ?? ( thread_spawn_owned body ) {
                T t → { ( vec_push [Thread] ts t ) }
                F _ → { ( __hub_range_worker url pf pending next size chunk got stop ch ) }
            }
            = w + w 1
        }
        // Record each chunk as it lands; the first failure stops the rest.
        : ~ i exits 0
        ~ < exits nw {
            ?? ( chan_recv [HubMsg] ch ) {
                T m → {
                    ? == . m kind 0 {
                        ( vec_put [i] done . m idx 1 )
                        : String ln ( string_new )
                        ( string_push_int ln . m idx )
                        ( string_push_char ln 10 )
                        ?? ( append_file ( string_data map ) ( string_data ln ) ) {
                            T _ → {}
                            F _ → {
                                ? failed {} {
                                    = failed T
                                    = ferr ( string_from `hub: cannot write the download's range record` )
                                }
                                ( atomic_store stop 1 )
                            }
                        }
                    } {
                        ? == . m kind 1 {
                            ? failed {} {
                                = failed T
                                = ferr ( string_from ( string_data . m err ) )
                            }
                            ( atomic_store stop 1 )
                        } { = exits + exits 1 }
                    }
                }
                F → { = exits nw }
            }
        }
        : ~ i j 0
        ~ < j ( vec_len [Thread] ts ) {
            ?? ( vec_get [Thread] ts j ) { T t → { : i _j ( thread_join t ) } F → {} }
            = j + j 1
        }
    } {}

    ? failed { ^ @ !String String { F ferr } } {}
    = k 0
    ~ < k nc {
        ? == ( vec_at [i] done k ) 0 {
            ^ @ !String String { F ( string_from `hub: stopped — rerun to resume the download` ) }
        } {}
        = k + k 1
    }

    // Every range is in: the file, hashed in order, must be the file
    // the source published.
    : !String String hr ( hub_hash_file part )
    ?? hr {
        T hex → { ^ ( __hub_publish root part ( string_data map ) hex expected ) }
        F e → { ^ @ !String String { F e } }
    }
}

// ---- a single stream -------------------------------------------------

// Feed the existing .part through the hasher (resume path).
@ __hub_rehash_part Sha256 h s path → !i String {
    : !File IoErr fr ( file_open path )
    ?? fr {
        T f → {
            : ~ i total 0
            : ~ b more T
            : ~ b bad F
            ~ more {
                : !( Vec u ) IoErr cr ( file_read_chunk f 1048576 )
                ?? cr {
                    T piece → {
                        : i pn ( vec_len [u] piece )
                        ? == pn 0 { = more F } {
                            ( sha256_update h piece )
                            = total + total pn
                        }
                    }
                    F _ → { = more F = bad T }
                }
            }
            ( file_close f )
            ? bad { ^ @ !i String { F ( string_from `hub: cannot read the partial download` ) } } {}
            ^ @ !i String { T total }
        }
        F _ → { ^ @ !i String { F ( string_from `hub: cannot reopen the partial download` ) } }
    }
}

@ __hub_fetch_stream String root s url s part s legacy s expected Atomic got Atomic stop → !String String {
    : String map ( __hub_map_path part )
    // A ranged transfer's staging file has holes: it is no prefix.
    ? ( file_exists ( string_data map ) ) {
        ( file_delete part )
        ( file_delete ( string_data map ) )
    } {}
    ( __hub_adopt_legacy part legacy )

    // resume offset = existing partial size
    : i off ( __hub_size_or0 part )
    : String hdrs ( string_new )
    ? > off 0 {
        ( string_push_str hdrs `Range: bytes=` )
        ( string_push_int hdrs off )
        ( string_push_str hdrs `-\r\n` )
    } {}

    : !HttpStream HttpErr sr ( http_stream_open_to `GET` url `` ( string_data hdrs ) HUB_IO_TIMEOUT_MS HUB_IO_TIMEOUT_MS )
    ?? sr {
        T st → {
            : i status ( http_stream_pump_headers st )
            : ~ b resume F
            ? == status 206 { = resume T } {}
            ? | == status 200 == status 206 {} {
                ( http_stream_close st )
                ^ @ !String String { F ( __hub_msg `hub: download failed (HTTP ` status `)` ) }
            } {}

            : String cl ( __hub_find_header st `content-length` )
            : ~ i total 0
            ?? ( string_to_int cl ) {
                T v → { = total v }
                F _ → {}
            }
            ? & resume > total 0 { = total + total off } {}

            : Sha256 h ( sha256_init )
            : ~ i done_bytes 0
            : ~ b failed F
            : ~ String ferr ( string_new )

            // The staging file, once it is open (its last owner closes it).
            : ~ ? File fo @ ?File { F }
            ? resume {
                : !i String rr ( __hub_rehash_part h part )
                ?? rr {
                    T n → { = done_bytes n }
                    F e → { = failed T = ferr e }
                }
                ? failed {} {
                    ?? ( file_append part ) {
                        T fa → { = fo @ ?File { T fa } }
                        F _ → { = failed T = ferr ( string_from `hub: cannot open the staging file` ) }
                    }
                }
            } {
                ?? ( file_create part ) {
                    T fa → { = fo @ ?File { T fa } }
                    F _ → { = failed T = ferr ( string_from `hub: cannot create the staging file` ) }
                }
            }

            : ~ b more ! failed
            ~ more {
                : ?( Vec u ) ch ( http_stream_next_bytes st )
                ?? ch {
                    T piece → {
                        : i pn ( vec_len [u] piece )
                        ? > pn 0 {
                            : b wrote ?? fo { T f → ?? ( file_write_chunk f piece ) { T _ → T F _ → F } F → F }
                            ? wrote {
                                ( sha256_update h piece )
                                = done_bytes + done_bytes pn
                                : i _g ( atomic_add got pn )
                            } {
                                = failed T
                                = more F
                                = ferr ( string_from `hub: disk write failed mid-download` )
                            }
                        } {}
                        ? != ( atomic_load stop ) 0 { = more F } {}
                    }
                    F → { = more F }
                }
            }
            ?? fo { T f → ( file_close f ) F → {} }

            ? failed {} {
                : ?HttpErr he ( http_stream_err st )
                ?? he {
                    T _ → {
                        = failed T
                        = ferr ( string_from `hub: transfer aborted — rerun to resume from the partial file` )
                    }
                    F → {}
                }
            }
            ( http_stream_close st )
            : ( Vec u ) dg ( sha256_final h )
            ? failed {
                ^ @ !String String { F ferr }
            } {}
            // Stopped: what is on disk is a prefix, whatever the length.
            ? != ( atomic_load stop ) 0 {
                ^ @ !String String { F ( string_from `hub: stopped — rerun to resume the download` ) }
            } {}

            ? & > total 0 != done_bytes total {
                ^ @ !String String { F ( string_from `hub: transfer ended short — rerun to resume from the partial file` ) }
            } {}

            : String hex ( bytes_to_hex dg )
            ^ ( __hub_publish root part ( string_data map ) hex expected )
        }
        F _ → {
            ^ @ !String String { F ( string_from `hub: cannot reach the download URL` ) }
        }
    }
}

// ---- the entry points ------------------------------------------------

// Fetch `url` into the blob store under staging name `stage` (see
// hub_stage_name); `legacy` is the staging path hub 0.2 used for it ("" if
// none), `size` the file's size when the listing gave one (0 if unknown).
// Bytes off the network are added to `got`; a nonzero `stop` ends the
// transfer early (resumable). → the blob's sha256 hex.
@ hub_fetch_blob String root s url s stage s legacy s expected i size HubOpts o Atomic got Atomic stop → !String String {
    // already cached? a content-addressed name is its own proof.
    ? == ( nurl_str_len expected ) 64 {
        : String bp0 ( hub_blob_path root expected )
        ? ( file_exists ( string_data bp0 ) ) {
            ^ @ !String String { T ( string_from expected ) }
        } {}
    } {}
    : String part ( _hub_part_path root stage )
    ? ( _hub_is_ranged size . o chunk ) {
        ^ ( __hub_fetch_ranged root url ( string_data part ) legacy expected size o got stop )
    } {}
    ^ ( __hub_fetch_stream root url ( string_data part ) legacy expected got stop )
}

// One download of a hub_fetch_all batch.
: HubJob {
    String url
    String stage
    String legacy
    String expected
    i size
}

: HubDone {
    i idx
    b ok
    String val
}

// Fetch every job, `. o jobs` at a time, under one progress line (stderr,
// a tty only) whose rate is the batch's total. → each job's sha256 hex, in
// order, or the first error (the others are stopped; all stay resumable).
@ hub_fetch_all String root ( Vec HubJob ) jobs HubOpts o s label → !( Vec String ) String {
    : i n ( vec_len [HubJob] jobs )
    : ~ i total 0
    : ~ i have 0
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [HubJob] jobs k ) {
            T jb → {
                = total + total . jb size
                = have + have ( _hub_have root ( string_data . jb stage ) ( string_data . jb legacy ) ( string_data . jb expected ) . jb size . o chunk )
            }
            F → {}
        }
        = k + k 1
    }
    : Progress pg ( progress_new label total )
    ? > have 0 { ( progress_set pg have ) } {}

    : Atomic got ( atomic_new 0 )
    : Atomic stop ( atomic_new 0 )
    : Atomic next ( atomic_new 0 )
    : ( Channel HubDone ) ch ( chan_new [HubDone] )
    : ~ i lanes . o jobs
    ? > lanes n { = lanes n } {}
    ? < lanes 1 { = lanes 1 } {}
    : ( Vec Thread ) ts ( vec_new [Thread] )
    : ~ i l 0
    ~ < l lanes {
        : String lroot ( string_from ( string_data root ) )
        : ( Vec HubJob ) ljobs ( vec_clone [HubJob] jobs )
        : ( @ v ) body \ → v { ( __hub_fetch_lane lroot ljobs o next got stop ch ) }
        ?? ( thread_spawn_owned body ) {
            T t → { ( vec_push [Thread] ts t ) }
            F _ → { ( __hub_fetch_lane root jobs o next got stop ch ) }
        }
        = l + l 1
    }

    : ( Vec String ) out ( vec_new [String] )
    = k 0
    ~ < k n { ( vec_push [String] out ( string_new ) ) = k + k 1 }
    : ~ b failed F
    : ~ String ferr ( string_new )
    : ~ i recv 0
    : ~ i seen 0
    ~ < recv n {
        ?? ( chan_try_recv [HubDone] ch ) {
            T d → {
                = recv + recv 1
                ? . d ok {
                    ( vec_put [String] out . d idx ( string_from ( string_data . d val ) ) )
                } {
                    ? failed {} {
                        = failed T
                        = ferr ( string_from ( string_data . d val ) )
                    }
                    ( atomic_store stop 1 )
                }
            }
            F → { ( sleep_ms 100 ) }
        }
        : i g ( atomic_load got )
        ? > g seen {
            ( progress_add pg - g seen )
            = seen g
        } {}
    }
    = l 0
    ~ < l ( vec_len [Thread] ts ) {
        ?? ( vec_get [Thread] ts l ) { T t → { : i _j ( thread_join t ) } F → {} }
        = l + l 1
    }
    ( progress_done pg )
    ? failed { ^ @ !( Vec String ) String { F ferr } } {}
    ^ @ !( Vec String ) String { T out }
}

// One lane of hub_fetch_all: the next job until none is left. Once `stop`
// is raised the remaining jobs are answered as stopped, unstarted, so
// every job is answered exactly once.
@ __hub_fetch_lane String root ( Vec HubJob ) jobs HubOpts o Atomic next Atomic got Atomic stop ( Channel HubDone ) ch → v {
    : i n ( vec_len [HubJob] jobs )
    : ~ b go T
    ~ go {
        : i k ( atomic_add next 1 )
        ? >= k n { = go F } {
            ? != ( atomic_load stop ) 0 {
                : b _s ( chan_send [HubDone] ch @ HubDone { k F ( string_from `hub: stopped` ) } )
            } {
                ?? ( vec_get [HubJob] jobs k ) {
                    T jb → {
                        : !String String r ( hub_fetch_blob root ( string_data . jb url ) ( string_data . jb stage ) ( string_data . jb legacy ) ( string_data . jb expected ) . jb size o got stop )
                        ?? r {
                            T hex → { : b _s ( chan_send [HubDone] ch @ HubDone { k T hex } ) }
                            F e → { : b _s ( chan_send [HubDone] ch @ HubDone { k F e } ) }
                        }
                    }
                    F → { : b _s ( chan_send [HubDone] ch @ HubDone { k F ( string_from `hub: no such job` ) } ) }
                }
            }
        }
    }
}
