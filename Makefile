.PHONY:                   \
	attach build-test run \
	build                 \
	tidy                  \
	test test-author test-release

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

test:
	@nice t/run

test-author:
	@nice t/author

test-release:
	@nice t/release
