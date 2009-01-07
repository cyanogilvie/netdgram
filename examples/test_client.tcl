#!/usr/bin/env tclsh8.6

package require Tcl 8.6
package require TclOO

tcl::tm::path add [file normalize [file join [file dirname [info script]] .. tm]]
#package require netdgram::tcp_coroutine
package require netdgram

#netdgram::ConnectionMethod::TCP_coroutine create cm_tcp_coroutine

#set con	[cm_tcp_coroutine connect localhost 1234]
set con		[netdgram::connect_uri "tcp_coroutine://localhost:1234"]
#set con		[netdgram::connect_uri "uds:///tmp/example.socket"]
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
	exit
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

vwait ::forever

