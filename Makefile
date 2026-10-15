NAME    := mugur
ODIN    ?= odin
VERSION := $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)

VET     := -vet -strict-style
LINT    := $(VET) -vet-cast -vet-tabs -vet-semicolon -vet-using-param \
           -vet-shadowing -disallow-do -warnings-as-errors
DEFINES := -define:VERSION=$(VERSION)

.PHONY: all build release run test lint clean version

all: lint test build

build:
	$(ODIN) build . $(VET) -debug -out:$(NAME) $(DEFINES)

release:
	$(ODIN) build . $(VET) -o:speed -out:$(NAME) $(DEFINES)

run: build
	./$(NAME)

test:
	$(ODIN) test . -all-packages $(VET)

lint:
	$(ODIN) check . $(LINT)

clean:
	rm -f $(NAME) $(NAME).exe *.pdb

version:
	@echo $(VERSION)
