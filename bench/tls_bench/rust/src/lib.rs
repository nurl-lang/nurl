// bench/tls_bench/rust/src/lib.rs — what the client-side binaries share:
// a rustls ClientConfig pinned to one group and one suite, and the
// one-line `key=value` result format bench/tls_bench/gen_tls_results.py
// reads.

use std::sync::Arc;

use rustls::client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier};
use rustls::client::Resumption;
use rustls::crypto::aws_lc_rs::{cipher_suite, default_provider, kx_group};
use rustls::crypto::{verify_tls12_signature, verify_tls13_signature, CryptoProvider};
use rustls::pki_types::{CertificateDer, ServerName, UnixTime};
use rustls::{ClientConfig, DigitallySignedStruct, Error, SignatureScheme};

/// Accepts the self-signed benchmark certificate, but still verifies the
/// CertificateVerify signature with the provider's real algorithms — a
/// client that skipped it would understate what a real handshake costs.
#[derive(Debug)]
struct BenchVerifier(Arc<CryptoProvider>);

impl ServerCertVerifier for BenchVerifier {
    fn verify_server_cert(
        &self,
        _: &CertificateDer<'_>,
        _: &[CertificateDer<'_>],
        _: &ServerName<'_>,
        _: &[u8],
        _: UnixTime,
    ) -> Result<ServerCertVerified, Error> {
        Ok(ServerCertVerified::assertion())
    }
    fn verify_tls12_signature(
        &self,
        m: &[u8],
        c: &CertificateDer<'_>,
        d: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, Error> {
        verify_tls12_signature(m, c, d, &self.0.signature_verification_algorithms)
    }
    fn verify_tls13_signature(
        &self,
        m: &[u8],
        c: &CertificateDer<'_>,
        d: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, Error> {
        verify_tls13_signature(m, c, d, &self.0.signature_verification_algorithms)
    }
    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        self.0.signature_verification_algorithms.supported_schemes()
    }
}

/// `group`: x25519 | p256 | mlkem (X25519MLKEM768) | default (the
/// provider's own list, X25519MLKEM768 first). `suite`: aes128 | chacha |
/// default. One group means one key share and no HelloRetryRequest.
pub fn client_config(group: &str, suite: &str, resume: bool) -> ClientConfig {
    let mut p = default_provider();
    match group {
        "x25519" => p.kx_groups = vec![kx_group::X25519],
        "p256" => p.kx_groups = vec![kx_group::SECP256R1],
        "mlkem" => p.kx_groups = vec![kx_group::X25519MLKEM768],
        _ => {}
    }
    match suite {
        "aes128" => p.cipher_suites = vec![cipher_suite::TLS13_AES_128_GCM_SHA256],
        "chacha" => p.cipher_suites = vec![cipher_suite::TLS13_CHACHA20_POLY1305_SHA256],
        "aes256" => p.cipher_suites = vec![cipher_suite::TLS13_AES_256_GCM_SHA384],
        _ => {}
    }
    let p = Arc::new(p);
    let mut cfg = ClientConfig::builder_with_provider(p.clone())
        .with_protocol_versions(&[&rustls::version::TLS13])
        .expect("TLS 1.3")
        .dangerous()
        .with_custom_certificate_verifier(Arc::new(BenchVerifier(p)))
        .with_no_client_auth();
    cfg.alpn_protocols = vec![b"http/1.1".to_vec()];
    cfg.resumption = if resume {
        Resumption::in_memory_sessions(4096)
    } else {
        Resumption::disabled()
    };
    cfg
}

/// The p-th percentile (0..=1000, per mille) of a SORTED sample.
pub fn pct(sorted: &[u32], per_mille: usize) -> u32 {
    if sorted.is_empty() {
        return 0;
    }
    let i = (sorted.len() * per_mille / 1000).min(sorted.len() - 1);
    sorted[i]
}

/// Minimal `--key value` argument lookup.
pub fn arg(args: &[String], key: &str, default: &str) -> String {
    args.iter()
        .position(|a| a == key)
        .and_then(|i| args.get(i + 1))
        .cloned()
        .unwrap_or_else(|| default.to_string())
}
