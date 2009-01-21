VER=0.2

BASESCRIPTS = \
			  connectionmethod.tcl \
			  queue.tcl \
			  uri.tcl

all: tm

tm: *.tcl connectionmethods/*.tcl
	-rm -rf tm
	install -d tm
	install -d tm/netdgram
	cat $(BASESCRIPTS) > tm/netdgram-$(VER).tm
	./tools/make_tm.tcl 'connectionmethods/*.tcl' tm/netdgram $(VER)

install: all
	#./install
	rsync -avP tm/* /tcl8.6/lib/tcl8/8.6

clean:
	-rm -rf tm
