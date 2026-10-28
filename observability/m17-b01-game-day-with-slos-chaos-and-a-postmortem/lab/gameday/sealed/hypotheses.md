# SEALED: game master only, until the review

| # | fault                                   | hypothesis (written before the game day)                                                  |
|---|-----------------------------------------|---------------------------------------------------------------------------------------------|
| 1 | a bad release, 1.1 (staged bug)         | the page fires within 3 min, rollback within 6 min, under 5 % of the course-list budget      |
| 2 | a migration locks the courses table     | the course list keeps both SLOs (stale copy), no page, a ticket within 3 min, lock ended within 10 |
| 3 | Course Copilot hangs (paused process)   | only Copilot answers fail, the course list keeps both SLOs, the Copilot page within 3 min    |
