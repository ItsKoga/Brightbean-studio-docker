UPSTREAM_REPO ?= https://github.com/brightbeanxyz/brightbean-studio.git
UPSTREAM_REF  ?= main
IMAGE         ?= brightbean-studio
PLATFORM      ?=
DATA_DIR      ?= $(CURDIR)/.data

PLATFORM_FLAG := $(if $(PLATFORM),--platform $(PLATFORM),)

.PHONY: upstream base build run stop logs clean

upstream:
	@if [ -d upstream/.git ]; then \
		git -C upstream fetch --depth 1 origin $(UPSTREAM_REF) && git -C upstream checkout -q FETCH_HEAD; \
	else \
		git clone --depth 1 --branch $(UPSTREAM_REF) $(UPSTREAM_REPO) upstream; \
	fi

base: upstream
	docker build $(PLATFORM_FLAG) -t brightbean-studio-base:local upstream

build: base
	docker build $(PLATFORM_FLAG) \
		--build-arg BASE_IMAGE=brightbean-studio-base:local \
		--build-arg UPSTREAM_SHA=$$(git -C upstream rev-parse HEAD) \
		-t $(IMAGE):local .

run:
	mkdir -p $(DATA_DIR)/config $(DATA_DIR)/media
	docker run -d --name brightbean-studio -p 8000:8000 \
		-e PUID=$$(id -u) -e PGID=$$(id -g) \
		-v $(DATA_DIR)/config:/config -v $(DATA_DIR)/media:/app/media \
		$(IMAGE):local

stop:
	-docker rm -f brightbean-studio

logs:
	docker logs -f brightbean-studio

clean: stop
	rm -rf upstream $(DATA_DIR)
