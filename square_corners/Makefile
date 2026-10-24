TARGET = libsquare_corners.dylib
SRC = square_corners.m
CC = clang
CFLAGS = -dynamiclib -framework Foundation -framework AppKit -arch arm64 -arch arm64e -O2

all: $(TARGET)

$(TARGET): $(SRC)
	$(CC) $(CFLAGS) -o $@ $<

install: $(TARGET)
	sudo cp $(TARGET) /private/var/ammonia/core/tweaks/

clean:
	rm -f $(TARGET)

.PHONY: all install clean
