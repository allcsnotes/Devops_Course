# token-service: LAB STAND-IN for GitHub's OIDC token service (token.actions.githubusercontent.com).
# Gitea 28.1.0 does not issue OIDC ID tokens to jobs (docs.gitea.com/usage/actions/comparison: "id-token ... not
# supported"), so this tiny issuer plays that role for the M08-L05 lab only. Never use it outside the lab.
FROM python:3.13.16-slim
RUN pip install --no-cache-dir pyjwt==2.10.1 cryptography==45.0.7
COPY issuer.py /app/issuer.py
USER nobody
CMD ["python", "-u", "/app/issuer.py"]
