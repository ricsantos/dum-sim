CONFIG ?= release
PREFIX ?= $(HOME)/.local

.PHONY: all cli app icon readme-icon install install-cli install-app clean

all: app

cli:
	swift build -c $(CONFIG) --product dum-sim

app:
	Scripts/bundle.sh $(CONFIG)

icon:
	swift build -c $(CONFIG) --product make-icon
	mkdir -p build
	"$$(swift build -c $(CONFIG) --show-bin-path)/make-icon" build --source Resources/AppIcon.png --png
	@echo "Wrote build/AppIcon.icns and build/AppIcon-1024.png"

# GitHub strips CSS from a README, so the rounded corners must be in the file.
readme-icon: icon
	cp build/AppIcon-1024.png Resources/icon.png
	sips -Z 512 Resources/icon.png > /dev/null
	@echo "Wrote Resources/icon.png"

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
