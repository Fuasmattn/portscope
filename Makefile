# Build, install as a login item via launchd, and remove again. No code signing needed.
#
#   make release    build .build/release/Portscope
#   make install    copy the binary to ~/.local/bin and start it at login through launchd
#   make install-binary  same, from a prebuilt ./Portscope (release tarball, no toolchain needed)
#   make restart    reload the launchd job after a rebuild
#   make uninstall  stop it and remove the binary and the LaunchAgent

LABEL      := dev.martinprinz.portscope
BIN_DIR    := $(HOME)/.local/bin
BIN        := $(BIN_DIR)/Portscope
AGENT_DIR  := $(HOME)/Library/LaunchAgents
PLIST      := $(AGENT_DIR)/$(LABEL).plist
DOMAIN     := gui/$(shell id -u)
LOG_DIR    := $(HOME)/Library/Logs/Portscope

.PHONY: release install install-binary restart uninstall status

release:
	swift build -c release
	@echo "Built .build/release/Portscope"

install: release
	$(MAKE) install-binary SOURCE=.build/release/Portscope

SOURCE ?= ./Portscope

install-binary:
	@test -x "$(SOURCE)" || { echo "No binary at $(SOURCE). Run make install (needs the Swift toolchain) or unpack the release tarball here."; exit 1; }
	mkdir -p "$(BIN_DIR)" "$(AGENT_DIR)" "$(LOG_DIR)"
	-launchctl bootout $(DOMAIN)/$(LABEL) 2>/dev/null
	-pkill -x Portscope 2>/dev/null
	cp "$(SOURCE)" "$(BIN)"
	-xattr -d com.apple.quarantine "$(BIN)" 2>/dev/null
	@printf '%s\n' \
	  '<?xml version="1.0" encoding="UTF-8"?>' \
	  '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
	  '<plist version="1.0">' \
	  '<dict>' \
	  '  <key>Label</key><string>$(LABEL)</string>' \
	  '  <key>ProgramArguments</key><array><string>$(BIN)</string></array>' \
	  '  <key>RunAtLoad</key><true/>' \
	  '  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>' \
	  '  <key>ProcessType</key><string>Interactive</string>' \
	  '  <key>LimitLoadToSessionType</key><string>Aqua</string>' \
	  '  <key>StandardOutPath</key><string>$(LOG_DIR)/stdout.log</string>' \
	  '  <key>StandardErrorPath</key><string>$(LOG_DIR)/stderr.log</string>' \
	  '</dict>' \
	  '</plist>' > "$(PLIST)"
	launchctl bootstrap $(DOMAIN) "$(PLIST)"
	@echo "Installed. Portscope starts now and at every login."

restart: install

uninstall:
	-launchctl bootout $(DOMAIN)/$(LABEL) 2>/dev/null
	-pkill -x Portscope 2>/dev/null
	rm -f "$(PLIST)" "$(BIN)"
	@echo "Removed the LaunchAgent and $(BIN)."

status:
	@launchctl print $(DOMAIN)/$(LABEL) 2>/dev/null | grep -E "state|pid|path" || echo "not loaded"
