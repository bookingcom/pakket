### How to test stuff
You must have docker & docker-compose installed

	docker-compose build && docker-compose run  bash

This will get you inside a docker container, where you can test pakket manually.

We also have a sample test file that you can use:

	pakket install --input-file t/test-pakket.list

### Limitations:

* `pakket --version` will not work
