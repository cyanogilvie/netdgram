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

namespace path [concat [namespace path] {
	::tcl::mathop
}]

package require netdgram 0.6.1.1
package require netdgram::tcp 0.6.1.1
package require cflib

cflib::config create cfg $argv {
	variable mode		"rr"
	variable queuetop	1000
	variable queuebot	500
}

set outstanding	0
set tx			0
set rx			0
set latency_acc	0

set con	[netdgram::connect_uri "tcp://:4300"]
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

set queuetop	[cfg get queuetop]
set queuebot	[expr {min([cfg get queuebot], [cfg get queuetop])}]
oo::objdefine $queue method receive {msg} {
	global queuebot
	#puts "got msg ($msg)"
	set now	[clock microseconds]
	global rx outstanding latency_acc
	incr rx
	if {[incr outstanding -1] < $queuebot} {
		feeder
	}
	incr latency_acc	[expr {$now - $msg}]
}

$con activate

coroutine feeder apply {
	{} {
		global outstanding queue tx queuetop

		while {1} {
			while {$outstanding < $queuetop} {
				incr tx
				incr outstanding
				$queue enqueue [clock microseconds]
				incr c
			}
			yield
		}
	}
}

coroutine poll apply {
	{} {
		global outstanding tx rx latency_acc

		try {
			set stamp	[clock microseconds]
			after 1000 [list [info coroutine]]
			yield
			while {1} {
				after 1000 [list [info coroutine]]
				set now			[clock microseconds]
				set delta_sec	[expr {($now - $stamp) / 1000000.0}]
				set stamp		$now

				if {$rx == 0} {
					set latency_ms	0.0
				} else {
					set latency_ms	[expr {($latency_acc / 1000.0) / $rx}]
				}

				puts [format "%s: %.4f %s: %.4f, %s: %.4f %s: %d" \
						"tx/s"				[/ $tx $delta_sec] \
						"rx/s"				[/ $rx $delta_sec] \
						"avg latency ms"	$latency_ms \
						"outstanding"		$outstanding]

				set tx			0
				set rx			0
				set latency_acc	0
				yield
			}
		} on error {errmsg options} {
			puts "Unhandled error in poll: [dict get $options -errorinfo]"
		}
	}
}

vwait ::forever
