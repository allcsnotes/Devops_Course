# ssh-lab-db: db-01 = the same server image plus PostgreSQL 16 (Ubuntu's package, listens on localhost only by default).
# Build the base image first (up.sh does this for you).
FROM ssh-lab-sshd:1
RUN apt-get update && apt-get install -y --no-install-recommends postgresql \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
