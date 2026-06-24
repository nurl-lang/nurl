// aes_gcm_vectors.nu — AES-128-GCM against the McGrew/NIST GCM test
// vectors (Test Case 3: no AAD; Test Case 4: with AAD), plus roundtrip
// and tamper-rejection.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/aes_gcm.nu`

@ hx s raw → ( Vec u ) { ?? ( bytes_from_hex raw ) { T v → ^ v F _ → ^ ( vec_new [u] ) } }

@ check s label ( Vec u ) got s want → i {
    : String gh ( bytes_to_hex got )
    ? ( nurl_str_eq ( string_data gh ) want ) { ( nurl_print label ) ( nurl_print `: PASS\n` ) ( string_free gh ) ^ 0 }
    { ( nurl_print label ) ( nurl_print `: FAIL got ` ) ( nurl_print ( string_data gh ) ) ( nurl_print `\n` ) ( string_free gh ) ^ 1 }
}

@ main → i {
    : ~ i fails 0
    : ( Vec u ) key ( hx `feffe9928665731c6d6a8f9467308308` )
    : ( Vec u ) iv ( hx `cafebabefacedbaddecaf888` )
    : ( Vec u ) empty ( vec_new [u] )

    // Test Case 3 — no AAD, full 64-byte plaintext.
    : ( Vec u ) p3 ( hx `d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b391aafd255` )
    : ( Vec u ) s3 ( aes128_gcm_encrypt key iv empty p3 )
    = fails + fails ( check `tc3` s3 `42831ec2217774244b7221b784d0d49ce3aa212f2c02a4e035c17e2329aca12e21d514b25466931c7d8f6a5aac84aa051ba30b396a0aac973d58e091473f59854d5c2af327cd64a62cf35abd2ba6fab4` )

    // Test Case 4 — with AAD, 60-byte plaintext.
    : ( Vec u ) p4 ( hx `d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39` )
    : ( Vec u ) aad ( hx `feedfacedeadbeeffeedfacedeadbeefabaddad2` )
    : ( Vec u ) s4 ( aes128_gcm_encrypt key iv aad p4 )
    = fails + fails ( check `tc4` s4 `42831ec2217774244b7221b784d0d49ce3aa212f2c02a4e035c17e2329aca12e21d514b25466931c7d8f6a5aac84aa051ba30b396a0aac973d58e0915bc94fbc3221a5db94fae95ae7121a47` )

    // Roundtrip + tamper.
    ?? ( aes128_gcm_decrypt key iv aad s4 ) {
        T pt → { = fails + fails ( check `tc4_open` pt `d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39` ) ( vec_free [u] pt ) }
        F _ → { ( nurl_print `tc4_open: FAIL rejected\n` ) = fails + fails 1 }
    }
    ( vec_set [u] s4 0 # u ^^ 255 ?? ( vec_get [u] s4 0 ) { T x → # i x F _ → 0 } )
    ?? ( aes128_gcm_decrypt key iv aad s4 ) {
        T bad → { ( nurl_print `tamper: FAIL accepted\n` ) = fails + fails 1 ( vec_free [u] bad ) }
        F _ → ( nurl_print `tamper: PASS\n` )
    }

    ? == fails 0 { ( nurl_print `aes-gcm: all vectors PASS\n` ) } { ( nurl_print `aes-gcm: FAILURES\n` ) }
    ^ fails
}
