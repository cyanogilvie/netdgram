#!/usr/bin/env cfkit8.6

tcl::tm::path add [file normalize [file join [file dirname [info script]] .. tm tcl]]
tcl::tm::path add [file normalize [file join ~ .tbuild repo tm tcl]]

lappend auto_path [file normalize [file join ~ .tbuild repo pkg linux-glibc2.3-ix86]]

#package require netdgram::tcp
package require netdgram

#netdgram::ConnectionMethod::TCP_coroutine create cm_tcp_coroutine

#set con	[cm_tcp connect localhost 1234]
#set con		[netdgram::connect_uri "tcp://localhost:1234"]
set con		[netdgram::connect_uri "uds:///tmp/example.socket"]
netdgram::queue create queue
queue attach $con

oo::objdefine queue method assign {msg} {
	# Returns the target queue name
	set choices	{foo bar baz}
	set target	[lindex $choices [expr {int(rand() * [llength $choices])}]]
	puts "Queueing to $target"
	return $target
}

oo::objdefine queue method pick {queues} {
	set source	[lindex $queues [expr {int(rand() * [llength $queues])}]]
	puts "randomly picked $source from ($queues)"
	return $source
}

#oo::objdefine queue method receive {msg} {
#	puts "Got msg: ($msg)"
#	exit
#}
proc myreceive {foo msg} {
	puts "myGot msg: ($foo) ($msg)"
	if {[incr ::got] == 5} {
		exit
	}
}
oo::objdefine queue forward receive myreceive thisisfoo

$con activate
queue enqueue {hello, world1}
queue enqueue {hello, world2}
queue enqueue {hello, world3}
queue enqueue {hello, world4}
queue enqueue {hello, world5}

#$con configure -received [list apply {
#	{msg} {
#		puts "Got msg: ($msg)"
#		exit
#	}
#}]
#$con activate
#$con send {hello, world}

coroutine coro_main vwait ::forever

