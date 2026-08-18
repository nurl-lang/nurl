# pki-server — Pure-NURL Private PKI Service & CA

A high-performance, self-contained Private PKI (Public Key Infrastructure) Certificate Authority and HTTP microservice written entirely in **pure NURL**.

It is a complete, native re-implementation of the reference Private PKI architecture, featuring zero external dependencies, no shellouts to `openssl` binaries, native ASN.1 DER encoding, ECDSA P-256 cryptography, automated CA initialization, device enrollment/renewal, operational certificate issuance, RFC 5280 CRL generation, API key authentication, and a built-in modern server-rendered Web UI.

---

## Features

- **Pure NURL Cryptography**: Native ECDSA P-256 key generation, SHA-256 hashing, ASN.1 DER encoding/decoding, X.509 v3 TBSCertificate signing, SEC1 EC private key formatting, and RFC 5280 CRL generation.
- **Two-Tier Device Lifecycle**:
  1. **Enrollment / Initial Certificate (`POST /init`)**: Devices register with a shared initialization key (`DEVICE_INIT_KEY`).
  2. **Renewal (`POST /renew_initial_cert`)**: Seamlessly renew initial certificates before expiration.
  3. **Operational Issuance (`POST /request-cert`)**: Issue short- or long-lived operational certificates by presenting and cryptographically proving possession of the initial certificate.
- **Revocation & CRL (`POST /revoke`, `GET /crl`)**: Revoke certificates by serial number or certificate PEM. Automatically updates OpenSSL-compatible `index.txt` and regenerates the standard RFC 5280 X.509 CRL. Revoking a certificate immediately invalidates device enrollment.
- **Authentication**:
  - `MANAGEMENT_KEY` enforced on management endpoints (`POST /revoke`, `GET /crl`) via `X-API-Key` header, `Authorization: Bearer <key>`, or `?api_key=` query parameter.
  - `DEVICE_INIT_KEY` enforced during device enrollment and initial certificate renewal.
- **Web UI & REST API**: Responsive HTML dashboard, certificate generation forms (with one-click clipboard copy and `.crt`/`.key` downloads), revocation forms, and interactive API documentation.
- **OpenSSL Compatibility**: Certificates, keys, and CRLs are 100% standard and verified with `openssl verify -CAfile ca.crt cert.crt` and `openssl crl -in ca.crl -text`.

---

## Directory Structure

```text
packages/pki-server/
├── nurl.toml               # Package metadata & dependencies (deps/http)
├── README.md               # Documentation & API specifications
├── src/
│   ├── main.nu             # CLI entry point, argument parsing & server startup
│   ├── service.nu          # HTTP route controllers & request handlers
│   ├── pki.nu              # Core pure-NURL PKI engine (CA, X.509, CRL, ECDSA)
│   ├── auth.nu             # API Key & device key authentication
│   └── ui.nu               # Server-rendered Web UI views & default styling
├── static/
│   └── css/
│       └── style.css       # Modern CSS stylesheet
└── tests/
    ├── smoke.nu            # In-process pure-NURL crypto & engine unit tests
    └── pki_test.sh         # End-to-end integration test suite with OpenSSL assertions
```

---

## Installing, Building and Running

### 1. Install with nurlpkg
```bash
nurlpkg install pki-server
```

### 2. Optionally Build manually from source

From the repository root:

```bash
./nurl.sh packages/pki-server/src/main.nu packages/pki-server/pki-server
```

### 3. Run Server

```bash
./pki-server --port 8080 --host 0.0.0.0
```

### CLI Options & Environment Variables

| CLI Option | Environment Variable | Default | Description |
|---|---|---|---|
| `-p, --port` | `PORT` | `8080` | TCP listen port |
| `-h, --host` | `HOST` | `0.0.0.0` | Bind host address |
| `--ca-cert` | `CA_CERT` | `./certs/ca.crt` | Path to Root CA certificate |
| `--ca-key` | `CA_KEY` | `./certs/ca.key` | Path to Root CA private key |
| `--crl-file` | `CRL_FILE` | `./certs/ca.crl` | Path to generated CRL file |
| `--index-file` | `INDEX_FILE` | `./certs/index.txt` | Path to OpenSSL-style index.txt |
| `--initial-dir` | `INITIAL_CERTS_DIR` | `./certs/initial` | Directory storing initial enrollment certs |
| `--certs-dir` | `DEVICE_CERTS_DIR` | `./certs/certificates`| Directory storing operational certs |
| `--init-key` | `DEVICE_INIT_KEY` | `your-device-init-key` | Device enrollment shared secret |
| `--mgmt-key` | `MANAGEMENT_KEY` | `your-management-key-here` | Management API authentication key |
| `--ca-cn` | `PKI_FQDN` | `Private PKI CA` | Root CA Common Name |

---

## REST API Reference

### 1. Service Health Check

```http
GET /health
```

**Response (200 OK):**
```json
{
  "status": "healthy",
  "timestamp": "2026-08-18T20:00:00Z"
}
```

---

### 2. Download Root CA Certificate

```http
GET /ca-cert
```

**Response (200 OK):**
```json
{
  "ca_certificate": "-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----\n"
}
```

---

### 3. Device Initialization (Enrollment)

```http
POST /init
Content-Type: application/json

{
  "device_id": "sensor-node-01",
  "key": "your-device-init-key"
}
```

**Response (200 OK):**
```json
{
  "certificate": "-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----\n"
}
```

---

### 4. Renew Initial Certificate

```http
POST /renew_initial_cert
Content-Type: application/json

{
  "device_id": "sensor-node-01",
  "key": "your-device-init-key",
  "initial_cert": "-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----\n"
}
```

**Response (200 OK):**
```json
{
  "certificate": "-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----\n"
}
```

---

### 5. Request Operational Certificate

Supports both `application/json` and `application/x-www-form-urlencoded`.

```http
POST /request-cert
Content-Type: application/json

{
  "device_id": "sensor-node-01",
  "initial_cert": "-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----\n",
  "validity_days": 90
}
```

**Response (200 OK):**
```json
{
  "device_id": "sensor-node-01",
  "certificate": "-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----\n",
  "private_key": "-----BEGIN EC PRIVATE KEY-----\n...\n-----END EC PRIVATE KEY-----\n",
  "ca_certificate": "-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----\n",
  "expires": "2026-11-16T20:00:00Z"
}
```

---

### 6. Revoke Certificate

Requires Management API key in `X-API-Key` header, `Authorization: Bearer <key>`, or `?api_key=`.

```http
POST /revoke
Content-Type: application/json
X-API-Key: your-management-key-here

{
  "certificate": "-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----\n"
}
```

*Or revoke by hex serial number:*
```json
{
  "serial": "3a8f10b2c94d"
}
```

**Response (200 OK):**
```json
{
  "status": "success",
  "message": "Certificate with serial 3a8f10b2c94d has been revoked",
  "serial": "3a8f10b2c94d",
  "revocation_time": "2026-08-18T20:00:00Z",
  "crl": "-----BEGIN X509 CRL-----\n...\n-----END X509 CRL-----\n"
}
```

---

### 7. Download CRL (Certificate Revocation List)

```http
GET /crl?api_key=your-management-key-here
```

**Response (200 OK):**
```text
Content-Type: application/pkix-crl
Content-Disposition: attachment; filename=ca.crl

-----BEGIN X509 CRL-----
...
-----END X509 CRL-----
```

---

## Running the Test Suite

### 1. In-process Pure-NURL Unit & Crypto Smoke Tests

```bash
./nurl.sh packages/pki-server/tests/smoke.nu packages/pki-server/tests/smoke
./packages/pki-server/tests/smoke
```

### 2. End-to-End HTTP & OpenSSL Compatibility Test Suite

```bash
./packages/pki-server/tests/pki_test.sh
```
