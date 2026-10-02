// packages/lsmdb/src/wal.nu — the write-ahead log.
//
// The memtable lives in RAM, so between a write being acknowledged and
// the next flush there is nothing on disk that remembers it. The log is
// that memory: every write is appended here and fsynced BEFORE the
// memtable is touched, so a database that is killed — kill -9, power
// loss, a full disk mid-write — comes back holding exactly the writes it
// said yes to.
//
// Record framing:
//   [u32 crc32(payload)][u32 payload_len][payload]
//   payload = [u64 seq][u8 kind][u32 klen][key][u32 vlen][value]
//
// The checksum is what makes the tail case safe. A crash in the middle
// of an append leaves a short or half-written record, and replay MUST
// treat that as "this write never happened" rather than as corruption of
// the whole log or, worse, as a record with a garbage length. Replay
// therefore stops at the first record that is short, over-long or fails
// its CRC, keeps everything before it, and reports the truncation.
//
//   ( wal_open path )                  → !Wal String      append mode
//   ( wal_append w key val seq kind )  → !v String
//   ( wal_sync w )                     → !v String        durability point
//   ( wal_bytes w )                    → i
//   ( wal_reopen w path )              → !v String        close, open again
//   ( wal_close w )                    → v                early release (optional)
//   ( wal_replay path m )              → !WalStat String  → memtable
//   ( wal_reset path )                 → !v String        truncate to empty
//
// A Wal is a handle: every copy is the same log, and the last owner
// closes its file.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/path.nu`
$ `stdlib/std/deflate.nu`
$ `memtable.nu`
$ `stdlib/core/rcbox.nu`

: WalImpl {
    File f
    ( Vec u ) buf
    i bytes
    Crc32 crc
}

// The log file is the one part the compiler does not manage: the last
// owner closes it (the buffer and the CRC table go with the drop glue).
% Drop WalImpl { @ drop WalImpl w → v { ( file_close . w f ) } }

: Wal { s ctl }

@ Wal_share Wal h → Wal { ^ @ Wal { # s ( rcbox_share # i . h ctl ) } }

@ Wal_drop sink Wal h → v {
    ( mem_forget h )
    ( rcbox_release [WalImpl] # i . h ctl )
}

@ __Wal_ptr Wal h → *WalImpl { ^ ( rcbox_ptr [WalImpl] # i . h ctl ) }

: WalStat {
    i records
    i maxseq
    i truncated  // 1 if a torn tail was dropped
    i bytes
}

@ __wal_open_err s path → String {
    : String msg ( string_from `lsmdb: cannot open the write-ahead log ` )
    ( string_push_str msg path )
    ^ msg
}

@ wal_open s path → !Wal String {
    : !File IoErr fr ( file_append path )
    ?? fr {
        T f → {
            : i w__box ( rcbox_zero [WalImpl] )
            : *WalImpl w ( rcbox_ptr [WalImpl] w__box )
            = . w f f
            = . w buf ( vec_with_cap [u] 256 )
            = . w bytes ?? ( file_size path ) { T n → n F _ → 0 }
            = . w crc ( crc32_ctx )
            ^ @ !Wal String { T @ Wal { # s w__box } }
        }
        F _ → { ^ @ !Wal String { F ( __wal_open_err path ) } }
    }
}

@ wal_bytes Wal w__h → i {
    : *WalImpl w ( __Wal_ptr w__h )
    ^ . w bytes
}

// Close the log file and open `path` again for appending — what a flush
// does once it has reset the log. If the reopen fails the log stays
// closed, and every append after it is an error rather than a lost write.
@ wal_reopen Wal w__h s path → !v String {
    : *WalImpl w ( __Wal_ptr w__h )
    ( file_close . w f )
    // The closed file's handle leaves the log (dropped here).
    : File old_f . w f
    ( mem_take old_f )
    = . w f @ File { # s 0 }
    ?? ( file_append path ) {
        T f → {
            = . w f f
            = . w bytes ?? ( file_size path ) { T n → n F _ → 0 }
            ^ @ !v String { T 0 }
        }
        F _ → { ^ @ !v String { F ( __wal_open_err path ) } }
    }
}

// Let go of `w` now rather than at the end of its owner's scope.
@ wal_close sink Wal w → v {}

@ wal_append Wal w__h ( Vec u ) key ( Vec u ) val i seq i kind → !v String {
    : *WalImpl w ( __Wal_ptr w__h )
    : i kl ( vec_len [u] key )
    : i vl ? == kind MT_PUT ( vec_len [u] val ) 0
    ( vec_clear [u] . w buf )
    ( bytes_push_u64_le . w buf # u64 seq )
    ( vec_push [u] . w buf # u kind )
    ( bytes_push_u32_le . w buf # u32 kl )
    ( vec_extend [u] . w buf key )
    ( bytes_push_u32_le . w buf # u32 vl )
    ? > vl 0 { ( vec_extend [u] . w buf val ) } {}

    : i plen ( vec_len [u] . w buf )
    : i crc ( crc32_ctx_hash . w crc . w buf )
    : ( Vec u ) rec ( vec_with_cap [u] + plen 8 )
    ( bytes_push_u32_le rec # u32 crc )
    ( bytes_push_u32_le rec # u32 plen )
    ( vec_extend [u] rec . w buf )
    : !v IoErr wr ( file_write_chunk . w f rec )
    ?? wr {
        T _ → { = . w bytes + . w bytes + plen 8 ^ @ !v String { T 0 } }
        F _ → { ^ @ !v String { F ( string_from `lsmdb: write-ahead log append failed (disk full?)` ) } }
    }
}

// The durability point. Returning from here means the OS has the bytes
// on the device — everything appended so far survives a power cut.
@ wal_sync Wal w__h → !v String {
    : *WalImpl w ( __Wal_ptr w__h )
    ?? ( file_sync . w f ) {
        T _ → { ^ @ !v String { T 0 } }
        F _ → { ^ @ !v String { F ( string_from `lsmdb: cannot fsync the write-ahead log` ) } }
    }
}

// Cut the log back to `len` bytes — the end of the last intact record.
//
// Recovery MUST do this before appending again. A torn tail left in
// place is not merely untidy: replay stops there, so every write made
// after the crash would land behind bytes that the next replay refuses
// to walk past, and would be silently invisible from then on.
@ wal_truncate s path i len → !v String {
    ?? ( file_truncate path len ) {
        T _ → {
            : String parent ( path_dirname path )
            ?? ( dir_sync ( string_data parent ) ) { T _ → {} F _ → {} }
            ^ @ !v String { T 0 }
        }
        F _ → { ^ @ !v String { F ( string_from `lsmdb: cannot truncate the torn tail of the write-ahead log` ) } }
    }
}

@ wal_reset s path → !v String {
    ?? ( file_create path ) {
        T f → {
            ?? ( file_sync f ) { T _ → {} F _ → {} }
            ( file_close f )
            ^ @ !v String { T 0 }
        }
        F _ → { ^ @ !v String { F ( string_from `lsmdb: cannot truncate the write-ahead log` ) } }
    }
}

// Replay every intact record into `m`. A missing log is an empty one —
// a database that has never been written to is not an error.
@ wal_replay s path MemTable m → !WalStat String {
    ? ( file_exists path ) {} {
        ^ @ !WalStat String { T @ WalStat { 0 0 0 0 } }
    }
    : !( Vec u ) IoErr rr ( read_file_bytes path )
    : ~ ( Vec u ) data ( vec_new [u] )
    ?? rr { T v → { = data v } F _ → {
            ^ @ !WalStat String { F ( string_from `lsmdb: cannot read the write-ahead log` ) } } }

    : i n ( vec_len [u] data )
    : ~ i pos 0
    : ~ i records 0
    : ~ i maxseq 0
    : ~ i truncated 0
    : ~ b going T
    ~ & going < pos n {
        ? > + pos 8 n { = truncated 1 = going F } {
            : i crc ?? ( bytes_read_u32_le data pos ) { T x → # i x F _ → 0 }
            : i plen ?? ( bytes_read_u32_le data + pos 4 ) { T x → # i x F _ → 0 }
            ? | < plen 13 > + pos + 8 plen n { = truncated 1 = going F } {
                : ( Vec u ) payload ( _mt_slice data + pos 8 plen )
                ? != ( crc32 payload ) crc {
                    // A half-written record at the tail: the write was
                    // never acknowledged, so dropping it is exactly right.
                    = truncated 1 = going F
                } {
                    : i seq ?? ( bytes_read_u64_le payload 0 ) { T x → # i x F _ → 0 }
                    : i kind ?? ( vec_get [u] payload 8 ) { T x → # i x F _ → 0 }
                    : i kl ?? ( bytes_read_u32_le payload 9 ) { T x → # i x F _ → 0 }
                    ? > + 13 kl plen { = truncated 1 = going F } {
                        : i vl ?? ( bytes_read_u32_le payload + 13 kl ) { T x → # i x F _ → 0 }
                        ? > + + 17 kl vl plen { = truncated 1 = going F } {
                            : ( Vec u ) key ( _mt_slice payload 13 kl )
                            : ( Vec u ) val ( _mt_slice payload + 17 kl vl )
                            ( mt_put m key val seq kind )
                            = records + records 1
                            ? > seq maxseq { = maxseq seq } {}
                            = pos + pos + 8 plen
                        }
                    }
                }
            }
        }
    }
    ^ @ !WalStat String { T @ WalStat { records maxseq truncated pos } }
}
