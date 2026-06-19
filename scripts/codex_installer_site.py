#!/usr/bin/env python3
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


class InstallerHandler(SimpleHTTPRequestHandler):
    def guess_type(self, path):
        suffix = Path(path).suffix.lower()
        if suffix in {".ps1", ".sh"}:
            return "text/plain; charset=utf-8"
        return super().guess_type(path)


def main():
    server = ThreadingHTTPServer(("0.0.0.0", 8091), InstallerHandler)
    print("Serving Codex installer files on 0.0.0.0:8091", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
