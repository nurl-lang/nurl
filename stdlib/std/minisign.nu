// stdlib/std/minisign.nu — pure-NURL minisign signature verification.
//
// Verifies a minisign detached signature against a public key, with zero
// external dependencies (so nurlpkg can check package signatures on any
// machine nurl runs on, Windows included). Supports both signature modes:
//   ED  (prehashed, minisign's default)  — Ed25519 over BLAKE2b-512(message)
//   Ed  (legacy)                         — Ed25519 over the raw message
//
// Formats (base64 on the second, non-comment line):
//   public key : algo(2) ‖ key_id(8) ‖ ed25519_pubkey(32)   = 42 bytes
//   signature  : algo(2) ‖ key_id(8) ‖ ed25519_sig(64)      = 74 bytes
// This checks the primary signature; the "global signature" over the trusted
// comment (line 4 of a .minisig) is not checked — callers that need a trusted
// comment should verify it separately.
//
// API:
//   ( minisign_verify msg pubfile_text sigfile_text ) → b   parse .pub + .minisig text
//   ( minisign_verify_b64 msg pub_b64 sig_b64 )       → b   raw base64 lines

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/encode.nu`
$ `stdlib/std/ed25519.nu`
$ `stdlib/std/hash_blake2b.nu`

// The second line of a minisign .pub / .minisig text (line index 1: the
// base64 payload under the "untrusted comment:" header), right-trimmed of
// CR / spaces. Returns "" if there is no second line.
@ __ms_line2 s text → String {
    : i n ( nurl_str_len text )
    : ~ i i 0
    // skip line 0
    ~ & < i n != ( nurl_str_get text i ) 10 { = i + i 1 }
    ? >= i n { ^ ( string_new ) } {}
    = i + i 1
    : i start i
    ~ & < i n != ( nurl_str_get text i ) 10 { = i + i 1 }
    : ~ i end i
    : ~ b trimming T
    ~ & trimming > end start {
        : i c ( nurl_str_get text - end 1 )
        ? | | == c 13 == c 32 == c 9 { = end - end 1 } { = trimming F }
    }
    ^ ( __ms_substr text start - end start )
}

@ __ms_substr s src i start i len → String {
    : String out ( string_with_cap ? > len 0 len 1 )
    : ~ i k 0
    ~ < k len {
        ( string_push_char out ( nurl_str_get src + start k ) )
        = k + k 1
    }
    ^ out
}

// Decode a base64 line to bytes, or an empty Vec on error.
@ __ms_b64 s line → ( Vec u ) {
    : !( Vec u ) ParseErr r ( b64_decode_vec line )
    ^ ?? r { T v → v F _ → ( vec_new [u] ) }
}

// Verify against raw base64 pubkey + signature lines.
@ minisign_verify_b64 ( Vec u ) message s pub_b64 s sig_b64 → b {
    : ( Vec u ) pubv ( __ms_b64 pub_b64 )
    : ( Vec u ) sig ( __ms_b64 sig_b64 )
    : ~ b ok F
    // shapes: pubkey 42 bytes (Ed), signature 74 bytes (Ed/ED)
    ? & == ( vec_len [u] pubv ) 42 == ( vec_len [u] sig ) 74 {
        : i pa0 ( __ms_byte pubv 0 )
        : i pa1 ( __ms_byte pubv 1 )
        : i sa0 ( __ms_byte sig 0 )
        : i sa1 ( __ms_byte sig 1 )
        // pubkey algo must be 'Ed' (0x45 0x64); sig algo 'E' + 'D'|'d'
        ? & & == pa0 69 == pa1 100 == sa0 69 {
            // key ids (bytes 2..10) must match
            ? ( __ms_keyid_eq pubv sig ) {
                : ( Vec u ) pk ( bytes_slice pubv 10 42 )
                : ( Vec u ) sg ( bytes_slice sig 10 74 )
                ? == sa1 68 {
                    // 'D' → prehashed: Ed25519 over BLAKE2b-512(message)
                    : ( Vec u ) h ( blake2b512_pure message )
                    = ok ( ed25519_verify_pure pk h sg )
                    ( vec_free [u] h )
                } {
                    ? == sa1 100 {
                        // 'd' → legacy: Ed25519 over the raw message
                        = ok ( ed25519_verify_pure pk message sg )
                    } {}
                }
                ( vec_free [u] pk )
                ( vec_free [u] sg )
            } {}
        } {}
    } {}
    ( vec_free [u] pubv )
    ( vec_free [u] sig )
    ^ ok
}

@ __ms_byte ( Vec u ) v i idx → i {
    ?? ( vec_get [u] v idx ) { T x → { ^ # i x } F → { ^ -1 } }
}

@ __ms_keyid_eq ( Vec u ) pubv ( Vec u ) sig → b {
    : ~ i k 2
    : ~ b eq T
    ~ & eq < k 10 {
        ? != ( __ms_byte pubv k ) ( __ms_byte sig k ) { = eq F } {}
        = k + k 1
    }
    ^ eq
}

// Verify against full .pub and .minisig file contents.
@ minisign_verify ( Vec u ) message s pubfile s sigfile → b {
    : String pl ( __ms_line2 pubfile )
    : String sl ( __ms_line2 sigfile )
    : b r ( minisign_verify_b64 message ( string_data pl ) ( string_data sl ) )
    ( string_free pl )
    ( string_free sl )
    ^ r
}
