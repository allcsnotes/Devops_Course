// students.js: steady, open-model load from "students" (module 17, lesson 3): RATE requests per second, whatever happens.
// 70 % course list, 20 % "who am I" with a session cookie, 10 % progress writes. Students logged in BEFORE the test,
// on whatever served them then (setup), exactly like real users mid-migration.
// Every request is recorded twice: a counter per pool for the live SLO gate (Prometheus remote write), and one line per
// request in the console log, for the charts (time, pool, status, milliseconds, route, server).
import http from 'k6/http';
import { Counter } from 'k6/metrics';

const BASE = __ENV.BASE || 'http://10.0.201.5';
const RUN = __ENV.RUN || 'run';
const reqs = new Counter('allcs_reqs');        // tags: pool, ok
const slow = new Counter('allcs_slow');        // over 250 ms (the latency SLO from M20-L01)

export const options = {
  scenarios: {
    students: { executor: 'constant-arrival-rate', rate: +(__ENV.RATE || 40), timeUnit: '1s',
                duration: __ENV.DURATION || '5m', preAllocatedVUs: 60, maxVUs: 200 },
  },
  summaryTrendStats: ['avg', 'p(95)', 'p(99)', 'max'],
};

export function setup() {
  const cookies = [];
  for (let i = 1; i <= 200; i++) {
    const s = `s${String(i).padStart(4, '0')}@example.com`;
    const r = http.post(`${BASE}/api/login`, JSON.stringify({ student: s }), { headers: { 'Content-Type': 'application/json' } });
    cookies.push({ s, c: `session=${r.cookies.session[0].value}` });
  }
  return { cookies };
}

// every counter series exists from the first second, at 0: Prometheus increase() cannot see the first value of a
// series that appears in the middle of a window (a burst of errors inside one 5 s push would count as 0)
let primed = false;
export default function (data) {
  if (!primed) {
    for (const pool of ['vm', 'k8s']) { reqs.add(0, { pool, ok: 'false' }); reqs.add(0, { pool, ok: 'true' }); slow.add(0, { pool }); }
    primed = true;
  }
  const u = data.cookies[Math.floor(Math.random() * data.cookies.length)];
  const p = { timeout: '5s', tags: { name: 'x' }, headers: { Cookie: u.c } };
  const x = Math.random();
  let r, route, want;
  if (x < 0.7) { route = 'courses'; want = 200; p.tags.name = 'courses'; r = http.get(`${BASE}/api/courses`, p); }
  else if (x < 0.9) { route = 'me'; want = 200; p.tags.name = 'me'; r = http.get(`${BASE}/api/me`, p); }
  else { route = 'progress'; want = 201; p.tags.name = 'progress'; p.headers['Content-Type'] = 'application/json';
         r = http.post(`${BASE}/api/progress`, JSON.stringify({ student: u.s, lesson: Math.floor(Math.random() * 40) + 1, run: RUN }), p); }
  const pool = (r.headers['X-Edge-Pool'] || 'none').replace('_pool', '');
  const ok = r.status === want;
  reqs.add(1, { pool, ok: String(ok) });
  if (r.timings.duration > 250) slow.add(1, { pool });
  console.log(`${Date.now()} ${pool} ${r.status} ${r.timings.duration.toFixed(1)} ${route} ${r.headers['X-Served-By'] || '-'}`);
}
