TARGET = bin/wallpaper_gallery
SRC = main.swift
SWIFTC = swiftc
SWIFTFLAGS = -O -framework AppKit -framework WebKit

all: $(TARGET)

$(TARGET): $(SRC)
	@mkdir -p bin
	$(SWIFTC) $(SWIFTFLAGS) -o $@ $<
	@cp gallery.html bin/gallery.html
	@echo "Build complete: $(TARGET)"

install: $(TARGET)
	@mkdir -p ~/bin ~/.local/bin ~/.config/yabai/bin 2>/dev/null || true
	cp $(TARGET) ~/.local/bin/wallpaper_gallery 2>/dev/null || cp $(TARGET) ~/bin/wallpaper_gallery
	cp $(TARGET) ~/.config/yabai/bin/wallpaper_gallery 2>/dev/null || true
	cp gallery.html ~/.local/bin/gallery.html 2>/dev/null || true
	cp gallery.html ~/bin/gallery.html 2>/dev/null || true
	cp gallery.html ~/.config/yabai/bin/gallery.html 2>/dev/null || true

clean:
	rm -rf bin/

.PHONY: all install clean
