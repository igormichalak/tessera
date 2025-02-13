BINARY_NAME = demo
ARGS ?=

.PHONY: all
all: run

.PHONY: run
run:
	odin run ./src/ -vet -out:$(BINARY_NAME) -- $(ARGS)
