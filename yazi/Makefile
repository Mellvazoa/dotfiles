TARGET = bin/filecopy
SRC = filecopy.swift
SWIFTC = swiftc
SWIFTFLAGS = -O -framework AppKit

all: $(TARGET)

$(TARGET): $(SRC)
	@mkdir -p bin
	$(SWIFTC) $(SWIFTFLAGS) -o $@ $<
	@echo "Build complete: $(TARGET)"

install: $(TARGET)
	@mkdir -p ~/.local/bin
	cp $(TARGET) ~/.local/bin/filecopy
	@chmod +x ~/.local/bin/filecopy

clean:
	rm -rf bin/

.PHONY: all install clean
