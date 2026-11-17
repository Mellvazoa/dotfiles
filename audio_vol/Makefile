TARGET = bin/audio_vol
SRC = main.swift
SWIFTC = swiftc
SWIFTFLAGS = -O -framework Cocoa -framework CoreAudio -framework AudioToolbox -framework QuartzCore

all: $(TARGET)

$(TARGET): $(SRC)
	@mkdir -p bin
	$(SWIFTC) $(SWIFTFLAGS) -o $@ $<
	@echo "Build complete: $(TARGET)"

install: $(TARGET)
	@mkdir -p ~/.local/bin
	cp $(TARGET) ~/.local/bin/audio_vol
	@chmod +x ~/.local/bin/audio_vol

clean:
	rm -rf bin/

.PHONY: all install clean
