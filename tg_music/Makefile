TARGET = bin/tg_music
SRC = main.swift
SWIFTC = swiftc
SWIFTFLAGS = -O -framework AppKit -framework AVFoundation -framework MediaPlayer -framework QuartzCore

all: $(TARGET)

$(TARGET): $(SRC)
	@mkdir -p bin
	$(SWIFTC) $(SWIFTFLAGS) -o $@ $<
	@echo "Build complete: $(TARGET)"

install: $(TARGET)
	@mkdir -p ~/.local/bin
	cp $(TARGET) ~/.local/bin/tg_music
	@chmod +x ~/.local/bin/tg_music

clean:
	rm -rf bin/

.PHONY: all install clean
