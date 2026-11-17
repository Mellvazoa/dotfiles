TARGET = bin/powermenu
SRC = main.swift
SWIFTC = swiftc
SWIFTFLAGS = -O -framework AppKit -framework QuartzCore

all: $(TARGET)

$(TARGET): $(SRC)
	@mkdir -p bin
	$(SWIFTC) $(SWIFTFLAGS) -o $@ $<
	@echo "Build complete: $(TARGET)"

install: $(TARGET)
	@mkdir -p ~/.local/bin
	cp $(TARGET) ~/.local/bin/powermenu
	@chmod +x ~/.local/bin/powermenu

clean:
	rm -rf bin/

.PHONY: all install clean
