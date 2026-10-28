// breakpoint test: raise the arrival rate until the API breaks, then stop
import http from 'k6/http';
import { check } from 'k6';
import { BASE, TAGS, student } from './slo.js';

export const options = {
  scenarios: {
    breakpoint: {
      executor: 'ramping-arrival-rate',
      startRate: 10,
      timeUnit: '1s',
      preAllocatedVUs: 50,
      maxVUs: 500,
      stages: [{ target: 150, duration: '2m20s' }],   // +1 request/s every second
    },
  },
  thresholds: {
    // stop when the API is clearly broken: more than 5 % errors
    http_req_failed: [{ threshold: 'rate<0.05', abortOnFail: true, delayAbortEval: '10s' }],
  },
};

export default function () {
  const res = http.get(`${BASE}/api/courses?user=${student()}`, TAGS);
  check(res, { 'status is 200': (r) => r.status === 200 });
}
