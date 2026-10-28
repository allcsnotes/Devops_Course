// the closed model: 20 VUs in a loop; a new request starts only when the last one ends
import http from 'k6/http';
import { sleep } from 'k6';
import { BASE, TAGS, student } from './slo.js';

export const options = {
  scenarios: {
    closed: { executor: 'constant-vus', vus: 20, duration: '40s' },
  },
};

export default function () {
  http.get(`${BASE}/api/courses?user=${student()}`, TAGS);
  sleep(1);
}
