// stdlib/std/x509.nu — a focused pure-NURL X.509 / DER parser.
//
// Not a general ASN.1 library: it walks a DER-encoded certificate and
// pulls out exactly what certificate-chain verification needs — the raw
// TBSCertificate bytes (what the issuer signed), the signature algorithm
// and value, the subject public key (RSA modulus/exponent or EC point),
// validity window, subject/issuer names, the SAN dNSNames, and the CA
// flag. No OpenSSL.
//
//   ( x509_parse der ) → X509      (.ok = F on malformed input)
//
// Signature/key algorithm codes (sig_alg / key_alg):
//   sig_alg: 1 rsa_pkcs1_sha256  2 _sha384  3 _sha512
//            4 ecdsa_sha256      5 ecdsa_sha384
//            6 rsa_pss           7 ed25519     0 unknown
//   key_alg: 1 RSA  2 EC  3 Ed25519  0 unknown

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`

@ __x509_bget ( Vec u ) v i k → i {
    ?? ( vec_get [u] v k ) { T x → ^ # i x F _ → ^ -1 }
}

// A DER element: tag, header length, content length, content start. The
// element spans [pos, start+len).
: DerTlv { i tag i hdr i len i start i ok }

@ der_at ( Vec u ) b i pos → DerTlv {
    : i n ( vec_len [u] b )
    ? > + pos 2 n { ^ @ DerTlv { 0 0 0 0 0 } } {}
    : i tag ( __x509_bget b pos )
    : i l0 ( __x509_bget b + pos 1 )
    ? < l0 128 {
        : i start + pos 2
        ? > + start l0 n { ^ @ DerTlv { 0 0 0 0 0 } } {}
        ^ @ DerTlv { tag 2 l0 start 1 }
    } {}
    : i nb & l0 127
    ? | == nb 0 > nb 4 { ^ @ DerTlv { 0 0 0 0 0 } } {}
    : ~ i len 0
    : ~ i k 0
    ~ < k nb { = len | << len 8 ( __x509_bget b + + pos 2 k ) = k + k 1 }
    : i hdr + 2 nb
    : i start + pos hdr
    ? > + start len n { ^ @ DerTlv { 0 0 0 0 0 } } {}
    ^ @ DerTlv { tag hdr len start 1 }
}

// First child of a constructed element.
@ __der_child ( Vec u ) b DerTlv t → DerTlv { ^ ( der_at b . t start ) }

// Next sibling after element `t`.
@ __der_next ( Vec u ) b DerTlv t → DerTlv { ^ ( der_at b + . t start . t len ) }

// Raw bytes of the whole element (tag..end).
@ __der_elem_bytes ( Vec u ) b DerTlv t → ( Vec u ) {
    ^ ( bytes_slice b - . t start . t hdr + . t start . t len )
}

// Content bytes of the element.
@ __der_content ( Vec u ) b DerTlv t → ( Vec u ) {
    ^ ( bytes_slice b . t start + . t start . t len )
}

// INTEGER content as an unsigned magnitude: drop DER's leading sign
// byte(s) so the byte length equals the true modulus/exponent size.
@ __der_uint ( Vec u ) b DerTlv t → ( Vec u ) {
    : ~ i s . t start
    : i end + . t start . t len
    ~ & < s - end 1 == ( __x509_bget b s ) 0 { = s + s 1 }
    ^ ( bytes_slice b s end )
}

// Compare an OID element's content bytes to a hex literal.
@ __der_oid_is ( Vec u ) b DerTlv t s hexoid → b {
    : ( Vec u ) want ?? ( bytes_from_hex hexoid ) { T v → v F _ → ( vec_new [u] ) }
    : i wl ( vec_len [u] want )
    ? != . t len wl { ( vec_free [u] want ) ^ F } {}
    : ~ b eq T
    : ~ i i 0
    ~ < i wl { ? != ( __x509_bget b + . t start i ) ( __x509_bget want i ) { = eq F } {} = i + i 1 }
    ( vec_free [u] want )
    ^ eq
}

: X509 {
    ( Vec u ) tbs
    i sig_alg
    ( Vec u ) sig
    i key_alg
    ( Vec u ) rsa_n
    ( Vec u ) rsa_e
    ( Vec u ) ec_point
    i ec_curve
    ( Vec u ) subject
    ( Vec u ) issuer
    ( Vec String ) sans
    i not_before
    i not_after
    b is_ca
    b ok
}

@ __x509_empty → X509 {
    ^ @ X509 {
        ( vec_new [u] ) 0 ( vec_new [u] ) 0 ( vec_new [u] ) ( vec_new [u] )
        ( vec_new [u] ) 0 ( vec_new [u] ) ( vec_new [u] ) ( vec_new [String] ) 0 0 F F
    }
}

// Map an AlgorithmIdentifier SEQ (at `alg`) to a sig_alg code.
@ __x509_sigalg ( Vec u ) b DerTlv alg → i {
    : DerTlv oid ( __der_child b alg )
    ? ( __der_oid_is b oid `2a864886f70d01010b` ) { ^ 1 } {}
    ? ( __der_oid_is b oid `2a864886f70d01010c` ) { ^ 2 } {}
    ? ( __der_oid_is b oid `2a864886f70d01010d` ) { ^ 3 } {}
    ? ( __der_oid_is b oid `2a8648ce3d040302` ) { ^ 4 } {}
    ? ( __der_oid_is b oid `2a8648ce3d040303` ) { ^ 5 } {}
    ? ( __der_oid_is b oid `2a864886f70d01010a` ) { ^ 6 } {}
    ? ( __der_oid_is b oid `2b6570` ) { ^ 7 } {}
    ^ 0
}

// Parse YYMMDD…/YYYYMMDD… time content → YYYYMMDDHHMMSS as an integer.
@ __x509_time ( Vec u ) b DerTlv t → i {
    : i tag . t tag
    : ~ i p . t start
    : ~ i year 0
    ? == tag 23 {
        // UTCTime YY -> 2000+YY (or 1900+YY if YY>=50)
        : i yy + * 10 - ( __x509_bget b p ) 48 - ( __x509_bget b + p 1 ) 48
        = year ? >= yy 50 + 1900 yy + 2000 yy
        = p + p 2
    } {
        // GeneralizedTime YYYY
        : ~ i y 0
        : ~ i k 0
        ~ < k 4 { = y + * y 10 - ( __x509_bget b + p k ) 48 = k + k 1 }
        = year y
        = p + p 4
    }
    : ~ i acc year
    : ~ i f 0
    ~ < f 5 {
        : i d + * 10 - ( __x509_bget b p ) 48 - ( __x509_bget b + p 1 ) 48
        = acc + * acc 100 d
        = p + p 2
        = f + f 1
    }
    ^ acc
}

// Pull dNSName entries (context tag 0x82) out of a SAN extnValue.
@ __x509_sans ( Vec u ) b DerTlv san_seq ( Vec String ) out → v {
    : ~ DerTlv e ( __der_child b san_seq )
    ~ == . e ok 1 {
        ? == . e tag 130 {  // [2] dNSName, IA5String
            : ( Vec u ) nm ( __der_content b e )
            ( vec_push [String] out ( bytes_to_str nm ) )
            ( vec_free [u] nm )
        } {}
        = e ( __der_next b e )
    }
}

// Walk extensions to capture SANs and the CA flag.
@ __x509_extensions ( Vec u ) b DerTlv exts X509 out → v {
    // exts is [3] EXPLICIT; its child is the SEQUENCE OF Extension.
    : DerTlv seq ( __der_child b exts )
    : ~ DerTlv ext ( __der_child b seq )
    ~ == . ext ok 1 {
        : DerTlv oid ( __der_child b ext )
        : b is_san ( __der_oid_is b oid `551d11` )
        : b is_bc ( __der_oid_is b oid `551d13` )
        ? | is_san is_bc {
            // value is the last child (OCTET STRING), after optional critical BOOLEAN
            : ~ DerTlv nxt ( __der_next b oid )
            ? == . nxt tag 1 { = nxt ( __der_next b nxt ) } {}  // skip critical
            // nxt = OCTET STRING extnValue; its content is inner DER
            : DerTlv inner ( der_at b . nxt start )
            ? is_san { ( __x509_sans b inner . out sans ) } {}
            ? is_bc {
                : DerTlv c0 ( __der_child b inner )
                ? & == . c0 ok 1 == . c0 tag 1 {
                    ? != ( __x509_bget b . c0 start ) 0 { = . out is_ca T } {}
                } {}
            } {}
        } {}
        = ext ( __der_next b ext )
    }
}

@ x509_parse ( Vec u ) der → X509 {
    : X509 out ( __x509_empty )
    : DerTlv cert ( der_at der 0 )
    ? != . cert ok 1 { ^ out } {}
    ? != . cert tag 48 { ^ out } {}

    : DerTlv tbs ( __der_child der cert )
    ? != . tbs ok 1 { ^ out } {}
    ( vec_free [u] . out tbs )
    = . out tbs ( __der_elem_bytes der tbs )

    // signatureAlgorithm + signatureValue (siblings of tbs)
    : DerTlv sigalg ( __der_next der tbs )
    = . out sig_alg ( __x509_sigalg der sigalg )
    : DerTlv sigbits ( __der_next der sigalg )
    ? == . sigbits tag 3 {
        // BIT STRING: skip the leading "unused bits" byte
        ( vec_free [u] . out sig )
        = . out sig ( bytes_slice der + . sigbits start 1 + . sigbits start . sigbits len )
    } {}

    // Walk TBS children.
    : ~ DerTlv c ( __der_child der tbs )
    ? & == . c ok 1 == . c tag 160 { = c ( __der_next der c ) } {}  // skip [0] version
    = c ( __der_next der c )  // skip serialNumber
    = c ( __der_next der c )  // skip signature alg
    ( vec_free [u] . out issuer )
    = . out issuer ( __der_elem_bytes der c )
    = c ( __der_next der c )  // validity
    : DerTlv nb ( __der_child der c )
    : DerTlv na ( __der_next der nb )
    = . out not_before ( __x509_time der nb )
    = . out not_after ( __x509_time der na )
    = c ( __der_next der c )
    ( vec_free [u] . out subject )
    = . out subject ( __der_elem_bytes der c )
    = c ( __der_next der c )  // subjectPublicKeyInfo

    : DerTlv keyalg ( __der_child der c )
    : DerTlv keyoid ( __der_child der keyalg )
    : DerTlv keybits ( __der_next der keyalg )
    ? ( __der_oid_is der keyoid `2a864886f70d010101` ) {
        // RSA: BIT STRING content (after unused-bits byte) is SEQ{n,e}
        = . out key_alg 1
        : DerTlv rsaseq ( der_at der + . keybits start 1 )
        : DerTlv ni ( __der_child der rsaseq )
        : DerTlv ei ( __der_next der ni )
        ( vec_free [u] . out rsa_n )
        = . out rsa_n ( __der_uint der ni )
        ( vec_free [u] . out rsa_e )
        = . out rsa_e ( __der_uint der ei )
    } {
        ? ( __der_oid_is der keyoid `2a8648ce3d0201` ) {
            // EC: namedCurve param + uncompressed point in the BIT STRING
            = . out key_alg 2
            : DerTlv curve ( __der_next der keyoid )
            : ~ i cc 0
            ? ( __der_oid_is der curve `2a8648ce3d030107` ) { = cc 256 } {}
            ? ( __der_oid_is der curve `2b81040022` ) { = cc 384 } {}
            = . out ec_curve cc
            ( vec_free [u] . out ec_point )
            = . out ec_point ( bytes_slice der + . keybits start 1 + . keybits start . keybits len )
        } {
            ? ( __der_oid_is der keyoid `2b6570` ) {
                = . out key_alg 3
                ( vec_free [u] . out ec_point )
                = . out ec_point ( bytes_slice der + . keybits start 1 + . keybits start . keybits len )
            } {}
        }
    }

    // optional extensions [3]
    = c ( __der_next der c )
    ? & == . c ok 1 == . c tag 163 { ( __x509_extensions der c out ) } {}

    = . out ok T
    ^ out
}

// Case-insensitive hostname match against the certificate SANs, honoring
// a single leading "*." wildcard label (RFC 6125).
@ x509_matches_host X509 cert s host → b {
    : ( Vec String ) sans . cert sans
    : i n ( vec_len [String] sans )
    : ~ i i 0
    : ~ b ok F
    ~ & ! ok < i n {
        ?? ( vec_get [String] sans i ) {
            T sv → { ? ( __host_match ( string_data sv ) host ) { = ok T } {} }
            F _ → {}
        }
        = i + i 1
    }
    ^ ok
}

// Match `pattern` (a SAN dNSName, possibly "*.example.com") against host,
// ASCII-case-insensitively. The wildcard matches exactly one left label.
@ __host_match s pattern s host → b {
    : i pl ( nurl_str_len pattern )
    : i hl ( nurl_str_len host )
    ? & > pl 1 == ( nurl_str_get pattern 0 ) 42 {
        // "*.rest" — host must end with ".rest" and have no dot in the
        // matched first label.
        : s rest ( nurl_str_slice pattern 1 - pl 1 )  // ".example.com"
        : i rl - pl 1
        ? <= hl rl { ^ F } {}
        : i off - hl rl
        // the matched prefix host[0..off) must contain no dot
        : ~ i k 0
        ~ < k off { ? == ( nurl_str_get host k ) 46 { ^ F } {} = k + k 1 }
        : s tail ( nurl_str_slice host off rl )
        ^ ( __ci_eq tail rest )
    } {}
    ^ ( __ci_eq pattern host )
}

@ __ci_eq s a s b → b {
    : i la ( nurl_str_len a )
    ? != la ( nurl_str_len b ) { ^ F } {}
    : ~ i i 0
    ~ < i la {
        ? != ( __lower ( nurl_str_get a i ) ) ( __lower ( nurl_str_get b i ) ) { ^ F } {}
        = i + i 1
    }
    ^ T
}

@ __lower i c → i { ^ ? & >= c 65 <= c 90 + c 32 c }

@ x509_free X509 c → v {
    ( vec_free [u] . c tbs )
    ( vec_free [u] . c sig )
    ( vec_free [u] . c rsa_n )
    ( vec_free [u] . c rsa_e )
    ( vec_free [u] . c ec_point )
    ( vec_free [u] . c subject )
    ( vec_free [u] . c issuer )
    ( vec_free_with [String] . c sans \ String s → v { ( string_free s ) } )
}
