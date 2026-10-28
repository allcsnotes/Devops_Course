# Threat model: course search (Course Copilot 1.6.x)

Date: 2026-10-21 · Who: Asha, Priya, Rahul · Time: 45 minutes

## 1. What are we working on?
- Lukas (browser) -> storefront -> Course Copilot GET /courses/search?q=...
- Copilot reads catalog.yaml into SQLite and runs one query per search
- Trust boundary 1: the internet -> our edge (anyone can send any q)
- Trust boundary 2: CI -> the repository (keys, the pipeline)

## 2. What can go wrong? (STRIDE)
| | Threat | Rating |
|---|---|---|
| S | someone signs in as Meera with a stolen password | high |
| T | a request changes the price it pays | medium |
| R | "I never deleted that course" and no log proves it | low |
| I | q rewrites the SQL and reads other tables | high |
| D | a flood of searches takes the API down | medium |
| E | a student calls the upload API for instructors | high |

## 3. What are we going to do about it?
- I: parameterised queries + Semgrep rule in CI (done 2026-10-21, Priya)
- S: MFA for instructors (owner Rahul, due 2026-11-15)
- E: server-side role check on every upload call (owner Priya, due 2026-11-07)
- D: rate limit per IP at the edge (owner Asha, due 2026-11-30)
- T: price always read on the server, never from the request (already true)
- R: audit log with user id for every catalog change (accept for now, review 2027-01)

## 4. Did we do a good job?
- Review at the next design change, or by 2027-01-31
