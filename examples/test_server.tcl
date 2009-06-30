#!/usr/bin/env cfkit8.6

tcl::tm::path add [file normalize [file join [file dirname [info script]] .. tm tcl]]
tcl::tm::path add [file normalize [file join ~ .tbuild repo tm tcl]]

lappend auto_path [file normalize [file join ~ .tbuild repo pkg linux-glibc2.3-ix86]]

#package require netdgram::tcp
package require netdgram

namespace path ::oo

#netdgram::ConnectionMethod::TCP_coroutine create cm_tcp_coroutine

#set listener	[cm_tcp listen 1234]
#set listener	[netdgram::listen_uri "tcp://*:1234"]
set listener	[netdgram::listen_uri "uds:///tmp/example.socket"]
#set listener	[netdgram::listen_uri "tcp://127.0.0.1:1234"]

oo::objdefine $listener forward accept apply {
	{con args} {
		puts "Accept: ($con)"

		set queue	[netdgram::queue new]
		$queue attach $con
		objdefine $queue method receive {msg} {
			puts "Got msg from ([self]): ($msg)"
			my enqueue "echo: ($msg)"
		}

		#$con configure -received [list apply {
		#	{con msg} {
		#		puts "Got msg from ($con): ($msg)"
		#		$con send "echo: ($msg)"
		#	}
		#} $con]
	}
}

puts "Created listener on port 1234: ($listener)"
coroutine coro_main vwait ::forever
