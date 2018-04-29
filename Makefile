CC=gcc
CFLAGS=-Wall

all: trace

trace: trace.c
	$(CC) $(CFLAGS) trace.c -o trace

clean:
	rm -f trace trace.dump trace.out trace.maps trace.report

package:
	@tar -czf trace-`date +%y%m%d`.tar.gz *
