// aes_gcm_vectors.nu — AES-128-GCM against the McGrew/NIST GCM test
// vectors (Test Case 3: no AAD; Test Case 4: with AAD), plus roundtrip
// and tamper-rejection.
//
// The cipher core encrypts FOUR blocks at a time (it is bitsliced), so
// the lengths below are chosen to walk every path through that loop:
// nothing at all, a single block, AAD with no plaintext, a plaintext
// that is exactly one four-block group (64 B), one that ends mid-group
// (60 B), and one long enough to run the group loop several times and
// still finish on a partial block (300 B). The long vectors and the
// empty/one-block ones were generated with OpenSSL via python
// `cryptography`, i.e. by an implementation that shares no code with
// this one.

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

    // Degenerate lengths: nothing to encrypt, and AAD with no plaintext.
    // Both leave the four-block loop unentered; only the tag is produced.
    : ( Vec u ) zk ( hx `00000000000000000000000000000000` )
    : ( Vec u ) ziv ( hx `000000000000000000000000` )
    : ( Vec u ) z1 ( hx `00000000000000000000000000000000` )
    : ( Vec u ) e1 ( aes128_gcm_encrypt zk ziv empty empty )
    = fails + fails ( check `tc1_empty` e1 `58e2fccefa7e3061367f1d57a4e7455a` )
    : ( Vec u ) e2 ( aes128_gcm_encrypt zk ziv empty z1 )
    = fails + fails ( check `tc2_oneblock` e2 `0388dace60b6a392f328c2b971b2fe78ab6e47d42cec13bdf53a67b21257bddf` )
    : ( Vec u ) dab ( hx `deadbeef` )
    : ( Vec u ) e3 ( aes128_gcm_encrypt zk ziv dab empty )
    = fails + fails ( check `aad_only` e3 `a583169867a1db810bbec2011a38ecb8` )

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

    // ── AES-256-GCM (McGrew/NIST GCM test vectors) ──
    // Test Case 14 — all-zero key/IV, one zero block, no AAD.
    : ( Vec u ) k256z ( hx `0000000000000000000000000000000000000000000000000000000000000000` )
    : ( Vec u ) ivz ( hx `000000000000000000000000` )
    : ( Vec u ) p14 ( hx `00000000000000000000000000000000` )
    : ( Vec u ) s14 ( aes256_gcm_encrypt k256z ivz empty p14 )
    = fails + fails ( check `tc14` s14 `cea7403d4d606b6e074ec5d3baf39d18d0d1c8a799996bf0265b98b5d48ab919` )

    // Test Case 16 — 256-bit key, 60-byte plaintext, 20-byte AAD.
    : ( Vec u ) k256 ( hx `feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308` )
    : ( Vec u ) p16 ( hx `d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39` )
    : ( Vec u ) s16 ( aes256_gcm_encrypt k256 iv aad p16 )
    = fails + fails ( check `tc16` s16 `522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d1aa8cb08e48590dbb3da7b08b1056828838c5f61e6393ba7a0abcc9f66276fc6ece0f4e1768cddf8853bb2d551b` )

    ?? ( aes256_gcm_decrypt k256 iv aad s16 ) {
        T pt → { = fails + fails ( check `tc16_open` pt `d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39` ) ( vec_free [u] pt ) }
        F _ → { ( nurl_print `tc16_open: FAIL rejected\n` ) = fails + fails 1 }
    }
    ( vec_set [u] s16 0 # u ^^ 255 ?? ( vec_get [u] s16 0 ) { T x → # i x F _ → 0 } )
    ?? ( aes256_gcm_decrypt k256 iv aad s16 ) {
        T bad → { ( nurl_print `tamper256: FAIL accepted\n` ) = fails + fails 1 ( vec_free [u] bad ) }
        F _ → ( nurl_print `tamper256: PASS\n` )
    }

    // ── 300 bytes: four full four-block groups and a 44-byte tail, with
    // a 13-byte AAD that is itself a partial GHASH block. Both key sizes.
    : ( Vec u ) lk ( hx `000102030405060708090a0b0c0d0e0f` )
    : ( Vec u ) lk32 ( hx `000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f` )
    : ( Vec u ) liv ( hx `000102030405060708090a0b` )
    : ( Vec u ) laad ( hx `a0a1a2a3a4a5a6a7a8a9aaabac` )
    : ( Vec u ) lpt ( hx `0b2a496887a6c5e4032241607f9ebddcfb1a39587796b5d4f31231506f8eadcceb0a29486786a5c4e30221405f7e9dbcdbfa1938577695b4d3f211304f6e8daccbea0928476685a4c3e201203f5e7d9cbbdaf91837567594b3d2f1102f4e6d8cabcae90827466584a3c2e1001f3e5d7c9bbad9f81736557493b2d1f00f2e4d6c8baac9e80726456483a2c1e0ff1e3d5c7b9ab9d8f71635547392b1d0ef0e2d4c6b8aa9c8e70625446382a1c0dffe1d3c5b7a99b8d7f61534537291b0cfee0d2c4b6a89a8c7e60524436281a0bfdefd1c3b5a7998b7d6f51433527190afceed0c2b4a6988a7c6e504234261809fbeddfc1b3a597897b6d5f4133251708faecdec0b2a496887a6c5e4032241607f9ebddcfb1a39587796b5d4f31231506f8eadcceb0a29486786a5c4e3022140` )
    : ( Vec u ) l128 ( aes128_gcm_encrypt lk liv laad lpt )
    = fails + fails ( check `long128` l128 `9846eea6e1bd32b048f020ea493dcdd4483c23be247b48221533c07d7bca0fa06eaef2bf93061227a3f628a79ff74a2e17650dc853f1a3cffdbc63e2e5229b4851e4fc66182a4fbae0d2707f436475c7d3767c733ecae856452f36c79307e784cbefa21c314dbaf0039d9fdfecd78b6740696218b47b5f8db60e4f82c3c4b115e51e492bb87167fc770a45b5a0771a32e837caea6d82dc925f2c2368ba9b117efc6cd1138d632a8efe7c93e95057eb3d8e1bdeb5c8ff7687197d615273ebf8bf433b25a616474755cfb42218aeadabee07ccd86f2c5281cca78ce131ce782d45898c2e216f8635c848adc751d7591d1a14709f71558f0537dca964fd28270f38fcfdc87bb029f0a598ccbd5806b1257a964aa462ae1be03a9b5424d32060d1f9efccad090fc5f901cfe4725101df147a91385ab7f32c4e64c460149d` )
    : ( Vec u ) l256 ( aes256_gcm_encrypt lk32 liv laad lpt )
    = fails + fails ( check `long256` l256 `4c289f73424307ff8e63d6ebce77c5b178ccbe6c87edeaa8cb75d4d572e7ad7eea1a87b4c847b75c97a65eadd7f9b58435a379b50da0366eec653b29578d78423bd6cf5294b7a3c5dfb6ab4ed0d173748350307a413526fc4e2f6fdc57bed4016032b0ee8307ad9e3ddedfb2574b7c0321ddbb53f4f370eede4d863d8dc8236230f8c92eb3f18e378b438941c2c4719e4d6e5aedc207a61effcd59a715dcc4a2f81d37dd0ef9e93ac4e17c3a007e9b87c6b4539a5c5d668836ad5177be2bbadf58260352ca3bd3ed74345246059f2498da2481ee8ad64fe542c3eb57ee8662f66869bd2741e6e6217105d9882aafa1adb3a9e00d0a865c510459360304328f6d1ffbbbf81a7c8dda74fd3367c8b387d621aef395f71d347b823d5c01657a1787ea09f700dd436bd3713e1b1ab031a2413c630062b61039b8f127973f` )
    ?? ( aes256_gcm_decrypt lk32 liv laad l256 ) {
        T lp → { = fails + fails ( check `long256_open` lp `0b2a496887a6c5e4032241607f9ebddcfb1a39587796b5d4f31231506f8eadcceb0a29486786a5c4e30221405f7e9dbcdbfa1938577695b4d3f211304f6e8daccbea0928476685a4c3e201203f5e7d9cbbdaf91837567594b3d2f1102f4e6d8cabcae90827466584a3c2e1001f3e5d7c9bbad9f81736557493b2d1f00f2e4d6c8baac9e80726456483a2c1e0ff1e3d5c7b9ab9d8f71635547392b1d0ef0e2d4c6b8aa9c8e70625446382a1c0dffe1d3c5b7a99b8d7f61534537291b0cfee0d2c4b6a89a8c7e60524436281a0bfdefd1c3b5a7998b7d6f51433527190afceed0c2b4a6988a7c6e504234261809fbeddfc1b3a597897b6d5f4133251708faecdec0b2a496887a6c5e4032241607f9ebddcfb1a39587796b5d4f31231506f8eadcceb0a29486786a5c4e3022140` ) ( vec_free [u] lp ) }
        F _ → { ( nurl_print `long256_open: FAIL rejected\n` ) = fails + fails 1 }
    }

    ( vec_free [u] zk ) ( vec_free [u] ziv ) ( vec_free [u] z1 )
    ( vec_free [u] e1 ) ( vec_free [u] e2 ) ( vec_free [u] e3 ) ( vec_free [u] dab )
    ( vec_free [u] lk ) ( vec_free [u] lk32 ) ( vec_free [u] liv )
    ( vec_free [u] laad ) ( vec_free [u] lpt ) ( vec_free [u] l128 ) ( vec_free [u] l256 )
    ( vec_free [u] key ) ( vec_free [u] iv ) ( vec_free [u] empty )
    ( vec_free [u] p3 ) ( vec_free [u] s3 ) ( vec_free [u] p4 ) ( vec_free [u] aad ) ( vec_free [u] s4 )
    ( vec_free [u] k256z ) ( vec_free [u] ivz ) ( vec_free [u] p14 ) ( vec_free [u] s14 )
    ( vec_free [u] k256 ) ( vec_free [u] p16 ) ( vec_free [u] s16 )

    ? == fails 0 { ( nurl_print `aes-gcm: all vectors PASS\n` ) } { ( nurl_print `aes-gcm: FAILURES\n` ) }
    ^ fails
}
