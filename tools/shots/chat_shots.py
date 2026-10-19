"""Screenshots of the chat home from the web build of
test_screens/web_shots_main.dart (see that file). Usage:
  PYTHONPATH=<playwright> python3 tools/shots/chat_shots.py <build/web> <out dir> shot[:file[:steps]] ...
steps (after the page has settled), '|'-separated: cX,Y = click at CSS px
(the mouse then leaves the page so no hover tooltip shows), wS = wait S s. E.g. card:chat-player-work:c138,691|w3|c287,790|w1.5
Serves the build on 127.0.0.1:8767, renders a 390x844 phone at 3x.
"""
import http.server, os, sys, threading, functools, time
from playwright.sync_api import sync_playwright

root, out, shots = sys.argv[1], sys.argv[2], sys.argv[3:]
handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=root)
handler.log_message = lambda *a: None
srv = http.server.ThreadingHTTPServer(('127.0.0.1', 8767), handler)
threading.Thread(target=srv.serve_forever, daemon=True).start()
exe = os.environ.get('CHROME')
with sync_playwright() as p:
    b = p.chromium.launch(executable_path=exe, args=['--use-gl=swiftshader', '--enable-unsafe-swiftshader'])
    for spec in shots:
        name, _, rest = spec.partition(':')
        file, _, steps = rest.partition(':')
        page = b.new_page(viewport={'width': 390, 'height': 844}, device_scale_factor=3)
        page.on('console', lambda m: print('  console:', m.text[:300]) if 'rror' in m.text else None)
        page.goto(f'http://127.0.0.1:8767/?shot={name}', wait_until='load', timeout=60000)
        page.wait_for_selector('flutter-view', timeout=60000)
        time.sleep(float(os.environ.get('SHOT_WAIT', '6')))
        for step in filter(None, steps.split('|')):
            if step[0] == 'c':
                x, y = map(float, step[1:].split(','))
                page.mouse.click(x, y)
                page.mouse.move(1, 1)
            elif step[0] == 'w':
                time.sleep(float(step[1:]))
        path = os.path.join(out, (file or f'chat-{name}') + '.png')
        page.screenshot(path=path)
        print('wrote', path)
        page.close()
    b.close()
srv.shutdown()
