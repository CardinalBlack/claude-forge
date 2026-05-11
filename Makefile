.PHONY: install test update ci

install:
	./bootstrap.sh

test:
	./tests/bats/bin/bats tests/

update:
	git pull --rebase
	./bootstrap.sh

# Used by CI.
ci: test
