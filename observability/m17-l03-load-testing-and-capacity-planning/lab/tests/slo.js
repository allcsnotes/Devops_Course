// The allcsvideos API SLOs from lesson 1, as k6 thresholds. Every test imports them.
export const SLO = {
  http_req_failed: ['rate<0.001'],     // availability: 99.9 % of requests succeed
  http_req_duration: ['p(99)<500'],    // latency: 99 % of requests answer within 500 ms
};

export const BASE = __ENV.BASE_URL || 'http://localhost:8080';

// a different student each time, so the API's per-user cache doesn't answer for us
export const student = () => `student-${Math.floor(Math.random() * 1000000)}`;

// one name for every URL, so a million student ids don't become a million metric series
export const TAGS = { tags: { name: 'GET /api/courses' } };
