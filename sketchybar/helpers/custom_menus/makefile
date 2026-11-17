bin/custom_menus: custom_menus.c | bin
	clang -std=c99 -O3 -F/System/Library/PrivateFrameworks/ -framework Carbon -framework SkyLight $< -o $@

bin:
	mkdir -p bin

clean:
	rm -rf bin
