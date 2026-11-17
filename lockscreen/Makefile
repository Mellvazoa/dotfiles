BIN = bin/lockscreen

all: $(BIN)

bin:
	mkdir -p bin

bin/pam_check.o: pam_check.c pam_check.h | bin
	clang -c -O3 $< -o $@

$(BIN): main.swift bin/pam_check.o | bin
	swiftc -O -framework Cocoa -framework WebKit -framework Carbon -framework LocalAuthentication -framework OpenDirectory -lpam bin/pam_check.o main.swift -o $@

clean:
	rm -rf bin
