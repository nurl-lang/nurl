// bench/http_server.js — minimal hello-world HTTP server for the
// peer-comparison benchmark (Tier D #3).
//
// Same shape as bench/http_server.nu and the Rust sibling. Two modes,
// one file — the bench harness runs both:
//   * default              → plaintext HTTP on 127.0.0.1:18082
//   * TLS_CERT + TLS_KEY set (PEM paths) → HTTPS on the port named by
//                            TLS_PORT (default 18445), via Node's
//                            built-in `https` module
//
// Serves "Hello, World!\n" (14 bytes, text/plain) on `/`. Uses only
// Node's built-in `http` / `https` modules — no dependencies — so the
// comparison stays "what ships in the standard distribution" (the same
// rule the existing bench/json_parse.{js,nu,py,rs} files follow).
//
// Run:
//     node bench/http_server.js                 # plaintext
//     TLS_CERT=c.pem TLS_KEY=k.pem node bench/http_server.js   # TLS
//
// The runner script bench/run_http.sh does this automatically.

const http = require('node:http');
const https = require('node:https');
const fs = require('node:fs');

const BODY = 'Hello, World!\n';

function handler(req, res) {
    res.writeHead(200, { 'content-type': 'text/plain; charset=utf-8' });
    res.end(BODY);
}

const certPath = process.env.TLS_CERT;
const keyPath = process.env.TLS_KEY;

let server;
let port;
let scheme;

if (certPath && keyPath) {
    const opts = {
        cert: fs.readFileSync(certPath),
        key: fs.readFileSync(keyPath),
    };
    server = https.createServer(opts, handler);
    port = Number(process.env.TLS_PORT) || 18445;
    scheme = 'https';
} else {
    server = http.createServer(handler);
    port = 18082;
    scheme = 'http';
}

// Default keep-alive timeout in Node 24 is 5s. Bump it so a 10s
// benchmark run doesn't see connection churn between hot requests.
server.keepAliveTimeout = 60_000;
server.headersTimeout = 65_000;

server.listen(port, '127.0.0.1', () => {
    console.log(`node ${scheme}_server listening on ${scheme}://127.0.0.1:${port}/`);
});
