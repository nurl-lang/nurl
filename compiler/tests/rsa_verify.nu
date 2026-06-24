// rsa_verify.nu — RSASSA PKCS#1 v1.5 and PSS verification against
// OpenSSL-generated RSA-2048 signatures (positive + negative cases).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/rsa.nu`

@ hx s raw → ( Vec u ) { ?? ( bytes_from_hex raw ) { T v → ^ v F _ → ^ ( vec_new [u] ) } }

@ main → i {
    : ~ i fails 0
    : ( Vec u ) n ( hx `ab1e5059185c2bc5c47ca2eae06e8e403ee787e98aad8d15d80d2346625adfa6404ae6cac58510ce3e40b917fde5dcd56e915851862733591ec8c9d375fb0ef5927fd0bad6f151c380a49d4dd9578106a8ade03f468b37905a9d6096b167f03b5d11ed737673cd6566a0f506b9c38811bc2d7854873dfb1ab8cdd15f4e053c256b3895c140c89fac7b930b90d165d40ee79ac54bc935aa9355a0a8ee0cfed79a96df1c306dd1b36d4d8d47e9b9a3ae41807e7551778c758c4b79fb4ee65c40817e5a40ffb98e19259d2ed4b0068d126c5a60a9aac1bd143c8ed29bb347ab321a12e365ed35c4ba9150fbcd3e36275a350fdaf5cb4b797e637b56bbd994288145` )
    : ( Vec u ) e ( hx `010001` )
    : ( Vec u ) sigp ( hx `644f4bab3d85f7971bdf0d212097535562e7fcefde00c7575b28f23cd6fe2156f931c01f71618d03ad68e4cb05903e4a4b1fdd80be5235ee3dc76816d7ccfff05f0501dba24cbae4925793378f49aeaafc9d1216614400279e734820a6dfb7b1868cd751a4b5f2b01f4d542e8d9f37646b7ee33cf2523e03a13b104fb74ca08cb7dab00771167107d95dbbf297bb49716a75dc47519eb18045f51d69120bb59cc310c56cd9fbcea114aee982aabf6fbad13dd84361b87c419e1c02745e0a44c3d7531358377b328c4f171c06eeb3bb73a57e2c80d30b9bdc38d35f5c89edf9dd5415d01a5e2b7fbec631847d217fd907f8b473058016fb47c99bce209635b2d1` )
    : ( Vec u ) sigpss ( hx `4821e780268e95ac996bd7c18c7e1ac76935408a618fcfd305761ad9c7a23e1ee1dfd62afeb19cd7629e119d87fe2f64c83cf3869b819ff5c50ba1f16528098b8359fe00633624214eeeb0571bfa03f4c5434b2dbdb4e0546ceafb28e043b09f1ac67c387f3d9ecac5522ac08da4676eb7fd971a987036cc7c848aab7e00be5677cf0aea462094e6aee5a219d254a9022a73d647417efadd470f9cc2d3c5e49a46bef9b0ce079b28840c8d30297c7820441071bed7b074bebff735fb3b2beb39fa36587641529a2e1c771000e0cf834d576d8cb75f9dfa694817995b8d79b9e7bf5b194575e01507a388886c5f1c2a7bf95f338e21afcf83739a0a7abd73ba99` )
    : ( Vec u ) digest ( hx `1031770a16d99b47df8643467958ecaa4c86ea2668c231b39cf7f9153a4f3640` )
    : ( Vec u ) wrong ( hx `0000000000000000000000000000000000000000000000000000000000000000` )

    ? ( rsa_pkcs1_verify_sha256 n e sigp digest ) { ( nurl_print `pkcs1_valid: PASS\n` ) } { ( nurl_print `pkcs1_valid: FAIL\n` ) = fails + fails 1 }
    ? ( rsa_pkcs1_verify_sha256 n e sigp wrong ) { ( nurl_print `pkcs1_wronghash: FAIL\n` ) = fails + fails 1 } { ( nurl_print `pkcs1_wronghash: PASS\n` ) }
    ? ( rsa_pss_verify_sha256 n e sigpss digest ) { ( nurl_print `pss_valid: PASS\n` ) } { ( nurl_print `pss_valid: FAIL\n` ) = fails + fails 1 }
    ? ( rsa_pss_verify_sha256 n e sigpss wrong ) { ( nurl_print `pss_wronghash: FAIL\n` ) = fails + fails 1 } { ( nurl_print `pss_wronghash: PASS\n` ) }
    // PSS sig must not verify under PKCS1 and vice-versa
    ? ( rsa_pkcs1_verify_sha256 n e sigpss digest ) { ( nurl_print `crossuse: FAIL\n` ) = fails + fails 1 } { ( nurl_print `crossuse: PASS\n` ) }

    ? == fails 0 { ( nurl_print `rsa: all checks PASS\n` ) } { ( nurl_print `rsa: FAILURES\n` ) }
    ^ fails
}
