# Game day report: allcsvideos staging, 21 October 2026

| # | sealed fault            | hypothesis held? | detected       | mitigated | course-list budget | Copilot budget |
|---|-------------------------|------------------|----------------|-----------|--------------------|----------------|
| 1 | bad release 1.1         | yes              | page +1:39     | +3:18     | 0.59 %             | 0.01 %         |
| 2 | migration lock          | no               | ticket +1:13   | +2:25     | 1.71 %             | 0.16 %         |
| 3 | Copilot hangs           | no               | page +1:31     | +3:04     | 5.38 %             | 1.44 %         |
| 2 | re-run on 1.2           | yes              | ticket +1:13   | +2:25     | 0.00 %             | 0.00 %         |
| 3 | re-run on 1.2           | yes              | page +2:06     | +2:51     | 0.00 %             | 0.72 %         |

Whole game day: 7.70 % of the course-list budget, 2.32 % of the Copilot budget (cap: 10 % each). No abort.
Postmortem: postmortem/2026-10-21-gameday-slow-dependencies.md
