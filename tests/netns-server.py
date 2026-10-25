#!/usr/bin/env python3
"""Test server for netns-e2e.sh: HTTP GET /<bytes> streams zeros, PUT discards,
UDP: any datagram triggers a paced 40 Mbit/s burst of 1400-byte packets for 3 s."""
import http.server, socketserver, socket, threading, time, sys

class H(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def log_message(self, *a): pass
    def do_GET(self):
        n = int(self.path.strip("/") or "0")
        self.send_response(200)
        self.send_header("Content-Length", str(n))
        self.end_headers()
        buf = b"\0" * 65536
        while n > 0:
            k = min(n, len(buf))
            self.wfile.write(buf[:k])
            n -= k
    def do_PUT(self):
        n = int(self.headers.get("Content-Length", "0"))
        while n > 0:
            d = self.rfile.read(min(n, 65536))
            if not d: break
            n -= len(d)
        self.send_response(200)
        self.send_header("Content-Length", "0")
        self.end_headers()

class S(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True

def udp():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.bind(("0.0.0.0", 9001))
    while True:
        _, addr = s.recvfrom(64)
        def burst(addr=addr):
            pkt = b"\0" * 1400
            rate = 40e6 / 8 / 1400   # packets per second
            end = time.time() + 3
            sent = 0
            t0 = time.time()
            while time.time() < end:
                s.sendto(pkt, addr); sent += 1
                ahead = sent / rate - (time.time() - t0)
                if ahead > 0: time.sleep(ahead)
        threading.Thread(target=burst, daemon=True).start()

threading.Thread(target=udp, daemon=True).start()
S(("0.0.0.0", 9000), H).serve_forever()
