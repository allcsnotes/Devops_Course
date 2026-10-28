#!/usr/bin/env python3
# Fills a log file with realistic debug lines until it reaches a size (bytes) or the disk is full. Usage: gen_fill.py FILE SIZE [START]
import sys, random, time
p, size = sys.argv[1], int(sys.argv[2]); r = random.Random(2410)
t = time.mktime(time.strptime(sys.argv[3] if len(sys.argv) > 3 else '2026-10-19 09:12:00', '%Y-%m-%d %H:%M:%S'))
n = 0
try:
    with open(p, 'a') as f:
        while n < size:
            t += r.random() * 0.06
            lvl = 'DEBUG' if 'debug' in p else r.choice(['INFO'] * 9 + ['WARN'])
            msg = (f'cache lookup key=course:{r.randint(1, 240)}:lesson:{r.randint(1, 60)} hit={r.choice(["true", "false"])} took={r.randint(1, 9)}ms'
                   if lvl == 'DEBUG' else f'GET /api/courses/{r.randint(1, 240)} 200 {r.randint(4, 90)}ms')
            s = time.strftime('%Y-%m-%dT%H:%M:%S', time.localtime(t)) + f' {lvl} {msg}\n'
            f.write(s); n += len(s)
except OSError as e:
    print('stopped:', e)
print(p, n)
