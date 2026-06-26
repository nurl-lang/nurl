// pkey_ec_pem.nu — load an EC P-256 private key from PEM (SEC1 + PKCS#8)
// and check the scalar + derived public key against the openssl-known
// values for this key. Confirms the DER walk and base64 strip are right
// for both container shapes.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/pkey.nu`

@ __hexeq ( Vec u ) v s want → b {
    : String h ( bytes_to_hex v )
    : b ok ( nurl_str_eq ( string_data h ) want )
    ( string_free h )
    ^ ok
}

@ __check s tag s pem → i {
    ?? ( ec_p256_priv_from_pem pem ) {
        F e → { ( nurl_print tag ) ( nurl_print `: parse FAIL\n` ) ^ 1 }
        T scalar → {
            : ( Vec u ) pubk ( ec_p256_pub_from_priv scalar )
            : b sok ( __hexeq scalar `6c1885e9c5c0336f91e7820dcab6cc896ef4b56a1c8c4dc364f46d6956cc09ad` )
            : b pok ( __hexeq pubk `0432e2f1fac909d798b0ed01d92fe66c70cda69fc6d8f8625f0809c2cd15d8dd936e6226ed3894e91adb99aa1395266c8bf1fbf9f0d5a10fea3fd2821f8ccbd56c` )
            ( nurl_print tag )
            ( nurl_print ? sok `: priv PASS` `: priv FAIL` )
            ( nurl_print ? pok ` pub PASS\n` ` pub FAIL\n` )
            ( vec_free [u] scalar ) ( vec_free [u] pubk )
            ^ ? & sok pok 0 1
        }
    }
}

@ main → i {
    : ~ i fails 0
    = fails + fails ( __check `SEC1 ` `-----BEGIN EC PRIVATE KEY-----\nMHcCAQEEIGwYhenFwDNvkeeCDcq2zIlu9LVqHIxNw2T0bWlWzAmtoAoGCCqGSM49\nAwEHoUQDQgAEMuLx+skJ15iw7QHZL+ZscM2mn8bY+GJfCAnCzRXY3ZNuYibtOJTp\nGtuZqhOVJmyL8fv58NWhD+o/0oIfjMvVbA==\n-----END EC PRIVATE KEY-----\n` )
    = fails + fails ( __check `PKCS8` `-----BEGIN PRIVATE KEY-----\nMIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgbBiF6cXAM2+R54IN\nyrbMiW70tWocjE3DZPRtaVbMCa2hRANCAAQy4vH6yQnXmLDtAdkv5mxwzaafxtj4\nYl8ICcLNFdjdk25iJu04lOka25mqE5UmbIvx+/nw1aEP6j/Sgh+My9Vs\n-----END PRIVATE KEY-----\n` )
    ( nurl_print ? == fails 0 `ALL PASS\n` `SOME FAILED\n` )
    ^ 0
}
