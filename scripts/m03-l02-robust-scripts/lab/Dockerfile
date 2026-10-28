# The lab server for M03-L02: the same "web-01" as M03-L01 (Ubuntu 24.04, nginx, the sample access log, the user asha),
# plus this lesson's scripts and a sandbox folder for the cleanup demo.
# Build it from the lesson folder (the folder that holds lab/ and scripts/):
#   docker build -t bash-lab:m03-l02 -f lab/Dockerfile .
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
# nginx: the web server the checks look at; procps: pgrep; sudo: so asha can stop/start nginx; python3: only runs gen_logs.py
# (curl is deliberately not installed: the `command -v curl` demo expects it to be missing)
RUN apt-get update -qq \
 && apt-get install -y -qq nginx procps sudo python3 >/dev/null \
 && rm -rf /var/lib/apt/lists/*

# asha is in the adm group, so she may read the logs in /var/log/nginx
RUN useradd -m -s /bin/bash -G adm asha \
 && echo 'asha ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/asha && chmod 440 /etc/sudoers.d/asha

# The GENERATED SAMPLE access log from M02-L04 (not real traffic): 5928 lines, 73 of them 5xx errors.
COPY lab/gen_logs.py /root/gen_logs.py
RUN mkdir -p /root/gen && cd /root/gen && python3 /root/gen_logs.py . \
 && install -o www-data -g adm -m 640 access.log /var/log/nginx/access.log \
 && touch -d '2026-10-19 21:51:59' /var/log/nginx/access.log

# The lesson's scripts: a full copy in ~/lesson, and the practice scripts right in asha's home.
# ~/cleanup.sh starts as version 1 (the broken one from the opening story).
# ~/sandbox/app is a STAGED dummy app folder with empty placeholder files, never a real site.
COPY scripts/ /home/asha/lesson/
RUN find /home/asha/lesson -type f -exec sed -i 's/\r$//' {} + \
 && cd /home/asha \
 && install -m 755 lesson/cleanup.v1.sh cleanup.sh \
 && for f in funcs.sh params.sh collect.sh opts.sh exitreturn.sh gap.sh traps.sh counter.sh masked.sh noisy.sh int.sh typo.sh; do \
      install -m 755 "lesson/$f" "$f"; \
    done \
 && mkdir -p sandbox/app sandbox/releases \
 && touch sandbox/app/app.env sandbox/app/index.html sandbox/app/server.jar \
 && chown -R asha:asha /home/asha

COPY lab/start.sh /usr/local/bin/start.sh
RUN sed -i 's/\r$//' /usr/local/bin/start.sh && chmod 755 /usr/local/bin/start.sh
CMD ["/usr/local/bin/start.sh"]
