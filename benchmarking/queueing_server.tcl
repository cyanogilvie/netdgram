#!/usr/bin/env tclsh8.6
# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

if {![info exists ::tcl::basekit]} {
	package require platform

	foreach platform [platform::patterns [platform::identify]] {
		set tm_path		[file join $env(HOME) .tbuild repo tm $platform]
		set pkg_path	[file join $env(HOME) .tbuild repo pkg $platform]
		if {[file exists $tm_path]} {
			tcl::tm::path add $tm_path
		}
		if {[file exists $pkg_path]} {
			lappend auto_path $pkg_path
		}
	}
}


package require netdgram 0.6.1.1
package require netdgram::tcp 0.6.1.1
package require cflib

cflib::config create cfg $argv {
	variable mode	"rr"
}

set listener	[netdgram::listen_uri "tcp://:4300"]
oo::objdefine $listener method accept {con args} {
	set queue	[netdgram::queue new]
	$queue attach $con

	switch -- [cfg get mode] {
		rr {
			# default
		}

		fifo {
			oo::objdefine $queue method assign {rawmsg} {
				return "_fifo"
			}
			oo::objdefine $queue method pick {rawmsg} {
				return "_fifo"
			}
		}

		default {
			error "Queue mode \"[cfg get mode]\" not implemented"
		}
	}

	oo::objdefine $queue method receive {msg} {
		#puts "Got message: ($msg)"
		my enqueue $msg
	}
}

vwait ::forever
