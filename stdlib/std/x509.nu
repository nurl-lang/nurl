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
//   key_alg: 1 RSA  2 EC  3 Ed25519  4 ML-DSA  0 unknown
//
// Ed25519 and ML-DSA both keep their raw public key in `ec_point` — the
// field is "the key bytes that are not an RSA modulus", not specifically
// an EC point. For ML-DSA, `ec_curve` carries the parameter set (44, 65
// or 87), which the key length also determines but which is cheaper to
// read back than to re-derive.

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
@ _der_child ( Vec u ) b DerTlv t → DerTlv { ^ ( der_at b . t start ) }

// Next sibling after element `t`.
@ _der_next ( Vec u ) b DerTlv t → DerTlv { ^ ( der_at b + . t start . t len ) }

// Raw bytes of the whole element (tag..end).
@ __der_elem_bytes ( Vec u ) b DerTlv t → ( Vec u ) {
    ^ ( bytes_slice b - . t start . t hdr + . t start . t len )
}

// Content bytes of the element.
@ _der_content ( Vec u ) b DerTlv t → ( Vec u ) {
    ^ ( bytes_slice b . t start + . t start . t len )
}

// INTEGER content as an unsigned magnitude: drop DER's leading sign
// byte(s) so the byte length equals the true modulus/exponent size.
@ _der_uint ( Vec u ) b DerTlv t → ( Vec u ) {
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
    // BasicConstraints pathLenConstraint: -1 = absent (unbounded), else the
    // max number of intermediate certs that may follow this CA toward the leaf.
    i path_len
    // keyUsage: has_ku = extension present; ku_cert_sign = keyCertSign bit set.
    b has_ku
    b ku_cert_sign
    // extendedKeyUsage: has_eku = present; eku_server = serverAuth or anyEKU.
    b has_eku
    b eku_server
    // iPAddress SANs (context tag [7]), each stored as a lowercase-hex string
    // of the raw 4- or 16-byte address.
    ( Vec String ) ip_sans
    b ok
}

@ __x509_empty → X509 {
    ^ @ X509 {
        ( vec_new [u] ) 0 ( vec_new [u] ) 0 ( vec_new [u] ) ( vec_new [u] )
        ( vec_new [u] ) 0 ( vec_new [u] ) ( vec_new [u] ) ( vec_new [String] ) 0 0 F
        -1 F F F F ( vec_new [String] ) F
    }
}

// Map an AlgorithmIdentifier SEQ (at `alg`) to a sig_alg code.
@ __x509_sigalg ( Vec u ) b DerTlv alg → i {
    : DerTlv oid ( _der_child b alg )
    ? ( __der_oid_is b oid `2a864886f70d01010b` ) { ^ 1 } {}
    ? ( __der_oid_is b oid `2a864886f70d01010c` ) { ^ 2 } {}
    ? ( __der_oid_is b oid `2a864886f70d01010d` ) { ^ 3 } {}
    ? ( __der_oid_is b oid `2a8648ce3d040302` ) { ^ 4 } {}
    ? ( __der_oid_is b oid `2a8648ce3d040303` ) { ^ 5 } {}
    ? ( __der_oid_is b oid `2a864886f70d01010a` ) { ^ 6 } {}
    ? ( __der_oid_is b oid `2b6570` ) { ^ 7 } {}
    // ML-DSA (FIPS 204): 2.16.840.1.101.3.4.3.{17,18,19}. The same OID
    // names the key type and the signature algorithm — there is no
    // separate hash to name, because ML-DSA hashes internally.
    ? ( __der_oid_is b oid `608648016503040311` ) { ^ 8 } {}
    ? ( __der_oid_is b oid `608648016503040312` ) { ^ 9 } {}
    ? ( __der_oid_is b oid `608648016503040313` ) { ^ 10 } {}
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

// True if the SAN content bytes contain an embedded NUL (0x00). A dNSName
// like "victim.com\0.attacker.com" would otherwise be truncated to
// "victim.com" by every strlen-based comparison — the classic embedded-NUL
// SAN spoof. Such names are rejected outright (never added to the match set).
@ __x509_has_nul ( Vec u ) b DerTlv e → b {
    : i end + . e start . e len
    : ~ i k . e start
    ~ < k end { ? == ( __x509_bget b k ) 0 { ^ T } {} = k + k 1 }
    ^ F
}

// Lowercase-hex of a SAN element's raw content (used for iPAddress).
@ __x509_hex_content ( Vec u ) b DerTlv e → String {
    : String s ( string_new )
    : i end + . e start . e len
    : ~ i k . e start
    ~ < k end {
        : i byte ( __x509_bget b k )
        ( string_push_char s ( __rand_nibble >> byte 4 ) )
        ( string_push_char s ( __rand_nibble & byte 15 ) )
        = k + k 1
    }
    ^ s
}

@ __rand_nibble i n → i { ^ ? < n 10 + 48 n + 87 n }

// Pull dNSName ([2], 0x82) and iPAddress ([7], 0x87) entries out of a SAN
// extnValue. dNSNames with an embedded NUL are dropped (spoof guard).
@ __x509_sans ( Vec u ) b DerTlv san_seq X509 out → v {
    : ~ DerTlv e ( _der_child b san_seq )
    ~ == . e ok 1 {
        ? == . e tag 130 {  // [2] dNSName, IA5String
            ? ! ( __x509_has_nul b e ) {
                : ( Vec u ) nm ( _der_content b e )
                ( vec_push [String] . out sans ( bytes_to_str nm ) )
                ( vec_free [u] nm )
            } {}
        } {}
        ? == . e tag 135 {  // [7] iPAddress, OCTET STRING (4 or 16 bytes)
            ? | == . e len 4 == . e len 16 {
                ( vec_push [String] . out ip_sans ( __x509_hex_content b e ) )
            } {}
        } {}
        = e ( _der_next b e )
    }
}

// Scalar results of the extension walk. The SAN / iPAddress lists are
// pushed directly into the X509's vec handles (those are shared by
// reference even though the struct itself is passed by value); the scalar
// flags below CANNOT be set that way — a by-value `= . out is_ca T` would
// mutate a copy and be lost — so they are returned here and merged by the
// caller, which holds the authoritative `out`.
: ExtInfo { b is_ca i path_len b has_ku b ku_cert_sign b has_eku b eku_server }

// Walk extensions to capture SANs (into `out`'s vec handles) and the CA
// flag + pathLen + keyUsage + EKU (returned in ExtInfo).
@ __x509_extensions ( Vec u ) b DerTlv exts X509 out → ExtInfo {
    : ~ ExtInfo ei @ ExtInfo { F -1 F F F F }
    // exts is [3] EXPLICIT; its child is the SEQUENCE OF Extension.
    : DerTlv seq ( _der_child b exts )
    : ~ DerTlv ext ( _der_child b seq )
    ~ == . ext ok 1 {
        : DerTlv oid ( _der_child b ext )
        : b is_san ( __der_oid_is b oid `551d11` )
        : b is_bc ( __der_oid_is b oid `551d13` )
        : b is_ku ( __der_oid_is b oid `551d0f` )
        : b is_eku ( __der_oid_is b oid `551d25` )
        ? | | | is_san is_bc is_ku is_eku {
            // value is the last child (OCTET STRING), after optional critical BOOLEAN
            : ~ DerTlv nxt ( _der_next b oid )
            ? == . nxt tag 1 { = nxt ( _der_next b nxt ) } {}  // skip critical
            // nxt = OCTET STRING extnValue; its content is inner DER
            : DerTlv inner ( der_at b . nxt start )
            ? is_san { ( __x509_sans b inner out ) } {}
            ? is_bc {
                // BasicConstraints ::= SEQ { cA BOOLEAN DEFAULT FALSE,
                //                            pathLenConstraint INTEGER OPTIONAL }
                : DerTlv c0 ( _der_child b inner )
                ? & == . c0 ok 1 == . c0 tag 1 {
                    ? != ( __x509_bget b . c0 start ) 0 { = . ei is_ca T } {}
                    // pathLenConstraint, if present, is the next INTEGER sibling.
                    : DerTlv pl ( _der_next b c0 )
                    ? & == . pl ok 1 == . pl tag 2 {
                        = . ei path_len ( __x509_int_val b pl )
                    } {}
                } {}
            } {}
            ? is_ku {
                // keyUsage extnValue IS a BIT STRING (inner, not a wrapper):
                // content = [unused-bits-count][data…]. keyCertSign is bit 5,
                // i.e. mask 0x04 of the first data byte.
                = . ei has_ku T
                ? & == . inner ok 1 == . inner tag 3 {
                    : i b0 ( __x509_bget b + . inner start 1 )
                    ? != 0 & b0 4 { = . ei ku_cert_sign T } {}
                } {}
            } {}
            ? is_eku {
                // extendedKeyUsage ::= SEQUENCE OF KeyPurposeId (OID).
                = . ei has_eku T
                : ~ DerTlv ku ( _der_child b inner )
                ~ == . ku ok 1 {
                    ? == . ku tag 6 {
                        ? ( __der_oid_is b ku `2b06010505070301` ) { = . ei eku_server T } {}  // serverAuth
                        ? ( __der_oid_is b ku `551d2500` ) { = . ei eku_server T } {}  // anyExtendedKeyUsage
                    } {}
                    = ku ( _der_next b ku )
                }
            } {}
        } {}
        = ext ( _der_next b ext )
    }
    ^ ei
}

// Value of a small (≤ i63) INTEGER element as a non-negative int.
@ __x509_int_val ( Vec u ) b DerTlv t → i {
    : ~ i v 0
    : i end + . t start . t len
    : ~ i k . t start
    ~ < k end { = v | << v 8 & 255 ( __x509_bget b k ) = k + k 1 }
    ^ v
}

@ x509_parse ( Vec u ) der → X509 {
    : X509 out ( __x509_empty )
    : DerTlv cert ( der_at der 0 )
    ? != . cert ok 1 { ^ out } {}
    ? != . cert tag 48 { ^ out } {}

    : DerTlv tbs ( _der_child der cert )
    ? != . tbs ok 1 { ^ out } {}
    ( vec_free [u] . out tbs )
    = . out tbs ( __der_elem_bytes der tbs )

    // signatureAlgorithm + signatureValue (siblings of tbs)
    : DerTlv sigalg ( _der_next der tbs )
    = . out sig_alg ( __x509_sigalg der sigalg )
    : DerTlv sigbits ( _der_next der sigalg )
    ? == . sigbits tag 3 {
        // BIT STRING: skip the leading "unused bits" byte
        ( vec_free [u] . out sig )
        = . out sig ( bytes_slice der + . sigbits start 1 + . sigbits start . sigbits len )
    } {}

    // Walk TBS children.
    : ~ DerTlv c ( _der_child der tbs )
    ? & == . c ok 1 == . c tag 160 { = c ( _der_next der c ) } {}  // skip [0] version
    = c ( _der_next der c )  // skip serialNumber
    = c ( _der_next der c )  // skip signature alg
    ? != . c ok 1 { ^ out } {}
    ( vec_free [u] . out issuer )
    = . out issuer ( __der_elem_bytes der c )
    = c ( _der_next der c )  // validity
    ? != . c ok 1 { ^ out } {}
    : DerTlv nb ( _der_child der c )
    : DerTlv na ( _der_next der nb )
    ? | != . nb ok 1 != . na ok 1 { ^ out } {}
    = . out not_before ( __x509_time der nb )
    = . out not_after ( __x509_time der na )
    = c ( _der_next der c )
    ? != . c ok 1 { ^ out } {}
    ( vec_free [u] . out subject )
    = . out subject ( __der_elem_bytes der c )
    = c ( _der_next der c )  // subjectPublicKeyInfo
    ? != . c ok 1 { ^ out } {}

    : DerTlv keyalg ( _der_child der c )
    : DerTlv keyoid ( _der_child der keyalg )
    : DerTlv keybits ( _der_next der keyalg )
    ? ( __der_oid_is der keyoid `2a864886f70d010101` ) {
        // RSA: BIT STRING content (after unused-bits byte) is SEQ{n,e}
        = . out key_alg 1
        : DerTlv rsaseq ( der_at der + . keybits start 1 )
        : DerTlv ni ( _der_child der rsaseq )
        : DerTlv ei ( _der_next der ni )
        ( vec_free [u] . out rsa_n )
        = . out rsa_n ( _der_uint der ni )
        ( vec_free [u] . out rsa_e )
        = . out rsa_e ( _der_uint der ei )
    } {
        ? ( __der_oid_is der keyoid `2a8648ce3d0201` ) {
            // EC: namedCurve param + uncompressed point in the BIT STRING
            = . out key_alg 2
            : DerTlv curve ( _der_next der keyoid )
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
            } {
                // ML-DSA: the BIT STRING holds the encoded public key
                // whole, with no AlgorithmIdentifier parameters — the
                // OID alone fixes the parameter set.
                : ~ i ml 0
                ? ( __der_oid_is der keyoid `608648016503040311` ) { = ml 44 } {}
                ? ( __der_oid_is der keyoid `608648016503040312` ) { = ml 65 } {}
                ? ( __der_oid_is der keyoid `608648016503040313` ) { = ml 87 } {}
                ? > ml 0 {
                    = . out key_alg 4
                    = . out ec_curve ml
                    ( vec_free [u] . out ec_point )
                    = . out ec_point ( bytes_slice der + . keybits start 1 + . keybits start . keybits len )
                } {}
            }
        }
    }

    // optional extensions [3]
    = c ( _der_next der c )
    ? & == . c ok 1 == . c tag 163 {
        : ExtInfo ei ( __x509_extensions der c out )
        = . out is_ca . ei is_ca
        = . out path_len . ei path_len
        = . out has_ku . ei has_ku
        = . out ku_cert_sign . ei ku_cert_sign
        = . out has_eku . ei has_eku
        = . out eku_server . ei eku_server
    } {}

    = . out ok T
    ^ out
}

// Case-insensitive hostname match against the certificate SANs, honoring
// a single leading "*." wildcard label (RFC 6125). An IP-literal host is
// matched ONLY against iPAddress SANs (never against dNSNames — so a
// dNSName "192.0.2.1" cannot spoof a connection made to that IP); a
// DNS-name host is matched only against dNSName SANs.
@ x509_matches_host X509 cert s host → b {
    // IP-literal host → compare against iPAddress SANs only.
    : String iphex ( __ipv4_hex host )
    ? > ( string_len iphex ) 0 {
        : ( Vec String ) ips . cert ip_sans
        : i ni ( vec_len [String] ips )
        : ~ i j 0
        : ~ b ipok F
        ~ & ! ipok < j ni {
            ?? ( vec_get [String] ips j ) {
                T sv → { ? ( __ci_eq ( string_data sv ) ( string_data iphex ) ) { = ipok T } {} }
                F _ → {}
            }
            = j + j 1
        }
        ( string_free iphex )
        ^ ipok
    } {}
    ( string_free iphex )
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

// If `host` is a dotted-quad IPv4 literal, return its 8-char lowercase-hex
// (e.g. "192.0.2.1" → "c0000201"); otherwise return "". Pure ASCII, no libc.
@ __ipv4_hex s host → String {
    : i hl ( nurl_str_len host )
    : ~ i octets 0
    : ~ i cur 0
    : ~ i digits 0
    : ~ b okfmt T
    : String out ( string_new )
    : ~ i k 0
    ~ & okfmt < k hl {
        : i ch ( nurl_str_get host k )
        ? & >= ch 48 <= ch 57 {
            = cur + * cur 10 - ch 48
            = digits + digits 1
            ? | > cur 255 > digits 3 { = okfmt F } {}
        } {
            ? == ch 46 {
                ? == digits 0 { = okfmt F } {}
                ( __hex_byte out cur )
                = octets + octets 1
                = cur 0 = digits 0
            } { = okfmt F }
        }
        = k + k 1
    }
    ? | | ! okfmt == digits 0 != octets 3 { ( string_free out ) ^ ( string_new ) } {}
    ( __hex_byte out cur )
    ^ out
}

@ __hex_byte String out i byte → v {
    ( string_push_char out ( __rand_nibble >> & byte 255 4 ) )
    ( string_push_char out ( __rand_nibble & byte 15 ) )
}

// Match `pattern` (a SAN dNSName, possibly "*.example.com") against host,
// ASCII-case-insensitively. The wildcard matches exactly one left label.
@ __host_match s pattern s host → b {
    : i pl ( nurl_str_len pattern )
    : i hl ( nurl_str_len host )
    ? & > pl 1 == ( nurl_str_get pattern 0 ) 42 {
        // Only "*.rest" is a valid wildcard: the '*' must be the entire
        // leftmost label (so partial-label "*foo.com" is rejected) and the
        // remainder must span at least two labels (so "*.com" / a wildcard
        // in the public-suffix position is rejected) — RFC 6125 §6.4.3.
        ? != ( nurl_str_get pattern 1 ) 46 { ^ F } {}  // require "*."
        : ~ i dots 0
        : ~ i di 2
        ~ < di pl { ? == ( nurl_str_get pattern di ) 46 { = dots + dots 1 } {} = di + di 1 }
        ? < dots 1 { ^ F } {}  // need ≥2 labels after "*."
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
    ( vec_free_with [String] . c ip_sans \ String s → v { ( string_free s ) } )
}
