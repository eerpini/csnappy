
OPT_FLAGS = -g -O2 -DNDEBUG -fomit-frame-pointer
DBG_FLAGS = -ggdb -O0 -DDEBUG
CFLAGS := -std=gnu89 -Wall -pedantic -DHAVE_BUILTIN_CTZ
ifeq (${DEBUG},yes)
CFLAGS += $(DBG_FLAGS)
else
CFLAGS += $(OPT_FLAGS)
endif
LDFLAGS = -Wl,-O1

all: test

endianness_file: endianness.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o endianness $<
	./endianness > $@
-include endianness_file

test: cl_test check_leaks

cl_tester: cl_tester.c csnappy.h libcsnappy.so
	$(CC) $(CFLAGS) $(LDFLAGS) -D_GNU_SOURCE -o $@ $< libcsnappy.so

cl_test: cl_tester
	rm -f afifo
	mkfifo afifo
	LD_LIBRARY_PATH=. ./cl_tester -c <testdata/urls.10K | LD_LIBRARY_PATH=. ./cl_tester -d -c > afifo &
	diff -u testdata/urls.10K afifo && echo "compress-decompress restores original"
	rm -f afifo
	LD_LIBRARY_PATH=. ./cl_tester -S d && echo "decompression is safe"
	LD_LIBRARY_PATH=. ./cl_tester -S c

check_leaks: cl_tester
	LD_LIBRARY_PATH=. valgrind --leak-check=full --show-reachable=yes ./cl_tester -d -c <testdata/urls.10K.snappy >/dev/null
	LD_LIBRARY_PATH=. valgrind --leak-check=full --show-reachable=yes ./cl_tester -d -c <testdata/baddata3.snappy >/dev/null || true
	LD_LIBRARY_PATH=. valgrind --leak-check=full --show-reachable=yes ./cl_tester -c <testdata/urls.10K >/dev/null
	LD_LIBRARY_PATH=. valgrind --leak-check=full --show-reachable=yes ./cl_tester -S d

libcsnappy.so: csnappy_compress.c csnappy_decompress.c csnappy_internal.h csnappy_internal_userspace.h
	$(CC) $(CFLAGS) -fPIC -DPIC -c -o csnappy_compress.o csnappy_compress.c
	$(CC) $(CFLAGS) -fPIC -DPIC -c -o csnappy_decompress.o csnappy_decompress.c
	$(CC) $(CFLAGS) $(LDFLAGS) -shared -o $@ csnappy_compress.o csnappy_decompress.o

libcsnappy_simple: csnappy_compress.c csnappy_internal.h csnappy_internal_userspace.h
	$(CC) $(CFLAGS) -fPIC -DPIC -c -o csnappy_compress.o csnappy_compress.c
	$(CC) -std=c99 -Wall -pedantic -O2 -g -fPIC -DPIC -c -o csnappy_simple.o csnappy_simple.c
	$(CC) $(LDFLAGS) -shared -o libcsnappy.so csnappy_compress.o csnappy_simple.o

block_compressor: block_compressor.c libcsnappy.so
	$(CC) -std=gnu99 -Wall -O2 -g -o $@ $< libcsnappy.so -llzo2 -lz -lrt

test_block_compressor: block_compressor
	for testfile in \
		/usr/lib64/chromium-browser/chrome \
		/usr/lib64/qt4/libQtWebKit.so.4.7.2 \
		/usr/lib64/llvm/libLLVM-2.9.so \
		/usr/lib64/xulrunner-2.0/libxul.so \
		/usr/libexec/gcc/x86_64-pc-linux-gnu/4.6.1-pre9999/cc1 \
		/usr/lib64/libnvidia-glcore.so.270.41.03 \
		/usr/lib64/gcc/x86_64-pc-linux-gnu/4.6.1-pre9999/libgcj.so.12.0.0 \
		/usr/lib64/libwireshark.so.0.0.1 \
		/usr/share/icons/oxygen/icon-theme.cache \
	; do \
	echo compressing: $$testfile ; \
	for method in snappy lzo zlib ; do \
	LD_LIBRARY_PATH=. ./block_compressor -c $$method $$testfile itmp ;\
	LD_LIBRARY_PATH=. ./block_compressor -c $$method -d itmp otmp > /dev/null ;\
	diff -u $$testfile otmp ;\
	echo "ratio:" \
	$$(stat --printf %s itmp) \* 100 / $$(stat --printf %s $$testfile) "=" \
	$$(expr $$(stat --printf %s itmp) \* 100 / $$(stat --printf %s $$testfile)) "%" ;\
	rm -f itmp otmp ;\
	done ; \
	done ;

install: csnappy.h libcsnappy.so
	cp csnappy.h /usr/include/
	cp libcsnappy.so /usr/lib/

uninstall:
	rm -f /usr/include/csnappy.h
	rm -f /usr/lib/libcsnappy.so

clean:
	rm -f *.o *_debug libcsnappy.so cl_tester endianness endianness_file

.PHONY: .REGEN clean all
