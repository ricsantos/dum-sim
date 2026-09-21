CONFIG ?= release
PREFIX ?= $(HOME)/.local

.PHONY: all cli app install install-cli install-app clean

all: app

cli:
	swift build -c $(CONFIG) --product dum-sim

app:
	Scripts/bundle.sh $(CONFIG)

install: install-cli install-app

install-cli: cli
	mkdir -p $(PREFIX)/bin
	cp "$$(swift build -c $(CONFIG) --show-bin-path)/dum-sim" $(PREFIX)/bin/dum-sim
	@echo "Installed $(PREFIX)/bin/dum-sim"

install-app: app
	rm -rf /Applications/DumSim.app
	cp -R build/DumSim.app /Applications/DumSim.app
	@echo "Installed /Applications/DumSim.app"

clean:
	rm -rf .build build
