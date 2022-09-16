.PHONY: attach build-test run

attach:
	podman-compose exec app bash

build-test:
	docker build -t pakket-test -f docker/Dockerfile-pakket-test .

run:
	podman-compose up --remove-orphans --build
