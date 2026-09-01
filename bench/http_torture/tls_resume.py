#!/usr/bin/env python3
# tls_resume.py host port — decide, reliably, whether a TLS 1.3 server
# supports session resumption. The TLS 1.3 NewSessionTicket is a
# POST-handshake message, so a probe that quits right after the handshake
# (echo Q) never sees it; this one sends a real HTTP request and reads the
# reply, holding the connection open long enough for the ticket to arrive.
#
# Step 1: connect, send a request, save any session (-sess_out). If no
#         session file is written, the server issued no ticket.
# Step 2: reconnect reusing that session (-sess_in). openssl prints
#         "Reused" iff the server accepted the resumption.
#
# Prints one markdown-cell fragment:  "<yes|no> | <full? >| <resumed?>"
import subprocess, sys, os, tempfile

host, port = sys.argv[1], sys.argv[2]
REQ = b"GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"

def s_client(extra):
    # Hold the connection open ~0.6s after the request so the TLS 1.3
    # post-handshake NewSessionTicket record is received (and, with
    # -sess_out, written) before openssl shuts the socket. Driving stdin
    # from a shell `{ printf; sleep; }` is the timing that reliably works;
    # closing stdin any earlier races the ticket.
    args = " ".join(["openssl", "s_client", "-connect", f"{host}:{port}",
                     "-tls1_3"] + extra)
    cmd = "{ printf %s; sleep 0.6; } | %s 2>&1" % (
        "'GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n'",
        args)
    try:
        out = subprocess.run(["bash", "-c", cmd], capture_output=True,
                             timeout=15).stdout
    except subprocess.TimeoutExpired:
        out = b""
    return out.decode(errors="replace")

sess = tempfile.NamedTemporaryFile(delete=False, suffix=".sess").name
try:
    os.unlink(sess)
except OSError:
    pass

try:
    out1 = s_client(["-sess_out", sess])
except Exception as e:
    print(f"no | probe-failed ({e}) | -"); sys.exit(0)

issued = os.path.exists(sess) and os.path.getsize(sess) > 0
ticket_line = "yes" if ("New Session Ticket" in out1 or issued) else "no"

resumed = "no"
if issued:
    out2 = s_client(["-sess_in", sess])
    resumed = "yes (Reused)" if "Reused" in out2 else "no"

supported = "yes" if (issued and resumed.startswith("yes")) else "no"
print("%s | %s | %s" % (supported,
                        "ticket issued" if issued else "no ticket issued",
                        resumed))
try:
    os.unlink(sess)
except OSError:
    pass
