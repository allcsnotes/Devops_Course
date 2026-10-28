# M01-L04 · From Laptop to Production
> Video: Module 1, Lesson 4. Watch it first, then follow along here.

## What you'll learn
- Why "it runs on my laptop" is far from production: many users, failures, secrets, and traffic that grows overnight.
- The five parts of the allcsvideos platform: three services you deploy and two data stores you protect.
- The path of one request: DNS, load balancer, web, API, then cache or database.
- The delivery loop (code, build, test, release, run, observe) and which module teaches each stage.
- What allcsvideos looks like at the end of the course.

## Before you start
- Docker Desktop running, from [M01-L03](../m01-l03-setting-up-your-devops-lab/).
- Nothing else to install: Node.js and nginx run in containers.

## Files in this folder
| File | What it is |
|---|---|
| `web/package.json` | A tiny demo storefront with one script, `npm run dev`. |
| `web/server.js` | The demo dev server: serves `index.html` on port 3000. |
| `web/index.html` | The demo course catalog page (281 bytes). |

## Key ideas

**The allcsvideos stack**

| Part | What it is | Kind |
|---|---|---|
| Web (storefront) | The pages students see: catalog, lesson player, checkout | Service you deploy |
| API | Spring Boot (Java): accounts, enrollments, payments, progress | Service you deploy |
| Course Copilot | Python AI service that answers questions from the course material | Service you deploy |
| PostgreSQL | The database: users, courses, enrollments | Data you protect |
| Redis | In-memory cache: course catalog, login sessions | Data you protect |

A service can be thrown away and recreated. Data cannot.

**One request:** Lukas clicks a lesson. DNS turns `allcsvideos.com` into the load balancer's address. The load balancer picks a healthy web server (and skips a dead one). The web tier asks the API for the lesson data. The API checks Redis first; on a hit the database isn't touched, on a miss it reads PostgreSQL and keeps a copy in Redis. A question to Course Copilot goes through the API to the AI service.

**The loop and the course map**

| Stage | What happens | Module(s) |
|---|---|---|
| Foundation | Linux, then automation with Bash and Python | 2, 3 |
| Foundation | Networking: DNS, ports, HTTP, TLS | 4 |
| Code | Git, short branches, pull requests, review | 5 |
| Build | The code becomes a container image, identical on every machine | 6, 7 |
| Test | A pipeline builds, tests and lints every push (GitHub Actions) | 8 |
| Release | Versioned images promoted through staging to production (rolling, blue-green, canary) | 9 |
| Run | AWS, Terraform, Ansible | 10, 11, 12 |
| Run | Kubernetes, ending on EKS with GitOps | 13-15 |
| Observe | Metrics, logs, traces, alerts; then SLOs, incidents, disaster recovery | 16, 17 |
| Whole loop | DevSecOps; platform engineering and cost | 18, 19 |
| Wrap-up | Capstone projects; interview prep | 20, 21 |

**The destination:** an AWS region over two availability zones; EKS runs web, API and Course Copilot as pods in both zones; PostgreSQL on RDS with a standby; Redis next to the services. Nobody changes production by hand: a merge triggers a pipeline that builds and signs an image, and Argo CD makes the cluster match the repo (GitOps). Releases go out as canaries that roll back on their own if errors rise. Prometheus, Grafana, logs and traces watch everything, and the disaster recovery plan is tested in a capstone.

## Follow along
1. Run the demo storefront the way a developer does, with `npm run dev`, inside a Node container:
   ```bash
   cd setup/m01-l04-from-laptop-to-production
   docker run --rm -it --name storefront-dev -p 3000:3000 -v "$PWD/web:/app" -w /app node:22-bookworm-slim npm run dev
   ```
   You should see:
   ```
   > allcsvideos-web@0.1.0 dev
   > node server.js

   storefront ready on http://localhost:3000
   ```
   Open http://localhost:3000 in your browser: there is the course catalog. Press Ctrl+C to stop it.
2. Now one real request and response. Start the storefront's front door, an nginx web server, serving the same page on port 8080:
   ```bash
   docker run -d --name web -p 8080:80 -v "$PWD/web/index.html:/usr/share/nginx/html/index.html:ro" nginx:1.29-alpine
   ```
3. Ask for the response headers only:
   ```bash
   curl -sI http://localhost:8080
   ```
   You should see something like:
   ```
   HTTP/1.1 200 OK
   Server: nginx/1.29.8
   Date: ...
   Content-Type: text/html
   Content-Length: 281
   Last-Modified: ...
   Connection: keep-alive
   ETag: "..."
   Accept-Ranges: bytes
   ```
   The first line is the status (200 OK). The server is nginx 1.29.8, the body is 281 bytes of HTML, and the last headers help browsers cache the page. Module 4 takes this path apart.

   No `curl` on your laptop? Use the one in a container, sharing the web container's network:
   ```bash
   docker run --rm --network container:web curlimages/curl:8.11.1 -sI http://localhost
   ```

**Interview opener: what happens between a commit and production?** A merge into the main branch triggers a CI pipeline that builds a versioned container image, runs the tests and security scans, and pushes it to a registry; the release is then promoted through staging to production, often as a canary, while metrics, logs and alerts confirm it's healthy, or roll it back if it isn't.

## Common mistakes
- Jumping straight to Kubernetes. Without Linux, networking and containers underneath, every Kubernetes problem looks like magic. The module order is on purpose.
- Thinking DevOps is just the pipeline. The loop only works when someone owns what happens after the deploy: watching, alerting and fixing.
- Treating data like code. A service comes back from its image in seconds; a lost database doesn't. A backup that was never test-restored doesn't count.

## Clean up
```bash
docker rm -f web
```
(`storefront-dev` was started with `--rm` and is already gone.)

## Next
[M02-L01 · The Shell and the Filesystem](../../linux/m02-l01-the-shell-and-the-filesystem/)
