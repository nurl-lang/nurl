// anomaly/store.nu — persistence (milestone M3).
//
// A model lives in its organisation's SQLite database, <root>/orgs/<org>.db
// — the same file that holds the organisation's members, roles and API
// keys. See "The organisation's database" below for the tables, for what
// the flat directory-per-model store it replaced could not do, and for how
// this behaves when several threads use one store.
//
// The forest blob ("ANOMFOR1") is a little-endian dump of the iforest node
// arena plus the version's decision offset/margin. Loading re-validates
// every structural invariant (lengths, index ranges, node-count caps), so a
// corrupt or truncated blob comes back as None — never undefined behaviour.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/floatbits.nu`
$ `stdlib/std/sort.nu`
$ `stdlib/ext/sqlite.nu`
$ `stdlib/ext/json.nu`
$ `src/prep.nu`
$ `src/model.nu`
$ `src/autoenc.nu`
$ `src/forecast.nu`
$ `deps/iforest/src/iforest.nu`

// Refuse to load blobs claiming more than this many arena nodes / trees /
// name bytes — bounds untrusted counts before any allocation.
: i ANOM_BLOB_MAX_NODES 200000000
: i ANOM_BLOB_MAX_TREES 100000
: i ANOM_BLOB_MAX_NAME 4096

// ── Bounded little-endian reader over an untrusted byte buffer ────────

: BlobRd {
    ( Vec u ) buf
    i pos
    b ok
}

@ __an_rd_new ( Vec u ) buf → *BlobRd {
    : *BlobRd rd # *BlobRd ( nurl_malloc Z BlobRd )
    = . rd buf buf
    = . rd pos 0
    = . rd ok T
    ^ rd
}

@ __an_rd_u64 * BlobRd rd → i {
    ?? ( bytes_read_u64_le . rd buf . rd pos ) {
        T x → {
            = . rd pos + . rd pos 8
            ^ # i x
        }
        F _ → {
            = . rd ok F
            ^ 0
        }
    }
}

@ __an_rd_f64 * BlobRd rd → f {
    ?? ( bytes_read_f64_le . rd buf . rd pos ) {
        T x → {
            = . rd pos + . rd pos 8
            ^ x
        }
        F _ → {
            = . rd ok F
            ^ 0.0
        }
    }
}

// ── VerModel ⇄ bytes ──────────────────────────────────────────────────

@ __an_blob_push_ivec ( Vec u ) out ( Vec i ) xs → v {
    : i n ( vec_len [i] xs )
    ( bytes_push_u64_le out # u64 n )
    : *i dp ( vec_data [i] xs )
    : ~ i k 0
    ~ < k n {
        ( bytes_push_u64_le out # u64 . dp k )
        = k + k 1
    }
}

@ __an_blob_push_fvec ( Vec u ) out ( Vec f ) xs → v {
    : i n ( vec_len [f] xs )
    ( bytes_push_u64_le out # u64 n )
    : *f dp ( vec_data [f] xs )
    : ~ i k 0
    ~ < k n {
        ( bytes_push_f64_le out . dp k )
        = k + k 1
    }
}

// Read `want` i64s (a count-prefixed vector whose count must equal `want`).
@ __an_blob_read_ivec * BlobRd rd i want → ( Vec i ) {
    : ( Vec i ) out ( vec_new [i] )
    : i n ( __an_rd_u64 rd )
    ? == n want {} { = . rd ok F ^ out }
    ( vec_reserve [i] out n )
    : ~ i k 0
    ~ & . rd ok < k n {
        ( vec_push [i] out ( __an_rd_u64 rd ) )
        = k + k 1
    }
    ^ out
}

@ __an_blob_read_fvec * BlobRd rd i want → ( Vec f ) {
    : ( Vec f ) out ( vec_new [f] )
    : i n ( __an_rd_u64 rd )
    ? == n want {} { = . rd ok F ^ out }
    ( vec_reserve [f] out n )
    : ~ i k 0
    ~ & . rd ok < k n {
        ( vec_push [f] out ( __an_rd_f64 rd ) )
        = k + k 1
    }
    ^ out
}

// Serialise one trained version (forest + offset + margin) to owned bytes.
@ vermodel_to_bytes VerModel vm → ( Vec u ) {
    : ( Vec u ) out ( vec_new [u] )
    ( bytes_extend_str out `ANOMFOR1` )
    : i nlen ( string_len . vm vname )
    ( bytes_push_u64_le out # u64 nlen )
    ( bytes_extend_str out ( string_data . vm vname ) )
    ( bytes_push_f64_le out . vm offset )
    ( bytes_push_f64_le out . vm margin )

    : IForest fo . vm forest
    ( bytes_push_u64_le out # u64 . fo n_trees )
    ( bytes_push_u64_le out # u64 . fo sample_size )
    ( bytes_push_f64_le out . fo c_psi )
    ( bytes_push_u64_le out # u64 . fo n_cols )
    ( __an_blob_push_ivec out . fo roots )
    : i n_nodes ( vec_len [i] . fo feature )
    ( bytes_push_u64_le out # u64 n_nodes )
    ( __an_blob_push_ivec out . fo feature )
    ( __an_blob_push_fvec out . fo split )
    ( __an_blob_push_ivec out . fo left )
    ( __an_blob_push_ivec out . fo right )
    ( __an_blob_push_ivec out . fo size )
    ^ out
}

// Every node index in xs must lie in [-1, n_nodes).
@ __an_blob_idx_ok ( Vec i ) xs i n_nodes → b {
    : i n ( vec_len [i] xs )
    : *i dp ( vec_data [i] xs )
    : ~ i k 0
    ~ < k n {
        : i x . dp k
        ? || < x -1 >= x n_nodes { ^ F } {}
        = k + k 1
    }
    ^ T
}

// Parse a forest blob. None on any structural violation: bad magic, short
// buffer, absurd counts, mismatched array lengths, out-of-range indices.
@ vermodel_from_bytes ( Vec u ) buf → ?VerModel {
    : ( Vec u ) magic ( bytes_from_str `ANOMFOR1` )
    : b magic_ok ( bytes_starts_with buf magic )
    ( vec_free [u] magic )
    ? magic_ok {} { ^ @ ?VerModel { F } }

    : *BlobRd rd ( __an_rd_new buf )
    = . rd pos 8

    : i nlen ( __an_rd_u64 rd )
    ? || < nlen 0 > nlen ANOM_BLOB_MAX_NAME { = . rd ok F } {}
    : ~ String vname ( string_new )
    ? . rd ok {
        : i n ( vec_len [u] buf )
        ? > + . rd pos nlen n { = . rd ok F } {
            : *u bp ( vec_data [u] buf )
            : i base + # i bp . rd pos
            ( string_free vname )
            = vname ( string_from_bytes # *u base nlen )
            = . rd pos + . rd pos nlen
        }
    } {}

    : f off ( __an_rd_f64 rd )
    : f margin ( __an_rd_f64 rd )
    : i n_trees ( __an_rd_u64 rd )
    : i sample_size ( __an_rd_u64 rd )
    : f c_psi ( __an_rd_f64 rd )
    : i n_cols ( __an_rd_u64 rd )
    ? || < n_trees 0 > n_trees ANOM_BLOB_MAX_TREES { = . rd ok F } {}
    ? || < sample_size 0 || < n_cols 0 > n_cols ANOM_BLOB_MAX_NODES { = . rd ok F } {}

    : ( Vec i ) roots ( __an_blob_read_ivec rd n_trees )
    : i n_nodes ( __an_rd_u64 rd )
    ? || < n_nodes 0 > n_nodes ANOM_BLOB_MAX_NODES { = . rd ok F } {}
    : ~ i safe_nodes n_nodes
    ? . rd ok {} { = safe_nodes 0 }
    : ( Vec i ) feature ( __an_blob_read_ivec rd safe_nodes )
    : ( Vec f ) split ( __an_blob_read_fvec rd safe_nodes )
    : ( Vec i ) left ( __an_blob_read_ivec rd safe_nodes )
    : ( Vec i ) right ( __an_blob_read_ivec rd safe_nodes )
    : ( Vec i ) size ( __an_blob_read_ivec rd safe_nodes )

    // Trailing garbage after a well-formed body is also a corrupt file.
    ? == . rd pos ( vec_len [u] buf ) {} { = . rd ok F }

    : ~ b ok . rd ok
    ( nurl_free rd )
    ? ok {
        ? ( __an_blob_idx_ok roots safe_nodes ) {} { = ok F }
        ? ( __an_blob_idx_ok left safe_nodes ) {} { = ok F }
        ? ( __an_blob_idx_ok right safe_nodes ) {} { = ok F }
        // feature must be in [-1, n_cols); leaves (-1) have no split.
        ? ( __an_blob_idx_ok feature n_cols ) {} { = ok F }
    } {}

    ? ok {} {
        ( string_free vname )
        ( vec_free [i] roots )
        ( vec_free [i] feature )
        ( vec_free [f] split )
        ( vec_free [i] left )
        ( vec_free [i] right )
        ( vec_free [i] size )
        ^ @ ?VerModel { F }
    }
    : IForest fo @ IForest { n_trees sample_size c_psi n_cols roots feature split left right size }
    ^ @ ?VerModel { T @ VerModel { vname fo off margin n_cols T } }
}

// ── Scored-verdict cache ──────────────────────────────────────────────
//
// Re-scoring a stored ring is pure recomputation: the same point against
// the same forests yields the same verdict every time. The dashboard's
// anomaly scan used to pay for that recomputation on every visit, one HTTP
// round trip AND one full model load per point, which is what made a
// 5000-point scan a minutes-long progress bar.
//
// The cache is a ring-aligned array of verdicts stamped with the model's
// `score_epoch` (prep.nu). Anything that can change a verdict — a retrain,
// a new autoencoder, a margin edit, a version toggled, a reset — bumps the
// epoch, and the whole cache is stale by construction; there is no
// per-entry invalidation rule to get wrong.
//
// Alignment survives ring eviction because rows are keyed on the LIFETIME
// point counter, not the ring index: `base_seen` is the lifetime index of
// row 0, so a ring row `j` of a ring of length L at counter S sits at cache
// index `S - L + j - base_seen`. Rows outside [0, nrows) are simply misses.
//
//   "ANOMSCR2" | u64 epoch | u64 base_seen
//              | u64 nver  | nver × (u64 len, bytes)
//              | u64 nrows | nrows × (f64 score, f64 severity, u64 state, u64 present, u64 flagged)
//
// `state` is 0 for a row never scored under this epoch, 1 for a scored
// verdict and 2 for "the model was not ready for this point". `present` and
// `flagged` are bitmasks over `vnames`, so a version that produced no
// verdict (a timevector window longer than the ring prefix) stays
// distinguishable from one that produced a clean verdict.
: i ANOM_SC_UNSCORED 0
: i ANOM_SC_SCORED 1
: i ANOM_SC_NOT_READY 2

// Refuse a cache claiming more rows/versions than a model could hold.
: i ANOM_SC_MAX_ROWS 100000000
: i ANOM_SC_MAX_VERS 64

: ScoreCache {
    i epoch
    i base_seen
    ( Vec String ) vnames
    ( Vec i ) state
    ( Vec f ) score
    ( Vec f ) severity
    ( Vec i ) present
    ( Vec i ) flagged
}

@ scorecache_new i epoch i base_seen → ScoreCache {
    ^ @ ScoreCache {
        epoch base_seen ( vec_new [String] )
        ( vec_new [i] ) ( vec_new [f] ) ( vec_new [f] ) ( vec_new [i] ) ( vec_new [i] )
    }
}

@ scorecache_free sink ScoreCache c → v {
    ( vec_free_with [String] . c vnames \ String x → v { ( string_free x ) } )
    ( vec_free [i] . c state )
    ( vec_free [f] . c score )
    ( vec_free [f] . c severity )
    ( vec_free [i] . c present )
    ( vec_free [i] . c flagged )
}

@ scorecache_rows ScoreCache c → i {
    ^ ( vec_len [i] . c state )
}

// Grow to `n` rows, every new row unscored.
@ scorecache_resize ScoreCache c i n → v {
    ~ < ( vec_len [i] . c state ) n {
        ( vec_push [i] . c state ANOM_SC_UNSCORED )
        ( vec_push [f] . c score 0.0 )
        ( vec_push [f] . c severity 0.0 )
        ( vec_push [i] . c present 0 )
        ( vec_push [i] . c flagged 0 )
    }
}

@ scorecache_set ScoreCache c i at i state f score f severity i present i flagged → v {
    : b _a ( vec_set [i] . c state at state )
    : b _b ( vec_set [f] . c score at score )
    : b _s ( vec_set [f] . c severity at severity )
    : b _c ( vec_set [i] . c present at present )
    : b _d ( vec_set [i] . c flagged at flagged )
}

// Do the cached version names still match the live ones, in order?
@ scorecache_vnames_match ScoreCache c ( Vec String ) live → b {
    : i n ( vec_len [String] live )
    ? == n ( vec_len [String] . c vnames ) {} { ^ F }
    : ~ i k 0
    ~ < k n {
        : ~ b same F
        ?? ( vec_get [String] live k ) {
            T a → {
                ?? ( vec_get [String] . c vnames k ) {
                    T b2 → { = same == ( nurl_str_eq ( string_data a ) ( string_data b2 ) ) 1 }
                    F _ → {}
                }
            }
            F _ → {}
        }
        ? same {} { ^ F }
        = k + k 1
    }
    ^ T
}

// ── Labels ────────────────────────────────────────────────────────────
//
// What a reader said about a stored point: that a flagged row was a
// false positive, or that it was the real thing. Keyed by the point's
// LIFETIME sequence number (Meta.n_seen space, see the score cache
// above), not its ring index, so a label survives eviction and never
// lands on the row that took a shifted slot. One JSON record per line,
// appended, last write wins on replay — the label `none` withdraws an
// earlier one. Labels change no verdict, so they never bump the epoch;
// their first reader is calibration, which leaves the false positives
// out of the set a margin is fitted on.

: s ANOM_LABEL_FP `false_positive`
: s ANOM_LABEL_OK `confirmed`
: s ANOM_LABEL_NONE `none`

: Label {
    i seq  // lifetime sequence number of the point
    i ts  // the point's own timestamp
    String label  // ANOM_LABEL_*
    String by  // who said so (a principal's name, an API key's id, or empty)
    i at  // when (unix seconds)
    String note
}

@ label_free sink Label l → v {
    ( string_free . l label )
    ( string_free . l by )
    ( string_free . l note )
}

@ labels_free sink ( Vec Label ) ls → v {
    ( vec_free_with [Label] ls \ Label l → v { ( label_free l ) } )
}

// Is `s` a label a reader may give?
@ label_known s name → b {
    ? == ( nurl_str_eq name ANOM_LABEL_FP ) 1 { ^ T } {}
    ? == ( nurl_str_eq name ANOM_LABEL_OK ) 1 { ^ T } {}
    ? == ( nurl_str_eq name ANOM_LABEL_NONE ) 1 { ^ T } {}
    ^ F
}

@ label_to_json Label l → Json {
    : Json o ( json_obj_new )
    ( json_obj_set o `seq` ( json_int . l seq ) )
    ( json_obj_set o `timestamp` ( json_int . l ts ) )
    ( json_obj_set o `label` ( json_str_lit ( string_data . l label ) ) )
    ( json_obj_set o `by` ( json_str_lit ( string_data . l by ) ) )
    ( json_obj_set o `at` ( json_int . l at ) )
    ( json_obj_set o `note` ( json_str_lit ( string_data . l note ) ) )
    ^ o
}

@ __an_label_str Json o s key → String {
    ?? ( json_obj_get o key ) {
        T v → { ? ( json_is_str v ) { ^ ( string_from ( json_str_data v ) ) } { ^ ( string_new ) } }
        F _ → { ^ ( string_new ) }
    }
}

@ __an_label_int Json o s key → i {
    ?? ( json_obj_get o key ) {
        T v → { ? ( json_is_num v ) { ^ ( json_as_int v ) } { ^ -1 } }
        F _ → { ^ -1 }
    }
}

// ── The organisation's database ───────────────────────────────────────
//
// A model belongs to an organisation, and an organisation IS a database:
// <root>/orgs/<org>.db, the same SQLite file that already holds the
// organisation's members, their roles and its API keys. Everything a
// model is — its metadata, its ring of raw points, its forests, its
// autoencoder, its forecast, its labels and its audit trail — lives in
// that file, keyed by the model's name.
//
// It used to be a directory per model in one flat store shared by every
// organisation, with ownership recorded on the side. Two things follow
// from moving it, and both were the reason to move:
//
//   * A model name is unique WITHIN an organisation and means nothing
//     outside it. Two tenants may each keep a `boiler`; neither can see
//     the other's, neither can take the name from the other, and asking
//     for a name another tenant uses is an honest 404 instead of a 403
//     that discloses the name exists.
//   * Evicting the oldest point when the ring is full is one DELETE over
//     an index. The flat store appended the line and then rewrote the
//     WHOLE log — 15 ms at 14 700 points on this machine, linear in the
//     cap, so a model at the 150 000-point default paid about 160 ms of
//     pure rewriting for every point it accepted.
//
// The tables, all keyed by model name (the organisation is the FILE, so
// no row carries an org column and no query can forget one):
//
//   models_meta         name → the metadata JSON. A model EXISTS iff it
//                       has a row here.
//   models_meta_corrupt metadata that would not parse, set aside with the
//                       time it happened rather than overwritten.
//   points              (model, seq) → the raw JSON line. `seq` is the
//                       point's LIFETIME number, the same space labels
//                       and the score cache are keyed in, so eviction is
//                       a range delete and nothing is renumbered.
//   blobs               (model, kind) → bytes. kind is `forest:<version>`,
//                       `ae`, `fc` or `scores`.
//   labels              (model, seq) → the label record. Last write wins
//                       is the primary key doing it; `none` deletes.
//   audit               an append-only log of margin changes per model.
//
// ── Threads ───────────────────────────────────────────────────────────
//
// A `Store` is a plain value: a root, an organisation, and whether the
// database opened. It holds NO connection, and that is deliberate twice
// over. A connection is opened for the length of one operation and closed
// with it, so it never leaves the thread that made it — `Database` is
// marked `% NotSend` in the binding, so the compiler enforces that rather
// than trusting a comment. And a handle cannot be stored in a value that
// is passed around by value: a `Database` has a Drop, a by-value struct
// parameter runs it, and the caller's connection would be closed by the
// callee's return. (It was: every command segfaulted on the first
// statement after the first helper took a Store by value.)
//
// Threads therefore share the FILE, not the handle. WAL lets their reads
// run concurrently with one writer; `busy_timeout` makes a second writer
// wait rather than fail; and every write of more than one statement is one
// BEGIN IMMEDIATE transaction, so it is all-or-nothing and never
// interleaves with another thread's. IMMEDIATE and not the default
// deferred BEGIN: a deferred transaction takes the write lock only when it
// first writes, and if another connection took it meanwhile SQLite answers
// SQLITE_BUSY_SNAPSHOT, which the busy handler is not allowed to retry.
//
// What this does NOT do is serialise a read-modify-write of one model
// across threads — two requests that load the same model, change it and
// save it can still lose one of the changes. That is the model layer's
// business, not the store's, and today the service holds one lock for the
// whole request.

: s ANOM_ORG_DEFAULT `public`

: s ANOM_KIND_AE `ae`
: s ANOM_KIND_FC `fc`
: s ANOM_KIND_SCORES `scores`

: Store {
    String root
    String org
    b ok
}

// An org id is a filename, and an id that reaches here has been through
// the authorization layer's key function (a GUID as itself, anything else
// as a digest of itself). Checking the alphabet again makes that a
// guarantee of this module rather than a promise from another: letters,
// digits and a dash, so no separator, no dot, no dot-dot and no empty name
// can name a file. A leading underscore is not a letter here on purpose:
// `_root.db` is the tenant registry, not an organisation, and the flat-store
// migration walks these names looking for one that claims a model.
@ __st_org_ok s org → b {
    : i n ( nurl_str_len org )
    ? | == n 0 > n 64 { ^ F } {}
    : ~ i k 0
    ~ < k n {
        : i c ( nurl_str_at org n k )
        : b digit & >= c 48 <= c 57
        : b lower & >= c 97 <= c 122
        : b upper & >= c 65 <= c 90
        : b dash == c 45
        ? | | | digit lower upper dash {} { ^ F }
        = k + k 1
    }
    ^ T
}

@ __st_orgs_dir s root → String {
    : String p ( string_from root )
    ( string_push_str p `/orgs` )
    ^ p
}

@ __st_db_path Store st → String {
    : String p ( __st_orgs_dir ( string_data . st root ) )
    ( string_push_char p 47 )
    ( string_push_str p ( string_data . st org ) )
    ( string_push_str p `.db` )
    ^ p
}

// The tables this module owns. `IF NOT EXISTS` throughout, so the
// authorization layer's schema and this one may each ensure their half of
// the same file, in either order, from any thread.
@ __st_schema → ( Vec String ) {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `CREATE TABLE IF NOT EXISTS models_meta (
        name TEXT PRIMARY KEY,
        meta TEXT NOT NULL
    )` ) )
    ( vec_push [String] v ( string_from `CREATE TABLE IF NOT EXISTS models_meta_corrupt (
        name TEXT NOT NULL,
        at INTEGER NOT NULL,
        meta TEXT NOT NULL
    )` ) )
    ( vec_push [String] v ( string_from `CREATE TABLE IF NOT EXISTS points (
        model TEXT NOT NULL,
        seq INTEGER NOT NULL,
        line TEXT NOT NULL,
        PRIMARY KEY (model, seq)
    )` ) )
    ( vec_push [String] v ( string_from `CREATE TABLE IF NOT EXISTS blobs (
        model TEXT NOT NULL,
        kind TEXT NOT NULL,
        data BLOB NOT NULL,
        PRIMARY KEY (model, kind)
    )` ) )
    ( vec_push [String] v ( string_from `CREATE TABLE IF NOT EXISTS labels (
        model TEXT NOT NULL,
        seq INTEGER NOT NULL,
        rec TEXT NOT NULL,
        PRIMARY KEY (model, seq)
    )` ) )
    ( vec_push [String] v ( string_from `CREATE TABLE IF NOT EXISTS audit (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        model TEXT NOT NULL,
        rec TEXT NOT NULL
    )` ) )
    ( vec_push [String] v ( string_from `CREATE INDEX IF NOT EXISTS audit_model ON audit (model, id)` ) )
    ^ v
}

// One connection for one operation. WAL is a property of the FILE and
// survives the connection; the busy timeout and the synchronous mode are
// per connection and are set here every time. NORMAL fsyncs at a
// checkpoint rather than at every commit: a power cut can cost the last
// commits, never the database — and the file store this replaces did not
// fsync at all.
@ __st_conn Store st → !Database SqliteErr {
    : String path ( __st_db_path st )
    ?? ( sqlite_open ( string_data path ) ) {
        F e → { ( string_free path ) ^ @ !Database SqliteErr { F e } }
        T db → {
            ( string_free path )
            ?? ( sqlite_busy_timeout db 5000 ) { T _ → {} F _ → {} }
            ?? ( sqlite_exec db `PRAGMA synchronous=NORMAL` ) { T _ → {} F _ → {} }
            ^ @ !Database SqliteErr { T db }
        }
    }
}

// Open the organisation's store: make the directory, put the database's
// journal into WAL and ensure this module's tables, once. Every operation
// after this opens its own connection for the length of the operation.
@ store_open_org s root s org → Store {
    ? ( __st_org_ok org ) {} {
        ^ @ Store { ( string_from root ) ( string_from org ) F }
    }
    : String dir ( __st_orgs_dir root )
    : !v IoErr mk ( dir_create_all ( string_data dir ) )
    ?? mk { T _ → {} F _ → {} }
    ( string_free dir )
    : Store st @ Store { ( string_from root ) ( string_from org ) T }
    : ~ b ok F
    ?? ( __st_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_exec db `PRAGMA journal_mode=WAL` ) { T _ → {} F _ → {} }
            : ( Vec String ) stmts ( __st_schema )
            : i n ( vec_len [String] stmts )
            : ~ b failed F
            : ~ i k 0
            ~ < k n {
                ?? ( vec_get [String] stmts k ) {
                    T sq → {
                        ?? ( sqlite_exec db ( string_data sq ) ) { T _ → {} F _ → { = failed T } }
                        ( string_free sq )
                    }
                    F _ → {}
                }
                = k + k 1
            }
            ( vec_free [String] stmts )
            = ok ! failed
        }
    }
    ( store_free st )
    ^ @ Store { ( string_from root ) ( string_from org ) ok }
}

// The organisation a store with no sign-in belongs to. Simple mode, the
// CLI and the analysis sandbox all collect into `public`, which is a real
// organisation with a real database — turning sign-in on later moves
// nothing.
@ store_open s root → Store { ^ ( store_open_org root ANOM_ORG_DEFAULT ) }

@ store_free sink Store st → v {
    ( string_free . st root )
    ( string_free . st org )
}

@ store_org Store st → s { ^ ( string_data . st org ) }

// ── Statement helpers ─────────────────────────────────────────────────

// Bind an owned String and free it — sqlite_bind_text copies immediately,
// so the two belong together and separating them is how a leak gets in.
@ __st_bind_str Statement q i idx String v → v {
    ?? ( sqlite_bind_text q idx v ) { T _ → {} F _ → {} }
    ( string_free v )
}

@ __st_bind_i Statement q i idx i v → v {
    ?? ( sqlite_bind_int q idx v ) { T _ → {} F _ → {} }
}

// Step to completion; F when a step failed.
@ __st_run Statement q → b {
    : ~ b ok T
    : ~ b done F
    ~ ! done {
        ?? ( sqlite_step q ) {
            F _ → { = ok F = done T }
            T has → { ? has {} { = done T } }
        }
    }
    ^ ok
}

// One statement whose only parameter is the model name.
@ __st_name_on Database db s sql s name → b {
    : ~ b ok F
    ?? ( sqlite_prepare db sql ) {
        F _ → {}
        T q → {
            ( __st_bind_str q 1 ( string_from name ) )
            = ok ( __st_run q )
        }
    }
    ^ ok
}

@ __st_begin Database db → b {
    : ~ b ok F
    ?? ( sqlite_exec db `BEGIN IMMEDIATE` ) { T _ → { = ok T } F _ → {} }
    ^ ok
}

@ __st_commit Database db → b {
    : ~ b ok F
    ?? ( sqlite_exec db `COMMIT` ) { T _ → { = ok T } F _ → {} }
    ^ ok
}

@ __st_rollback Database db → v {
    ?? ( sqlite_exec db `ROLLBACK` ) { T _ → {} F _ → {} }
}

// ── Blobs: forests, the autoencoder, the forecast, the score cache ────

@ __st_forest_kind s vname → String {
    : String k ( string_from `forest:` )
    ( string_push_str k vname )
    ^ k
}

@ __st_blob_put_on Database db s name s kind ( Vec u ) data → b {
    : ~ b ok F
    ?? ( sqlite_prepare db `INSERT OR REPLACE INTO blobs (model, kind, data) VALUES (?1, ?2, ?3)` ) {
        F _ → {}
        T q → {
            ( __st_bind_str q 1 ( string_from name ) )
            ( __st_bind_str q 2 ( string_from kind ) )
            ?? ( sqlite_bind_blob q 3 data ) { T _ → {} F _ → {} }
            = ok ( __st_run q )
        }
    }
    ^ ok
}

@ __st_blob_put Store st s name s kind ( Vec u ) data → b {
    ? . st ok {} { ^ F }
    : ~ b ok F
    ?? ( __st_conn st ) {
        F _ → {}
        T db → { = ok ( __st_blob_put_on db name kind data ) }
    }
    ^ ok
}

// The bytes of one blob, or None when the model has no such row.
@ __st_blob_get Store st s name s kind → ?( Vec u ) {
    ? . st ok {} { ^ @ ?( Vec u ) { F } }
    : ~ b found F
    : ~ ( Vec u ) out ( vec_new [u] )
    ?? ( __st_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db `SELECT data FROM blobs WHERE model = ?1 AND kind = ?2` ) {
                F _ → {}
                T q → {
                    ( __st_bind_str q 1 ( string_from name ) )
                    ( __st_bind_str q 2 ( string_from kind ) )
                    ?? ( sqlite_step q ) {
                        F _ → {}
                        T has → {
                            ? has {
                                ( vec_free [u] out )
                                = out ( sqlite_column_blob q 0 )
                                = found T
                            } {}
                        }
                    }
                }
            }
        }
    }
    ? found { ^ @ ?( Vec u ) { T out } } {}
    ( vec_free [u] out )
    ^ @ ?( Vec u ) { F }
}

@ __st_blob_del Store st s name s kind → v {
    ? . st ok {} { ^ v }
    ?? ( __st_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db `DELETE FROM blobs WHERE model = ?1 AND kind = ?2` ) {
                F _ → {}
                T q → {
                    ( __st_bind_str q 1 ( string_from name ) )
                    ( __st_bind_str q 2 ( string_from kind ) )
                    : b _r ( __st_run q )
                }
            }
        }
    }
}

// ── Existence and listing ─────────────────────────────────────────────

@ __st_exists_on Database db s name → b {
    : ~ b there F
    ?? ( sqlite_prepare db `SELECT 1 FROM models_meta WHERE name = ?1` ) {
        F _ → {}
        T q → {
            ( __st_bind_str q 1 ( string_from name ) )
            ?? ( sqlite_step q ) { T has → { = there has } F _ → {} }
        }
    }
    ^ there
}

// A model exists iff this organisation's database has its metadata row.
@ store_exists Store st s name → b {
    ? . st ok {} { ^ F }
    : ~ b there F
    ?? ( __st_conn st ) {
        F _ → {}
        T db → { = there ( __st_exists_on db name ) }
    }
    ^ there
}

// Every model in this organisation, by name, sorted.
@ store_list Store st → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    ? . st ok {} { ^ out }
    ?? ( __st_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db `SELECT name FROM models_meta ORDER BY name` ) {
                F _ → {}
                T q → {
                    : ~ b done F
                    ~ ! done {
                        ?? ( sqlite_step q ) {
                            F _ → { = done T }
                            T has → {
                                ? has { ( vec_push [String] out ( sqlite_column_text q 0 ) ) } { = done T }
                            }
                        }
                    }
                }
            }
        }
    }
    ^ out
}

// ── Metadata ──────────────────────────────────────────────────────────

@ __st_meta_put_on Database db s name String txt → b {
    : ~ b ok F
    ?? ( sqlite_prepare db `INSERT OR REPLACE INTO models_meta (name, meta) VALUES (?1, ?2)` ) {
        F _ → {}
        T q → {
            ( __st_bind_str q 1 ( string_from name ) )
            ( __st_bind_str q 2 txt )
            = ok ( __st_run q )
        }
    }
    ^ ok
}

@ store_save_meta Store st s name * Meta m → b {
    ? . st ok {} { ^ F }
    : String txt ( meta_to_json_str m )
    : ~ b ok F
    ?? ( __st_conn st ) {
        F _ → {}
        T db → { = ok ( __st_meta_put_on db name ( string_clone txt ) ) }
    }
    ( string_free txt )
    ^ ok
}

@ store_load_meta Store st s name → ?*Meta {
    ? . st ok {} { ^ @ ?*Meta { F } }
    : ~ b found F
    : ~ String txt ( string_new )
    ?? ( __st_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db `SELECT meta FROM models_meta WHERE name = ?1` ) {
                F _ → {}
                T q → {
                    ( __st_bind_str q 1 ( string_from name ) )
                    ?? ( sqlite_step q ) {
                        F _ → {}
                        T has → {
                            ? has {
                                ( string_free txt )
                                = txt ( sqlite_column_text q 0 )
                                = found T
                            } {}
                        }
                    }
                }
            }
        }
    }
    ? found {} { ( string_free txt ) ^ @ ?*Meta { F } }
    : ?*Meta m ( meta_from_json_str ( string_data txt ) )
    ( string_free txt )
    ^ m
}

// Set metadata that would not parse aside, with the time it happened, so
// a model can be reopened without destroying the evidence. Returns where
// it went (empty when there was nothing to move).
@ store_quarantine_meta Store st s name i now → String {
    ? . st ok {} { ^ ( string_new ) }
    : ~ b moved F
    ?? ( __st_conn st ) {
        F _ → {}
        T db → {
            ? ( __st_begin db ) {} {}
            ?? ( sqlite_prepare db `INSERT INTO models_meta_corrupt (name, at, meta)
                 SELECT name, ?2, meta FROM models_meta WHERE name = ?1` ) {
                F _ → {}
                T q → {
                    ( __st_bind_str q 1 ( string_from name ) )
                    ( __st_bind_i q 2 now )
                    ? ( __st_run q ) { = moved > ( sqlite_changes db ) 0 } {}
                }
            }
            ? moved { : b _d ( __st_name_on db `DELETE FROM models_meta WHERE name = ?1` name ) } {}
            : b _c ( __st_commit db )
        }
    }
    ? moved {} { ^ ( string_new ) }
    : String where ( string_from `models_meta_corrupt (` )
    ( string_push_str where name )
    ( string_push_str where ` at ` )
    ( string_push_int where now )
    ( string_push_char where 41 )
    ^ where
}

// ── Forests ───────────────────────────────────────────────────────────

@ store_save_forest Store st s name VerModel vm → b {
    : ( Vec u ) blob ( vermodel_to_bytes vm )
    : String kind ( __st_forest_kind ( string_data . vm vname ) )
    : b ok ( __st_blob_put st name ( string_data kind ) blob )
    ( string_free kind )
    ( vec_free [u] blob )
    ^ ok
}

// Load one version's forest; None if absent or corrupt. The blob's
// embedded version name must match the requested one — a moved or
// content-tampered blob is treated as corrupt, not trusted.
@ store_load_forest Store st s name s vname → ?VerModel {
    : String kind ( __st_forest_kind vname )
    : ?( Vec u ) got ( __st_blob_get st name ( string_data kind ) )
    ( string_free kind )
    ?? got {
        F _ → { ^ @ ?VerModel { F } }
        T blob → {
            : ?VerModel vm ( vermodel_from_bytes blob )
            ( vec_free [u] blob )
            ?? vm {
                T v → {
                    ? == ( nurl_str_eq ( string_data . v vname ) vname ) 1 {
                        ^ @ ?VerModel { T v }
                    } {
                        ( anom_vermodel_free v )
                        ^ @ ?VerModel { F }
                    }
                }
                F _ → { ^ @ ?VerModel { F } }
            }
        }
    }
}

@ store_delete_forest Store st s name s vname → v {
    : String kind ( __st_forest_kind vname )
    ( __st_blob_del st name ( string_data kind ) )
    ( string_free kind )
}

// ── The autoencoder and the forecast ──────────────────────────────────

@ store_save_ae Store st s name AeModel ae → b {
    : String txt ( ae_to_json_str ae )
    : ( Vec u ) data ( bytes_from_str ( string_data txt ) )
    : b ok ( __st_blob_put st name ANOM_KIND_AE data )
    ( vec_free [u] data )
    ( string_free txt )
    ^ ok
}

@ store_load_ae Store st s name → ?AeModel {
    ?? ( __st_blob_get st name ANOM_KIND_AE ) {
        F _ → { ^ @ ?AeModel { F } }
        T data → {
            : String txt ( string_from_bytes ( vec_data [u] data ) ( vec_len [u] data ) )
            ( vec_free [u] data )
            : ?AeModel m ( ae_from_json_str ( string_data txt ) )
            ( string_free txt )
            ^ m
        }
    }
}

@ store_save_fc Store st s name * FcModel fc → b {
    : String txt ( fc_to_json_str fc )
    : ( Vec u ) data ( bytes_from_str ( string_data txt ) )
    : b ok ( __st_blob_put st name ANOM_KIND_FC data )
    ( vec_free [u] data )
    ( string_free txt )
    ^ ok
}

@ store_load_fc Store st s name → ?*FcModel {
    ?? ( __st_blob_get st name ANOM_KIND_FC ) {
        F _ → { ^ @ ?*FcModel { F } }
        T data → {
            : String txt ( string_from_bytes ( vec_data [u] data ) ( vec_len [u] data ) )
            ( vec_free [u] data )
            : ?*FcModel m ( fc_from_json_str ( string_data txt ) )
            ( string_free txt )
            ^ m
        }
    }
}

@ store_delete_fc Store st s name → v {
    ( __st_blob_del st name ANOM_KIND_FC )
}

// ── Deleting a model ──────────────────────────────────────────────────

// Everything the model is, in one transaction: either the model is gone
// or it is untouched. The rows the file backend removed as a directory.
@ store_delete Store st s name → b {
    ? . st ok {} { ^ F }
    : ~ b ok F
    ?? ( __st_conn st ) {
        F _ → {}
        T db → {
            : b own ( __st_begin db )
            : ~ b good T
            ? ( __st_name_on db `DELETE FROM points WHERE model = ?1` name ) {} { = good F }
            ? ( __st_name_on db `DELETE FROM blobs WHERE model = ?1` name ) {} { = good F }
            ? ( __st_name_on db `DELETE FROM labels WHERE model = ?1` name ) {} { = good F }
            ? ( __st_name_on db `DELETE FROM audit WHERE model = ?1` name ) {} { = good F }
            ? ( __st_name_on db `DELETE FROM models_meta_corrupt WHERE name = ?1` name ) {} { = good F }
            ? ( __st_name_on db `DELETE FROM models_meta WHERE name = ?1` name ) {} { = good F }
            ? own {
                ? good { ? ( __st_commit db ) {} { = good F } } { ( __st_rollback db ) }
            } {}
            = ok good
        }
    }
    ^ ok
}

// ── The scored-verdict cache, as a blob ───────────────────────────────

@ store_save_scores Store st s name ScoreCache c → b {
    ? . st ok {} { ^ F }
    : ( Vec u ) out ( vec_new [u] )
    ( bytes_extend_str out `ANOMSCR2` )
    ( bytes_push_u64_le out # u64 . c epoch )
    ( bytes_push_u64_le out # u64 . c base_seen )
    : i nv ( vec_len [String] . c vnames )
    ( bytes_push_u64_le out # u64 nv )
    : ~ i k 0
    ~ < k nv {
        ?? ( vec_get [String] . c vnames k ) {
            T nm → {
                ( bytes_push_u64_le out # u64 ( string_len nm ) )
                ( bytes_extend_str out ( string_data nm ) )
            }
            F _ → {}
        }
        = k + k 1
    }
    : i nr ( vec_len [i] . c state )
    ( bytes_push_u64_le out # u64 nr )
    : *i stp ( vec_data [i] . c state )
    : *f scp ( vec_data [f] . c score )
    : *f svp ( vec_data [f] . c severity )
    : *i prp ( vec_data [i] . c present )
    : *i flp ( vec_data [i] . c flagged )
    = k 0
    ~ < k nr {
        ( bytes_push_f64_le out . scp k )
        ( bytes_push_f64_le out . svp k )
        ( bytes_push_u64_le out # u64 . stp k )
        ( bytes_push_u64_le out # u64 . prp k )
        ( bytes_push_u64_le out # u64 . flp k )
        = k + k 1
    }
    : b ok ( __st_blob_put st name ANOM_KIND_SCORES out )
    ( vec_free [u] out )
    ^ ok
}

// Load the cache; None when absent, truncated or structurally impossible.
// A rejected cache costs a rescan, never a wrong verdict.
@ store_load_scores Store st s name → ?ScoreCache {
    ?? ( __st_blob_get st name ANOM_KIND_SCORES ) {
        T buf → {
            // ANOMSCR1 aggregated by minimum decision value; 2 by the
            // most severe version. An old cache is a miss, never a
            // wrong number.
            : ( Vec u ) magic ( bytes_from_str `ANOMSCR2` )
            : b magic_ok ( bytes_starts_with buf magic )
            ( vec_free [u] magic )
            ? magic_ok {} {
                ( vec_free [u] buf )
                ^ @ ?ScoreCache { F }
            }
            : *BlobRd rd ( __an_rd_new buf )
            = . rd pos 8
            : i epoch ( __an_rd_u64 rd )
            : i base ( __an_rd_u64 rd )
            : i nv ( __an_rd_u64 rd )
            ? || < nv 0 > nv ANOM_SC_MAX_VERS { = . rd ok F } {}
            : ScoreCache c ( scorecache_new epoch base )
            : ~ i k 0
            ~ & . rd ok < k nv {
                : i nlen ( __an_rd_u64 rd )
                ? || < nlen 0 > nlen ANOM_BLOB_MAX_NAME { = . rd ok F } {
                    : i n ( vec_len [u] buf )
                    ? > + . rd pos nlen n { = . rd ok F } {
                        : *u bp ( vec_data [u] buf )
                        : i base2 + # i bp . rd pos
                        ( vec_push [String] . c vnames ( string_from_bytes # *u base2 nlen ) )
                        = . rd pos + . rd pos nlen
                    }
                }
                = k + k 1
            }
            : i nr ( __an_rd_u64 rd )
            ? || < nr 0 > nr ANOM_SC_MAX_ROWS { = . rd ok F } {}
            : ~ i safe nr
            ? . rd ok {} { = safe 0 }
            ( vec_reserve [i] . c state safe )
            ( vec_reserve [f] . c score safe )
            ( vec_reserve [f] . c severity safe )
            ( vec_reserve [i] . c present safe )
            ( vec_reserve [i] . c flagged safe )
            = k 0
            ~ & . rd ok < k safe {
                ( vec_push [f] . c score ( __an_rd_f64 rd ) )
                ( vec_push [f] . c severity ( __an_rd_f64 rd ) )
                ( vec_push [i] . c state ( __an_rd_u64 rd ) )
                ( vec_push [i] . c present ( __an_rd_u64 rd ) )
                ( vec_push [i] . c flagged ( __an_rd_u64 rd ) )
                = k + k 1
            }
            // Trailing garbage after a well-formed body is corruption too.
            ? == . rd pos ( vec_len [u] buf ) {} { = . rd ok F }
            : b good . rd ok
            ( nurl_free rd )
            ( vec_free [u] buf )
            ? good { ^ @ ?ScoreCache { T c } } {}
            ( scorecache_free c )
            ^ @ ?ScoreCache { F }
        }
        F _ → { ^ @ ?ScoreCache { F } }
    }
}

@ store_delete_scores Store st s name → v {
    ( __st_blob_del st name ANOM_KIND_SCORES )
}

// ── The ring of raw points ────────────────────────────────────────────
//
// One row per stored point: the raw JSON record as it arrived, plus the
// server-side timestamp, kept raw so a retrain can re-encode it with
// categories learned since. `seq` is the point's LIFETIME number — the
// space `Meta.n_seen` counts in, the space labels and the score cache are
// keyed in — so the ring is the rows with the largest `seq`, and dropping
// the oldest renumbers nothing.

@ __st_point_put_on Database db s name i seq s line → b {
    : ~ b ok F
    ?? ( sqlite_prepare db `INSERT OR REPLACE INTO points (model, seq, line) VALUES (?1, ?2, ?3)` ) {
        F _ → {}
        T q → {
            ( __st_bind_str q 1 ( string_from name ) )
            ( __st_bind_i q 2 seq )
            ( __st_bind_str q 3 ( string_from line ) )
            = ok ( __st_run q )
        }
    }
    ^ ok
}

@ __st_evict_on Database db s name i from_seq → b {
    : ~ b ok F
    ?? ( sqlite_prepare db `DELETE FROM points WHERE model = ?1 AND seq < ?2` ) {
        F _ → {}
        T q → {
            ( __st_bind_str q 1 ( string_from name ) )
            ( __st_bind_i q 2 from_seq )
            = ok ( __st_run q )
        }
    }
    ^ ok
}

// One ingested point, as one transaction: the row, the eviction it may
// cause, and the metadata whose counter says how many points there are.
// A crash between them would leave the ring and `n_seen` disagreeing, and
// another thread must never read the ring half-updated. `evict_before` is
// the lifetime number of the oldest row to keep (0 evicts nothing).
@ store_commit_point Store st s name i seq s line i evict_before * Meta m → b {
    ? . st ok {} { ^ F }
    : String txt ( meta_to_json_str m )
    : ~ b ok F
    ?? ( __st_conn st ) {
        F _ → {}
        T db → {
            : b own ( __st_begin db )
            : ~ b good ( __st_point_put_on db name seq line )
            ? & good > evict_before 0 {
                ? ( __st_evict_on db name evict_before ) {} { = good F }
            } {}
            ? good { ? ( __st_meta_put_on db name ( string_clone txt ) ) {} { = good F } } {}
            ? own {
                ? good { ? ( __st_commit db ) {} { = good F } } { ( __st_rollback db ) }
            } {}
            = ok good
        }
    }
    ( string_free txt )
    ^ ok
}

// Drop every point older than `from_seq`.
@ store_evict_points Store st s name i from_seq → b {
    ? . st ok {} { ^ F }
    : ~ b ok F
    ?? ( __st_conn st ) {
        F _ → {}
        T db → { = ok ( __st_evict_on db name from_seq ) }
    }
    ^ ok
}

// Replace the whole ring: `lines` become the points from `base_seq` on.
// Used where the ring is rebuilt rather than extended — a reset, a file of
// history imported, a cap lowered below the fill. One transaction.
@ store_write_points Store st s name ( Vec String ) lines i base_seq → b {
    ? . st ok {} { ^ F }
    : ~ b ok F
    ?? ( __st_conn st ) {
        F _ → {}
        T db → {
            : b own ( __st_begin db )
            : ~ b good ( __st_name_on db `DELETE FROM points WHERE model = ?1` name )
            : i n ( vec_len [String] lines )
            : ~ i k 0
            ~ & good < k n {
                ?? ( vec_get [String] lines k ) {
                    T l → {
                        ? ( __st_point_put_on db name + base_seq k ( string_data l ) ) {} { = good F }
                    }
                    F _ → {}
                }
                = k + k 1
            }
            ? own {
                ? good { ? ( __st_commit db ) {} { = good F } } { ( __st_rollback db ) }
            } {}
            = ok good
        }
    }
    ^ ok
}

// The ring in order, oldest first. Owned lines.
@ store_load_points Store st s name → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    ? . st ok {} { ^ out }
    ?? ( __st_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db `SELECT line FROM points WHERE model = ?1 ORDER BY seq` ) {
                F _ → {}
                T q → {
                    ( __st_bind_str q 1 ( string_from name ) )
                    : ~ b done F
                    ~ ! done {
                        ?? ( sqlite_step q ) {
                            F _ → { = done T }
                            T has → {
                                ? has { ( vec_push [String] out ( sqlite_column_text q 0 ) ) } { = done T }
                            }
                        }
                    }
                }
            }
        }
    }
    ^ out
}

// The newest `n` points, oldest first — what scoring one point actually
// needs, without reading a ring that may hold a hundred thousand rows.
@ store_load_points_tail Store st s name i n → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    ? & . st ok > n 0 {} { ^ out }
    ?? ( __st_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db `SELECT line FROM (
                     SELECT seq, line FROM points WHERE model = ?1 ORDER BY seq DESC LIMIT ?2
                 ) ORDER BY seq` ) {
                F _ → {}
                T q → {
                    ( __st_bind_str q 1 ( string_from name ) )
                    ( __st_bind_i q 2 n )
                    : ~ b done F
                    ~ ! done {
                        ?? ( sqlite_step q ) {
                            F _ → { = done T }
                            T has → {
                                ? has { ( vec_push [String] out ( sqlite_column_text q 0 ) ) } { = done T }
                            }
                        }
                    }
                }
            }
        }
    }
    ^ out
}

// How many points the model holds.
@ store_points_count Store st s name → i {
    ? . st ok {} { ^ 0 }
    : ~ i n 0
    ?? ( __st_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db `SELECT COUNT(*) FROM points WHERE model = ?1` ) {
                F _ → {}
                T q → {
                    ( __st_bind_str q 1 ( string_from name ) )
                    ?? ( sqlite_step q ) { T has → { ? has { = n ( sqlite_column_int q 0 ) } {} } F _ → {} }
                }
            }
        }
    }
    ^ n
}

// ── Labels ────────────────────────────────────────────────────────────
//
// One row per labelled point, keyed by the point's lifetime sequence
// number. Last write wins is the primary key doing it, and `none`
// withdraws by deleting the row — the flat store replayed a log and
// removed earlier entries in an O(n²) scan to reach the same state.

@ __st_label_put_on Database db s name Label l → b {
    ? == ( nurl_str_eq ( string_data . l label ) ANOM_LABEL_NONE ) 1 {
        : ~ b okd F
        ?? ( sqlite_prepare db `DELETE FROM labels WHERE model = ?1 AND seq = ?2` ) {
            F _ → {}
            T q → {
                ( __st_bind_str q 1 ( string_from name ) )
                ( __st_bind_i q 2 . l seq )
                = okd ( __st_run q )
            }
        }
        ^ okd
    } {}
    : Json o ( label_to_json l )
    : String txt ( json_stringify o )
    ( json_free o )
    : ~ b ok F
    ?? ( sqlite_prepare db `INSERT OR REPLACE INTO labels (model, seq, rec) VALUES (?1, ?2, ?3)` ) {
        F _ → {}
        T q → {
            ( __st_bind_str q 1 ( string_from name ) )
            ( __st_bind_i q 2 . l seq )
            ( __st_bind_str q 3 ( string_clone txt ) )
            = ok ( __st_run q )
        }
    }
    ( string_free txt )
    ^ ok
}

@ store_append_label Store st s name Label l → b {
    ? . st ok {} { ^ F }
    : ~ b ok F
    ?? ( __st_conn st ) {
        F _ → {}
        T db → { = ok ( __st_label_put_on db name l ) }
    }
    ^ ok
}

// The labels in force. Ascending by seq is not promised — a reader wanting
// the ring order joins on seq (model_label_map).
@ store_load_labels Store st s name → ( Vec Label ) {
    : ( Vec Label ) out ( vec_new [Label] )
    ? . st ok {} { ^ out }
    ?? ( __st_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db `SELECT rec FROM labels WHERE model = ?1 ORDER BY seq` ) {
                F _ → {}
                T q → {
                    ( __st_bind_str q 1 ( string_from name ) )
                    : ~ b done F
                    ~ ! done {
                        ?? ( sqlite_step q ) {
                            F _ → { = done T }
                            T has → {
                                ? has {
                                    : String rec ( sqlite_column_text q 0 )
                                    ?? ( json_parse ( string_data rec ) ) {
                                        T j → {
                                            ? ( json_is_obj j ) {
                                                : i seq ( __an_label_int j `seq` )
                                                : String lab ( __an_label_str j `label` )
                                                ? & >= seq 0 ( label_known ( string_data lab ) ) {
                                                    ( vec_push [Label] out @ Label {
                                                        seq
                                                        ( __an_label_int j `timestamp` )
                                                        lab
                                                        ( __an_label_str j `by` )
                                                        ( __an_label_int j `at` )
                                                        ( __an_label_str j `note` )
                                                    } )
                                                } { ( string_free lab ) }
                                            } {}
                                            ( json_free j )
                                        }
                                        F _ → {}
                                    }
                                    ( string_free rec )
                                } { = done T }
                            }
                        }
                    }
                }
            }
        }
    }
    ^ out
}

@ store_delete_labels Store st s name → v {
    ? . st ok {} { ^ v }
    ?? ( __st_conn st ) {
        F _ → {}
        T db → { : b _r ( __st_name_on db `DELETE FROM labels WHERE model = ?1` name ) }
    }
}

// ── The audit log ─────────────────────────────────────────────────────

@ __st_audit_put_on Database db s name Json ent → b {
    : String txt ( json_stringify ent )
    : ~ b ok F
    ?? ( sqlite_prepare db `INSERT INTO audit (model, rec) VALUES (?1, ?2)` ) {
        F _ → {}
        T q → {
            ( __st_bind_str q 1 ( string_from name ) )
            ( __st_bind_str q 2 ( string_clone txt ) )
            = ok ( __st_run q )
        }
    }
    ( string_free txt )
    ^ ok
}

@ store_append_audit Store st s name Json ent → b {
    ? . st ok {} { ^ F }
    : ~ b ok F
    ?? ( __st_conn st ) {
        F _ → {}
        T db → { = ok ( __st_audit_put_on db name ent ) }
    }
    ^ ok
}

// The newest `limit` entries, oldest first (all when limit <= 0). Taken by
// the index rather than by reading the whole log and dropping the front.
@ store_load_audit Store st s name i limit → Json {
    : Json arr ( json_arr_new )
    ? . st ok {} { ^ arr }
    : ~ i lim -1
    ? > limit 0 { = lim limit } {}
    : ( Vec String ) rows ( vec_new [String] )
    ?? ( __st_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db `SELECT rec FROM audit WHERE model = ?1 ORDER BY id DESC LIMIT ?2` ) {
                F _ → {}
                T q → {
                    ( __st_bind_str q 1 ( string_from name ) )
                    ( __st_bind_i q 2 lim )
                    : ~ b done F
                    ~ ! done {
                        ?? ( sqlite_step q ) {
                            F _ → { = done T }
                            T has → {
                                ? has { ( vec_push [String] rows ( sqlite_column_text q 0 ) ) } { = done T }
                            }
                        }
                    }
                }
            }
        }
    }
    : i n ( vec_len [String] rows )
    : ~ i k n
    ~ > k 0 {
        = k - k 1
        ?? ( vec_get [String] rows k ) {
            T l → { ?? ( json_parse ( string_data l ) ) { T j → { ( json_arr_push arr j ) } F _ → {} } }
            F _ → {}
        }
    }
    ( vec_free_with [String] rows \ String x → v { ( string_free x ) } )
    ^ arr
}

// ── Migrating a model out of the flat store ───────────────────────────
//
// Before this, a model was a directory of files under the store root,
// shared by every organisation, with ownership recorded on the side. The
// move is a one-way trip taken once at startup: the rows go into the
// owning organisation's database and the directory is MOVED ASIDE under
// <root>/migrated-<time>/ rather than deleted, so an upgrade destroys
// nothing and a rollback is a directory move back.

@ __st_starts s hay s pre → b {
    : i hn ( nurl_str_len hay )
    : i pn ( nurl_str_len pre )
    ? > pn hn { ^ F } {}
    : ~ i k 0
    ~ < k pn {
        ? == ( nurl_str_at hay hn k ) ( nurl_str_at pre pn k ) {} { ^ F }
        = k + k 1
    }
    ^ T
}

@ __st_ends s hay s suf → b {
    : i hn ( nurl_str_len hay )
    : i sn ( nurl_str_len suf )
    ? > sn hn { ^ F } {}
    : ~ i k 0
    ~ < k sn {
        ? == ( nurl_str_at hay hn + - hn sn k ) ( nurl_str_at suf sn k ) {} { ^ F }
        = k + k 1
    }
    ^ T
}

@ __st_flat_file s root s name s file → String {
    : String p ( string_from root )
    ( string_push_char p 47 )
    ( string_push_str p name )
    ( string_push_char p 47 )
    ( string_push_str p file )
    ^ p
}

// Read one file of a flat model directory as text; empty when absent.
@ __st_flat_text s root s name s file → String {
    : String p ( __st_flat_file root name file )
    : !String IoErr r ( read_file ( string_data p ) )
    ( string_free p )
    ?? r { T txt → { ^ txt } F _ → { ^ ( string_new ) } }
}

// Copy one file of a flat model directory into a blob row.
@ __st_flat_blob s root s name s file Store st s kind → b {
    : String p ( __st_flat_file root name file )
    : !( Vec u ) IoErr r ( read_file_bytes ( string_data p ) )
    ( string_free p )
    ?? r {
        T data → {
            : b ok ( __st_blob_put st name kind data )
            ( vec_free [u] data )
            ^ ok
        }
        F _ → { ^ T }
    }
}

// One flat model directory into this organisation's database.
@ store_migrate_dir Store st s root s name i now → b {
    ? . st ok {} { ^ F }
    : String meta ( __st_flat_text root name `metadata.json` )
    ? > ( string_len meta ) 0 {} { ( string_free meta ) ^ F }

    // The lifetime number of the ring's oldest row: what the metadata
    // counted minus what the log holds. Metadata that does not parse is
    // stored as it is, so the loader quarantines it exactly as it would
    // have quarantined the file.
    : String log ( __st_flat_text root name `data.jsonl` )
    : ( Vec String ) raw ( string_split log `\n` )
    : ( Vec String ) lines ( vec_new [String] )
    : i nraw ( vec_len [String] raw )
    : ~ i k 0
    ~ < k nraw {
        ?? ( vec_get [String] raw k ) {
            T l → { ? > ( string_len l ) 0 { ( vec_push [String] lines ( string_clone l ) ) } {} }
            F _ → {}
        }
        = k + k 1
    }
    ( vec_free_with [String] raw \ String x → v { ( string_free x ) } )
    ( string_free log )
    : ~ i seen ( vec_len [String] lines )
    ?? ( meta_from_json_str ( string_data meta ) ) {
        T m → { = seen . m n_seen ( meta_free m ) }
        F _ → {}
    }
    : ~ i base - seen ( vec_len [String] lines )
    ? < base 0 { = base 0 } {}

    // The metadata row and the organisation's ownership row, in one
    // transaction. A blank subject is the same "nobody in particular, but
    // the organisation's" the authorization layer already uses for a
    // member who has left; the INSERT is ignored when that table is not
    // there yet, which only happens before anyone has signed in.
    : ~ b ok F
    ?? ( __st_conn st ) {
        F _ → {}
        T db → {
            : b own ( __st_begin db )
            ? ( __st_meta_put_on db name ( string_clone meta ) ) { = ok T } {}
            ? ok {
                ?? ( sqlite_prepare db `INSERT OR IGNORE INTO models (name, owner_sub, created_at) VALUES (?1, ?2, ?3)` ) {
                    F _ → {}
                    T q → {
                        ( __st_bind_str q 1 ( string_from name ) )
                        ( __st_bind_str q 2 ( string_new ) )
                        ( __st_bind_i q 3 now )
                        : b _w ( __st_run q )
                    }
                }
            } {}
            ? own { ? ok { ? ( __st_commit db ) {} { = ok F } } { ( __st_rollback db ) } } {}
        }
    }
    ( string_free meta )

    ? ok { ? ( store_write_points st name lines base ) {} { = ok F } } {}
    ( vec_free_with [String] lines \ String x → v { ( string_free x ) } )

    // The blobs: one forest per trained version, plus the autoencoder,
    // the forecast and the score cache when they exist.
    ? ok {
        : String dir ( string_from root )
        ( string_push_char dir 47 )
        ( string_push_str dir name )
        ?? ( dir_list ( string_data dir ) ) {
            T entries → {
                : i ne ( vec_len [String] entries )
                : ~ i e 0
                ~ < e ne {
                    ?? ( vec_get [String] entries e ) {
                        T fn → {
                            : s f ( string_data fn )
                            ? & ( __st_starts f `version_` ) ( __st_ends f `.forest` ) {
                                : i fl ( nurl_str_len f )
                                : String vn ( string_new )
                                : ~ i c 8
                                ~ < c - fl 7 { ( string_push_char vn ( nurl_str_at f fl c ) ) = c + c 1 }
                                : String kind ( __st_forest_kind ( string_data vn ) )
                                ? ( __st_flat_blob root name f st ( string_data kind ) ) {} { = ok F }
                                ( string_free kind )
                                ( string_free vn )
                            } {}
                        }
                        F _ → {}
                    }
                    = e + e 1
                }
                ( vec_free_with [String] entries \ String x → v { ( string_free x ) } )
            }
            F _ → {}
        }
        ( string_free dir )
    } {}

    ? ok { ? ( __st_flat_blob root name `autoencoder.json` st ANOM_KIND_AE ) {} { = ok F } } {}
    ? ok { ? ( __st_flat_blob root name `forecast.json` st ANOM_KIND_FC ) {} { = ok F } } {}
    ? ok { ? ( __st_flat_blob root name `scores.bin` st ANOM_KIND_SCORES ) {} { = ok F } } {}

    // Labels and the audit log, replayed in file order so the last word
    // on a sequence number is the one that survives.
    ? ok {
        : String lab ( __st_flat_text root name `labels.jsonl` )
        : ( Vec String ) ls ( string_split lab `\n` )
        : i nl ( vec_len [String] ls )
        : ~ i j 0
        ~ < j nl {
            ?? ( vec_get [String] ls j ) {
                T l → {
                    ? > ( string_len l ) 0 {
                        ?? ( json_parse ( string_data l ) ) {
                            T o → {
                                ? ( json_is_obj o ) {
                                    : i seq ( __an_label_int o `seq` )
                                    : String lb ( __an_label_str o `label` )
                                    ? & >= seq 0 ( label_known ( string_data lb ) ) {
                                        : Label one @ Label {
                                            seq
                                            ( __an_label_int o `timestamp` )
                                            lb
                                            ( __an_label_str o `by` )
                                            ( __an_label_int o `at` )
                                            ( __an_label_str o `note` )
                                        }
                                        : b _w ( store_append_label st name one )
                                        ( label_free one )
                                    } { ( string_free lb ) }
                                } {}
                                ( json_free o )
                            }
                            F _ → {}
                        }
                    } {}
                }
                F _ → {}
            }
            = j + j 1
        }
        ( vec_free_with [String] ls \ String x → v { ( string_free x ) } )
        ( string_free lab )
    } {}

    ? ok {
        : String aud ( __st_flat_text root name `audit.jsonl` )
        : ( Vec String ) as ( string_split aud `\n` )
        : i na ( vec_len [String] as )
        : ~ i j 0
        ~ < j na {
            ?? ( vec_get [String] as j ) {
                T l → {
                    ? > ( string_len l ) 0 {
                        ?? ( json_parse ( string_data l ) ) {
                            T o → { : b _w ( store_append_audit st name o ) ( json_free o ) }
                            F _ → {}
                        }
                    } {}
                }
                F _ → {}
            }
            = j + j 1
        }
        ( vec_free_with [String] as \ String x → v { ( string_free x ) } )
        ( string_free aud )
    } {}

    ^ ok
}

// The organisation whose database claims this model name, `public` when
// none does — which is also the answer with sign-in off, where the
// public organisation is the only one there is.
@ __st_owner_org s root s name → String {
    : String dir ( __st_orgs_dir root )
    : ~ String found ( string_new )
    ?? ( dir_list ( string_data dir ) ) {
        T entries → {
            : i n ( vec_len [String] entries )
            : ~ i k 0
            ~ < k n {
                ?? ( vec_get [String] entries k ) {
                    T e → {
                        : s en ( string_data e )
                        ? & == ( string_len found ) 0 ( __st_ends en `.db` ) {
                            : i el ( nurl_str_len en )
                            : String org ( string_new )
                            : ~ i c 0
                            ~ < c - el 3 { ( string_push_char org ( nurl_str_at en el c ) ) = c + c 1 }
                            ? ( __st_org_ok ( string_data org ) ) {
                                : Store probe ( store_open_org root ( string_data org ) )
                                ? . probe ok {
                                    ?? ( __st_conn probe ) {
                                        F _ → {}
                                        T pdb → {
                                            ?? ( sqlite_prepare pdb `SELECT 1 FROM models WHERE name = ?1` ) {
                                                F _ → {}
                                                T q → {
                                                    ( __st_bind_str q 1 ( string_from name ) )
                                                    ?? ( sqlite_step q ) {
                                                        T has → {
                                                            ? has {
                                                                ( string_free found )
                                                                = found ( string_from ( string_data org ) )
                                                            } {}
                                                        }
                                                        F _ → {}
                                                    }
                                                }
                                            }
                                        }
                                    }
                                } {}
                                ( store_free probe )
                            } {}
                            ( string_free org )
                        } {}
                    }
                    F _ → {}
                }
                = k + k 1
            }
            ( vec_free_with [String] entries \ String x → v { ( string_free x ) } )
        }
        F _ → {}
    }
    ( string_free dir )
    ? > ( string_len found ) 0 { ^ found } {}
    ( string_free found )
    ^ ( string_from ANOM_ORG_DEFAULT )
}

// Every flat model directory left under `root`, moved into the database
// of the organisation that owns it. Returns how many moved. Called once
// at startup; when there is nothing to move it costs one directory read.
@ store_migrate_flat s root i now → i {
    : ~ i moved 0
    : String aside ( string_from root )
    ( string_push_str aside `/migrated-` )
    ( string_push_int aside now )
    ?? ( dir_list root ) {
        T entries → {
            : i n ( vec_len [String] entries )
            : ~ i k 0
            ~ < k n {
                ?? ( vec_get [String] entries k ) {
                    T e → {
                        : s en ( string_data e )
                        : b skip | ( __st_starts en `migrated-` ) == ( nurl_str_eq en `orgs` ) 1
                        ? skip {} {
                            : String probe ( __st_flat_file root en `metadata.json` )
                            : b is_model ( file_exists ( string_data probe ) )
                            ( string_free probe )
                            ? is_model {
                                : String org ( __st_owner_org root en )
                                : Store st ( store_open_org root ( string_data org ) )
                                : b ok ( store_migrate_dir st root en now )
                                ( store_free st )
                                ? ok {
                                    : !v IoErr mk ( dir_create_all ( string_data aside ) )
                                    ?? mk { T _ → {} F _ → {} }
                                    : String from ( string_from root )
                                    ( string_push_char from 47 )
                                    ( string_push_str from en )
                                    : String to ( string_clone aside )
                                    ( string_push_char to 47 )
                                    ( string_push_str to en )
                                    : !v IoErr mv ( fs_rename ( string_data from ) ( string_data to ) )
                                    ?? mv { T _ → { = moved + moved 1 } F _ → {} }
                                    ( string_free from )
                                    ( string_free to )
                                } {}
                                ( string_free org )
                            } {}
                        }
                    }
                    F _ → {}
                }
                = k + k 1
            }
            ( vec_free_with [String] entries \ String x → v { ( string_free x ) } )
        }
        F _ → {}
    }
    ( string_free aside )
    ^ moved
}

// ── Moving a model between organisations ──────────────────────────────
//
// Adoption. A point that arrives without a credential naming an owner
// lands in `public`, which is where such data waits rather than an
// organisation with a claim on it; the home organisation may then take
// it. When the store was one flat directory that was a row rewrite —
// nothing moved. Now the model IS rows in a file, so adopting it means
// carrying every one of them into the other file and removing them here.

// Every blob kind this model has.
@ __st_blob_kinds Store st s name → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    ? . st ok {} { ^ out }
    ?? ( __st_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db `SELECT kind FROM blobs WHERE model = ?1 ORDER BY kind` ) {
                F _ → {}
                T q → {
                    ( __st_bind_str q 1 ( string_from name ) )
                    : ~ b done F
                    ~ ! done {
                        ?? ( sqlite_step q ) {
                            F _ → { = done T }
                            T has → {
                                ? has { ( vec_push [String] out ( sqlite_column_text q 0 ) ) } { = done T }
                            }
                        }
                    }
                }
            }
        }
    }
    ^ out
}

// The metadata exactly as stored, unparsed. Empty when there is no row.
@ __st_meta_text Store st s name → String {
    : ~ String txt ( string_new )
    ? . st ok {} { ^ txt }
    ?? ( __st_conn st ) {
        F _ → {}
        T db → {
            ?? ( sqlite_prepare db `SELECT meta FROM models_meta WHERE name = ?1` ) {
                F _ → {}
                T q → {
                    ( __st_bind_str q 1 ( string_from name ) )
                    ?? ( sqlite_step q ) {
                        F _ → {}
                        T has → {
                            ? has { ( string_free txt ) = txt ( sqlite_column_text q 0 ) } {}
                        }
                    }
                }
            }
        }
    }
    ^ txt
}

// Everything `name` is, from `src` into `dst`. Refuses when `dst` already
// has that name — two models of one name in one organisation is exactly
// what the organisation-as-database rule exists to prevent. The source
// keeps its rows if any part of the write fails.
@ store_move_model Store src Store dst s name i now → b {
    ? & . src ok . dst ok {} { ^ F }
    ? ( store_exists src name ) {} { ^ F }
    ? ( store_exists dst name ) { ^ F } {}

    : String meta ( __st_meta_text src name )
    ? > ( string_len meta ) 0 {} { ( string_free meta ) ^ F }
    : ~ i seen 0
    ?? ( meta_from_json_str ( string_data meta ) ) {
        T m → { = seen . m n_seen ( meta_free m ) }
        F _ → {}
    }
    : ( Vec String ) lines ( store_load_points src name )
    : ~ i base - seen ( vec_len [String] lines )
    ? < base 0 { = base 0 } {}

    : ~ b ok F
    ?? ( __st_conn dst ) {
        F _ → {}
        T db → {
            : b own ( __st_begin db )
            : ~ b good ( __st_meta_put_on db name ( string_clone meta ) )
            : i n ( vec_len [String] lines )
            : ~ i k 0
            ~ & good < k n {
                ?? ( vec_get [String] lines k ) {
                    T l → { ? ( __st_point_put_on db name + base k ( string_data l ) ) {} { = good F } }
                    F _ → {}
                }
                = k + k 1
            }
            ? good {
                ?? ( sqlite_prepare db `INSERT OR IGNORE INTO models (name, owner_sub, created_at) VALUES (?1, ?2, ?3)` ) {
                    F _ → {}
                    T q → {
                        ( __st_bind_str q 1 ( string_from name ) )
                        ( __st_bind_str q 2 ( string_new ) )
                        ( __st_bind_i q 3 now )
                        : b _w ( __st_run q )
                    }
                }
            } {}
            ? own {
                ? good { ? ( __st_commit db ) {} { = good F } } { ( __st_rollback db ) }
            } {}
            = ok good
        }
    }
    ( vec_free_with [String] lines \ String x → v { ( string_free x ) } )
    ( string_free meta )
    ? ok {} { ^ F }

    // The blobs, the labels and the audit trail, each read from the source
    // and written to the destination through the ordinary calls.
    : ( Vec String ) kinds ( __st_blob_kinds src name )
    : i nk ( vec_len [String] kinds )
    : ~ i j 0
    ~ < j nk {
        ?? ( vec_get [String] kinds j ) {
            T kd → {
                ?? ( __st_blob_get src name ( string_data kd ) ) {
                    T data → {
                        ? ( __st_blob_put dst name ( string_data kd ) data ) {} { = ok F }
                        ( vec_free [u] data )
                    }
                    F _ → {}
                }
            }
            F _ → {}
        }
        = j + j 1
    }
    ( vec_free_with [String] kinds \ String x → v { ( string_free x ) } )

    : ( Vec Label ) labs ( store_load_labels src name )
    : i nl ( vec_len [Label] labs )
    = j 0
    ~ < j nl {
        ?? ( vec_get [Label] labs j ) { T l → { : b _w ( store_append_label dst name l ) } F _ → {} }
        = j + j 1
    }
    ( labels_free labs )

    : Json aud ( store_load_audit src name 0 )
    : i na ( json_arr_len aud )
    = j 0
    ~ < j na {
        ?? ( json_arr_get aud j ) { T e → { : b _w ( store_append_audit dst name e ) } F _ → {} }
        = j + j 1
    }
    ( json_free aud )

    ? ok { ? ( store_delete src name ) {} { = ok F } } {}
    ? ok {
        ?? ( __st_conn src ) {
            F _ → {}
            T db → { : b _d ( __st_name_on db `DELETE FROM models WHERE name = ?1` name ) }
        }
    } {}
    ^ ok
}
