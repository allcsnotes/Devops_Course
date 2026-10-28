# SEALED (game master only). Scenario 3: Course Copilot hangs (a frozen process: connections open, no answers)
HYPOTHESIS="Course Copilot hangs: only Copilot answers fail, the course list keeps both SLOs, and the Copilot page fires within 3 minutes"
inject()   { docker compose -f ../compose.yaml pause copilot; }
rollback() { docker compose -f ../compose.yaml unpause copilot; }
