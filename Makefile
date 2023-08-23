.PHONY:                   \
	attach build-test run \
	build                 \
	tidy                  \
	author-test release-test unit-test

attach:
	podman-compose exec app bash

build-test:
	docker build -t pakket-test -f docker/Dockerfile-pakket-test .

run:
	podman-compose up --remove-orphans --build

build:
	@dzil build

tidy:
	@t/tidy

author-test:
	@nice t/author

release-test:
	@nice t/release

unit-test:
	@nice t/run
