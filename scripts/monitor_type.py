"""Type text into a QEMU guest through the human monitor protocol.

The tool connects to a QEMU monitor unix socket and converts each line
of input into sendkey commands, so that a guest without a working
serial console can be driven blindly over its VGA console.

usage: monitor_type.py <monitor-socket> type "some text"
       monitor_type.py <monitor-socket> key ret
       monitor_type.py <monitor-socket> screendump /path/screen.png
"""
import socket
import sys
import time

KEYMAP = {
    "a": "a", "b": "b", "c": "c", "d": "d", "e": "e", "f": "f",
    "g": "g", "h": "h", "i": "i", "j": "j", "k": "k", "l": "l",
    "m": "m", "n": "n", "o": "o", "p": "p", "q": "q", "r": "r",
    "s": "s", "t": "t", "u": "u", "v": "v", "w": "w", "x": "x",
    "y": "y", "z": "z",
    "0": "0", "1": "1", "2": "2", "3": "3", "4": "4",
    "5": "5", "6": "6", "7": "7", "8": "8", "9": "9",
    " ": "spc",
    "-": "minus",
    "=": "equal",
    "[": "bracket_left",
    "]": "bracket_right",
    ";": "semicolon",
    "'": "apostrophe",
    "`": "grave_accent",
    "\\": "backslash",
    ",": "comma",
    ".": "dot",
    "/": "slash",
    "\n": "ret",
    "\t": "tab",
}

SHIFTMAP = {
    "A": "a", "B": "b", "C": "c", "D": "d", "E": "e", "F": "f",
    "G": "g", "H": "h", "I": "i", "J": "j", "K": "k", "L": "l",
    "M": "m", "N": "n", "O": "o", "P": "p", "Q": "q", "R": "r",
    "S": "s", "T": "t", "U": "u", "V": "v", "W": "w", "X": "x",
    "Y": "y", "Z": "z",
    "!": "1", "@": "2", "#": "3", "$": "4", "%": "5",
    "^": "6", "&": "7", "*": "8", "(": "9", ")": "0",
    "_": "minus",
    "+": "equal",
    "{": "bracket_left",
    "}": "bracket_right",
    ":": "semicolon",
    "\"": "apostrophe",
    "~": "grave_accent",
    "|": "backslash",
    "<": "comma",
    ">": "dot",
    "?": "slash",
}


class Monitor:
    """Minimal client for the QEMU human monitor protocol."""

    def __init__(self, path: str) -> None:
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.connect(path)
        self.sock.settimeout(5)
        self._drain()

    def _drain(self) -> None:
        try:
            while True:
                data = self.sock.recv(65536)
                if not data:
                    return
                if data.endswith(b"(qemu) "):
                    return
        except socket.timeout:
            return

    def command(self, command: str) -> None:
        self.sock.sendall(command.encode("ascii") + b"\n")
        self._drain()

    def send_key(self, key: str) -> None:
        self.command(f"sendkey {key}")
        time.sleep(0.06)

    def type_text(self, text: str) -> None:
        for char in text:
            if char in KEYMAP:
                self.send_key(KEYMAP[char])
            elif char in SHIFTMAP:
                self.send_key(f"shift-{SHIFTMAP[char]}")
            else:
                raise ValueError(f"no key mapping for {char!r}")


def main() -> int:
    """Run a single monitor command."""
    monitor_path = sys.argv[1]
    action = sys.argv[2]
    monitor = Monitor(monitor_path)
    if action == "type":
        monitor.type_text(sys.argv[3])
    elif action == "typeline":
        monitor.type_text(sys.argv[3] + "\n")
    elif action == "key":
        monitor.send_key(sys.argv[3])
    elif action == "screendump":
        monitor.command(f"screendump {sys.argv[3]} -f png")
        time.sleep(0.5)
    else:
        raise SystemExit(f"unknown action: {action}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
