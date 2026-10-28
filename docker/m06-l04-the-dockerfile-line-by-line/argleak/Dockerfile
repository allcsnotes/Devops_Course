# syntax=docker/dockerfile:1
FROM python:3.12.15-slim
# STAGED on purpose: a FAKE token passed as a build argument
ARG PIP_INDEX_TOKEN
RUN test -n "$PIP_INDEX_TOKEN" && echo "private package index configured"
