// smoke test: a tiny load, to prove the script and the system work at all
import http from 'k6/http';
import { check, sleep } from 'k6';
import { SLO, BASE, TAGS, student } from './slo.js';

export const options = {
  vus: 2,              // 2 virtual users
  duration: '20s',
  thresholds: SLO,
};

export default function () {
  const res = http.get(`${BASE}/api/courses?user=${student()}`, TAGS);
  check(res, {
    'status is 200': (r) => r.status === 200,
    'has 5 courses': (r) => r.json('courses').length === 5,
  });
  sleep(1);            // think time: the student reads the page
}
