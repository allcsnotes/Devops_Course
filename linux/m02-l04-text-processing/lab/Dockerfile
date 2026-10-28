# The "web-01" server from the video: Ubuntu 24.04 with sample nginx and API logs.
# Build and start it with ./up.sh, remove it with ./down.sh.
FROM ubuntu:24.04
COPY gen_logs.py setup.sh /root/
RUN bash /root/setup.sh && rm /root/setup.sh /root/gen_logs.py
# keep the container running so you can open shells in it
CMD ["sleep", "infinity"]
