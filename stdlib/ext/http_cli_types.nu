// Shared value types for the curl-executable client, without its I/O backend.
$ `stdlib/core/vec.nu`

: | HttpcErr { HttpcConnect HttpcTimeout HttpcTls HttpcDns HttpcInvalidUrl HttpcOther }
: HttpcResp { i status i blen ( Vec u ) body }

@ httpc_err_name HttpcErr error → s {
    ^ ?? error {
        HttpcConnect → `connect`
        HttpcTimeout → `timeout`
        HttpcTls → `tls`
        HttpcDns → `dns`
        HttpcInvalidUrl → `invalid URL`
        HttpcOther → `transport`
    }
}
