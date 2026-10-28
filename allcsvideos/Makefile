# allcsvideos platform: the commands everyone uses. make help lists them.
SHELL := /bin/bash
export GIT_SHA := $(shell git rev-parse HEAD 2>/dev/null)
export GIT_URL := $(shell git remote get-url origin 2>/dev/null)
REGISTRY_NAME := do-m07b01-registry

.PHONY: help up down logs ps scan release registry nuke

help:                            ## list the targets
	@grep -E '^[a-z]+:.*## ' $(MAKEFILE_LIST) | sed 's/:.*## /\t/'

up: .env secrets/db_password.txt ## build what changed, start the stack, wait until healthy
	docker compose up -d --build --wait

.env:
	cp .env.example .env

secrets/db_password.txt:
	scripts/dev-secrets.sh

down:                            ## stop and remove containers of every profile (data stays)
	docker compose --profile "*" down

ps:                              ## status and health of every service
	docker compose ps -a

logs:                            ## follow the logs: make logs s=catalog
	docker compose logs -f --tail 20 $(s)

scan:                            ## Trivy gate on the local images
	scripts/scan.sh $(addprefix do-m07b01/,$(addsuffix :dev,storefront gateway catalog copilot))

registry:                        ## local registry on 127.0.0.1:5001 (stands in for GHCR or ECR)
	@docker start $(REGISTRY_NAME) >/dev/null 2>&1 || { docker volume create --label course=devops do-m07b01-registry-data >/dev/null; \
	  docker run -d --name $(REGISTRY_NAME) \
	  --label course=devops -p 127.0.0.1:5001:5000 -v do-m07b01-registry-data:/var/lib/registry registry:3.1.2 >/dev/null; } && echo "registry: 127.0.0.1:5001"

release: registry                ## build, scan, SBOM, tag and push: make release VERSION=1.0.0
	scripts/release.sh $(VERSION)

nuke:                            ## DANGER: also delete the database volume and local images
	docker compose --profile "*" down -v --rmi local
