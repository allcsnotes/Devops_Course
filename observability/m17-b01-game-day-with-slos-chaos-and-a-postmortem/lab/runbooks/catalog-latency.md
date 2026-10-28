# Runbook: course list slow (ErrorBudgetBurn, slo=catalog-latency)

More than 14.4 % of course lists take longer than 250 ms. Same first steps as catalog-availability.md:
recent deploy -> roll back; workers busy -> what are they waiting on; database locks -> pg_stat_activity.
