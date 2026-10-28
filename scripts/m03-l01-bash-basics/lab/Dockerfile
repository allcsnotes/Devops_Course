# The lab server for M03-L01: "web-01", an Ubuntu 24.04 box with nginx, a sample access log and the user asha.
# Build it from the lesson folder (the folder that holds lab/ and scripts/):
#   docker build -t bash-lab:m03-l01 -f lab/Dockerfile .
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
# nginx: the web server the checks look at; procps: pgrep; sudo: so asha can stop/start nginx; python3: only runs gen_logs.py
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

# The lesson's scripts: a full copy in ~/lesson, and the practice files right in asha's home.
# report.sh is rebuilt with Windows (CRLF) line endings for the pitfall demo, whatever git did to it on checkout.
# ~/reports holds three small files, one with a space in its name (the quoting demo).
COPY scripts/ /home/asha/lesson/
RUN find /home/asha/lesson -type f ! -name report.sh -exec sed -i 's/\r$//' {} + \
 && cd /home/asha \
 && install -m 644 lesson/hello.sh hello.sh \
 && for f in conditions.sh answer.sh login.sh args.sh; do install -m 755 "lesson/$f" "$f"; done \
 && install -m 644 lesson/servers.txt servers.txt \
 && sed 's/\r$//; s/$/\r/' lesson/report.sh > report.sh && chmod 755 report.sh \
 && mkdir reports \
 && printf 'used 3%%\nused 15%%\nok\n' > reports/disk.txt \
 && printf 'running\n11 processes\n' > reports/nginx.txt \
 && printf '73 errors\nall POST /api/checkout\nfrom 21:40\nrelease v2.14.0\ntimeout 300 ms\n' > 'reports/error report.txt' \
 && chown -R asha:asha /home/asha

COPY lab/start.sh /usr/local/bin/start.sh
RUN sed -i 's/\r$//' /usr/local/bin/start.sh && chmod 755 /usr/local/bin/start.sh
CMD ["/usr/local/bin/start.sh"]
