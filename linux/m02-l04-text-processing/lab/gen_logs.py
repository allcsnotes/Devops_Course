# Generates the GENERATED SAMPLE logs for M02-L04 (not real traffic). Runs inside the web-01 lab container (python3).
#   access.log : nginx "combined" format, allcsvideos.com, 19 Oct 2026 20:00-21:51 (+0530)
#   api.log    : the API's application log (the Python stand-in from M02-L03)
# Staged incident: release v2.14.0 at 21:39:52 sets PAYMENT_TIMEOUT_MS=300, so from 21:40 most POST /api/checkout -> 500.
# Side story: 192.0.2.66 hammers POST /login (401) from 21:05.  All IPs are documentation ranges (RFC 5737), emails example.com.
import random, sys
from datetime import datetime, timedelta
random.seed(2404)
OUT = sys.argv[1] if len(sys.argv) > 1 else '.'
D0 = datetime(2026, 10, 19, 20, 0, 0); END = datetime(2026, 10, 19, 21, 52, 0)
INC = datetime(2026, 10, 19, 21, 40, 0); HAM0 = datetime(2026, 10, 19, 21, 5, 0)
HAM = '192.0.2.66'
IPS = [f'198.51.100.{i}' for i in range(2, 250)] + [f'203.0.113.{i}' for i in range(2, 200)]
random.shuffle(IPS); IPS = IPS[:310]
W = [1 / (i + 3) ** .7 for i in range(len(IPS))]
UAS = ['Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0 Safari/537.36',
       'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_6) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15',
       'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0 Mobile Safari/537.36',
       'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148',
       'Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:131.0) Gecko/20100101 Firefox/131.0']
UA_OF = {ip: random.choice(UAS) for ip in IPS}
SLUGS = ['devops', 'dsa', 'system-design', 'spring-boot', 'genai']
REQ = [  # method, path-maker, weight
    ('GET', lambda: '/', 10), ('GET', lambda: '/courses', 9), ('GET', lambda: '/courses/' + random.choice(SLUGS), 13),
    ('GET', lambda: '/static/app.3f9c.js', 9), ('GET', lambda: '/static/style.8a21.css', 8), ('GET', lambda: '/api/courses', 8),
    ('GET', lambda: '/api/progress', 7), ('POST', lambda: '/api/progress', 4), ('GET', lambda: '/api/cart', 5),
    ('POST', lambda: '/api/cart', 3), ('POST', lambda: '/api/checkout', 3.2), ('GET', lambda: '/login', 3), ('POST', lambda: '/login', 3),
    ('GET', lambda: f'/videos/{random.choice(SLUGS)}/lesson-{random.randint(1, 24):02d}.m3u8', 6), ('GET', lambda: '/favicon.ico', 2)]
RW = [r[2] for r in REQ]
SIZE = {'/': 18432, '/courses': 24117, '/static/app.3f9c.js': 187342, '/static/style.8a21.css': 31877, '/api/courses': 4211,
        '/api/progress': 388, '/api/cart': 612, '/login': 6120, '/favicon.ico': 1150}
acc, api = [], []   # (time, text)
order = [48190]
def ts_acc(t): return t.strftime('%d/%b/%Y:%H:%M:%S') + ' +0530'
def ts_api(t): return t.strftime('%Y-%m-%d %H:%M:%S') + ',%03d' % (t.microsecond // 1000)
def A(t, ip, m, p, st, b, ref='-', ua=None):
    acc.append((t, f'{ip} - - [{ts_acc(t)}] "{m} {p} HTTP/1.1" {st} {b} "{ref}" "{ua or UA_OF.get(ip, UAS[0])}"'))
def L(t, lvl, msg):
    if not t.microsecond: t = t + timedelta(microseconds=random.randint(1000, 999000))
    api.append((t, f'{ts_api(t)} {lvl:<5} {msg}'))
def mask(ip): return 'u' + str(sum(map(int, ip.split('.'))) * 7 % 900 + 100)
def checkout(t, ip):
    tries = random.choice([1, 2, 2, 3]) if t >= INC else 1
    tt = t
    for k in range(tries):
        order[0] += 1; oid = f'A-{order[0]}'
        if t >= INC and random.random() < .9:
            A(tt, ip, 'POST', '/api/checkout', 500, 61, 'https://allcsvideos.com/cart')
            L(tt, 'ERROR', f'checkout: payment failed for order {oid}')
            api.append((tt, 'Traceback (most recent call last):'))
            api.append((tt, '  File "/opt/allcsvideos/api.py", line 141, in checkout'))
            api.append((tt, '    charge = payments.charge(order, timeout_ms=cfg.PAYMENT_TIMEOUT_MS)'))
            api.append((tt, 'TimeoutError: payment gateway did not answer within 300 ms'))
        else:
            A(tt, ip, 'POST', '/api/checkout', 200, random.randint(180, 240), 'https://allcsvideos.com/cart')
            L(tt, 'INFO', f'checkout: order {oid} paid')
            return
        tt += timedelta(seconds=random.randint(4, 15), microseconds=random.randint(1000, 900000))
L(D0 - timedelta(minutes=12), 'INFO', 'allcsvideos-api v2.13.4 starting (workers=2)')
L(D0 - timedelta(minutes=12) + timedelta(seconds=1), 'INFO', 'config: loaded /srv/allcsvideos/app.env (PAYMENT_TIMEOUT_MS=3000)')
L(D0 - timedelta(minutes=12) + timedelta(seconds=1, microseconds=1500), 'INFO', 'listening on 127.0.0.1:8080')
t = D0
while t < END:
    t += timedelta(seconds=random.expovariate(0.72))
    if t >= END: break
    ip = random.choices(IPS, W)[0]
    m, pf, _ = random.choices(REQ, RW)[0]
    p = pf()
    ref = random.choice(['-', 'https://allcsvideos.com/', 'https://allcsvideos.com/courses', f'https://allcsvideos.com/courses/{random.choice(SLUGS)}'])
    st, b = 200, SIZE.get(p, 0)
    if p.startswith('/courses/'): b = random.randint(21000, 29000)
    if p.startswith('/videos/'): b = random.randint(900, 1400)
    if p.startswith('/static/') and random.random() < .35: st, b = 304, 0
    if p == '/api/progress' and m == 'POST': b = 2
    if p == '/api/cart' and m == 'POST': b = random.randint(400, 700)
    if p == '/login' and m == 'POST':
        if random.random() < .1: st, b = 401, 43; L(t, 'WARN', f'auth: login failed for {mask(ip)}@example.com from {ip}')
        else: st, b = 302, 0
    if p == '/api/checkout':
        checkout(t, ip); continue
    A(t, ip, m, p, st, b, ref)
# from 21:40 more people reach checkout (and retry): about 4 a minute
tc = INC + timedelta(seconds=3, microseconds=512000)
while tc < END:
    checkout(tc, random.choices(IPS, W)[0])
    tc += timedelta(seconds=random.expovariate(4 / 60))
# bots
for k in range(14):
    tb = D0 + timedelta(seconds=random.randint(0, 6700))
    A(tb, '192.0.2.14', 'GET', random.choice(['/wp-login.php', '/.env', '/admin.php', '/xmlrpc.php']), 404, 162, '-', 'Mozilla/5.0 (compatible; scanner)')
# one unrelated 500 earlier: a DB hiccup on /api/progress
tx = datetime(2026, 10, 19, 20, 31, 17, 412000); ipx = IPS[40]
A(tx, ipx, 'GET', '/api/progress', 500, 61, 'https://allcsvideos.com/courses/dsa')
L(tx, 'ERROR', 'progress: database query failed for /api/progress')
api.append((tx, 'Traceback (most recent call last):'))
api.append((tx, '  File "/opt/allcsvideos/api.py", line 88, in progress'))
api.append((tx, '    rows = db.fetch_progress(user_id)'))
api.append((tx, 'ConnectionResetError: [Errno 104] Connection reset by peer'))
L(datetime(2026, 10, 19, 20, 47, 5), 'WARN', 'email: SMTP send slow (2310 ms), receipt queued')
for mm in range(0, 112, 5):
    L(D0 + timedelta(minutes=mm, seconds=30), 'INFO', 'health: ok (db 3 ms, redis 1 ms)')
# the hammering IP
th = HAM0
while th < END:
    A(th, HAM, 'POST', '/login', 401, 43, '-', 'python-requests/2.32.3')
    L(th, 'WARN', f'auth: login failed for {random.choice(["admin", "test", "info", "sales", "support"])}@example.com from {HAM}')
    th += timedelta(seconds=random.choice([2, 3, 3, 4]))
# the release
rt = datetime(2026, 10, 19, 21, 39, 52, 108000)
L(rt, 'INFO', 'deploy: release v2.14.0 started by priya')
L(rt + timedelta(seconds=3), 'INFO', 'allcsvideos-api v2.14.0 starting (workers=2)')
L(rt + timedelta(seconds=4), 'INFO', 'config: loaded /srv/allcsvideos/app.env (PAYMENT_TIMEOUT_MS=300)')
L(rt + timedelta(seconds=4, microseconds=2000), 'INFO', 'listening on 127.0.0.1:8080')
acc.sort(key=lambda x: x[0]); api.sort(key=lambda x: x[0])   # stable: tracebacks stay under their ERROR line
open(OUT + '/access.log', 'w').write(''.join(l + '\n' for _, l in acc))
open(OUT + '/api.log', 'w').write(''.join(l + '\n' for _, l in api))
print(len(acc), 'access lines', len(api), 'api lines')
