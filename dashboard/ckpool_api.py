import json
import socket
import struct

CKPOOL_SOCKET = "/tmp/ckpool/stratifier"


def query_ckpool(command, timeout=2):
    """Send a command to the CKPool stratifier API."""

    if command not in ("poolstats", "clients", "workers"):
        raise ValueError("Unsupported CKPool command")

    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
        sock.settimeout(timeout)
        sock.connect(CKPOOL_SOCKET)

        message = command.encode("utf-8")

        # CKPool Unix messages use a 4-byte length prefix.
        sock.sendall(struct.pack("<I", len(message)) + message)

        # CKPool closes the write side after sending a message.
        sock.shutdown(socket.SHUT_WR)

        header = receive_exact(sock, 4)
        length = struct.unpack("<I", header)[0]

        if length > 4 * 1024 * 1024:
            raise ValueError("CKPool response too large")

        response = receive_exact(sock, length)
        return json.loads(response.decode("utf-8"))


def receive_exact(sock, length):
    data = bytearray()

    while len(data) < length:
        chunk = sock.recv(length - len(data))

        if not chunk:
            raise ConnectionError("CKPool closed connection")

        data.extend(chunk)

    return bytes(data)


def get_poolstats():
    return query_ckpool("poolstats")


def get_clients():
    return query_ckpool("clients")


def get_workers():
    return query_ckpool("workers")


def dsps_to_ghs(dsps):
    """Convert difficulty shares per second to GH/s."""
    if dsps is None:
        return None

    return float(dsps) * (2 ** 32) / 1e9
