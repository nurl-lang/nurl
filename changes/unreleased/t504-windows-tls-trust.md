### Fixed

- **Verified TLS works on Windows** (Agora #504). The trust anchors came
  from `SSL_CERT_FILE` or three Unix bundle paths, none of which exists
  on Windows, so every `tls_connect`, `http_get` and `hub pull` to an
  `https://` server failed with a TLS error there. Windows keeps no bundle,
  and its certificate store holds only the roots the machine has needed
  so far, so reading that store would still miss most of them. When no
  bundle anchors the chain and `SSL_CERT_FILE` is unset, the anchor step
  now asks the Windows chain engine (`CertGetCertificateChain` with the
  SSL policy), which fetches a trusted root it has not seen yet. NURL's
  own checks (hostname, validity, chain links, CA constraints) still run
  first. crypt32 is loaded at run time, so no link line changes.
  `SSL_CERT_FILE` still replaces the system's trust rather than extending
  it. Elsewhere nothing changes.
