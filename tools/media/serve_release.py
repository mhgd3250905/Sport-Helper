"""Read-only LAN fixture for media acceptance; never uploads anything.

The optional control JSON is {"mode":"normal|slow|corrupt|offline"}.
Only video responses are throttled/corrupted, so submanifest validation is
exercised independently. Bind only on a trusted development LAN.
"""
import argparse
import functools
import http.server
import json
import threading
import time
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', required=True, type=Path)
    parser.add_argument('--port', type=int, default=8778)
    parser.add_argument('--secondary-port', type=int, default=8779)
    parser.add_argument('--control', required=True, type=Path)
    parser.add_argument('--log', required=True, type=Path)
    args = parser.parse_args()
    root = args.root.resolve(strict=True)
    lock = threading.Lock()

    def log(record):
        with lock, args.log.open('a', encoding='utf-8') as output:
            output.write(json.dumps({'time': time.time(), **record}) + '\n')

    class Handler(http.server.SimpleHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_GET(self):
            try:
                self.mode = json.loads(args.control.read_text()).get('mode', 'normal')
            except (OSError, ValueError):
                self.mode = 'normal'
            path = Path(self.translate_path(self.path)).resolve()
            if not path.is_relative_to(root) or not path.is_file():
                self.send_error(404)
                return
            if self.mode == 'offline':
                self.send_error(503, 'Local media fixture unavailable')
                log({'path': self.path, 'mode': self.mode, 'status': 503})
                return
            log({'path': self.path, 'mode': self.mode, 'status': 200,
                 'bytes': path.stat().st_size, 'port': self.server.server_port})
            try:
                super().do_GET()
            except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
                pass

        def copyfile(self, source, outputfile):
            video = self.path.split('?')[0].endswith('.mp4')
            changed = False
            while chunk := source.read(8192 if self.mode == 'slow' and video else 65536):
                if self.mode == 'corrupt' and video and not changed:
                    chunk = bytes([chunk[0] ^ 0xFF]) + chunk[1:]
                    changed = True
                outputfile.write(chunk)
                outputfile.flush()
                if self.mode == 'slow' and video:
                    time.sleep(.10)

    handler = functools.partial(Handler, directory=str(root))
    servers = [http.server.ThreadingHTTPServer(('0.0.0.0', port), handler)
               for port in [args.port, args.secondary_port]]
    for server in servers:
        threading.Thread(target=server.serve_forever, daemon=True).start()
    print(f'Read-only release fixture on ports {args.port}, {args.secondary_port}', flush=True)
    try:
        threading.Event().wait()
    except KeyboardInterrupt:
        for server in servers:
            server.shutdown()


if __name__ == '__main__':
    main()
