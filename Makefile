############################
#       Dev aliases        #
############################

DOCKER_COMPOSE ?= docker compose

.PHONY: up
up:
	$(DOCKER_COMPOSE) up -d
	sleep 3

.PHONY: down
down:
	$(DOCKER_COMPOSE) down -v --remove-orphans