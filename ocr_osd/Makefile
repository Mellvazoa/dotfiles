TARGET = bin/ocr_osd
SRC = main.swift
SWIFTC = swiftc
SWIFTFLAGS = -O -framework AppKit -framework Vision -framework QuartzCore

all: $(TARGET)

$(TARGET): $(SRC)
	@mkdir -p bin
	$(SWIFTC) $(SWIFTFLAGS) -o $@ $<
	@echo "Build complete: $(TARGET)"

install: $(TARGET)
	@mkdir -p ~/.local/bin
	cp $(TARGET) ~/.local/bin/ocr_osd
	@chmod +x ~/.local/bin/ocr_osd

clean:
	rm -rf bin/

.PHONY: all install clean
