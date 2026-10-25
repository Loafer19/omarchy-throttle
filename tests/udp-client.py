#!/usr/bin/env python3
"""Ask netns-server.py for a 3 s, 40 Mbit/s UDP burst and print the received Mbit/s."""
import socket, time, sys
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4 << 20)
s.settimeout(1.0)
s.sendto(b"go", (sys.argv[1], 9001))
got = 0; t0 = None; last = None
try:
    while True:
        d = s.recv(2048)
        now = time.time()
        if t0 is None: t0 = now
        last = now; got += len(d)
except socket.timeout:
    pass
dur = (last - t0) if t0 and last and last > t0 else 1
print("%.1f" % (got * 8 / dur / 1e6))
