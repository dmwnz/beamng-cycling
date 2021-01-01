import socket
import sys

sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server_address = ('localhost', 20201)
sock.connect(server_address)

while True:
    buf = sock.recv(4096)
    msg = buf.decode('utf-8')
    print(msg)