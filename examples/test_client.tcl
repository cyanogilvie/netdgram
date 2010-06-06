# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

tcl::tm::path add [file normalize [file join [file dirname [info script]] .. tm tcl]]

package require netdgram 0.5.4
package require cflib

cflib::config create cfg $argv {
	variable uri	"tcp://"
}

package require netdgram::tcp
oo::define netdgram::connectionmethod::tcp method default_port {} {return 4300}

set con		[netdgram::connect_uri [cfg get uri]]
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

oo::objdefine queue method receive {msg} {
	namespace path {::tcl::mathop}
	puts "Got msg: ($msg)"
	if {[incr ::got] == 5} {
		puts [format "Run time: %.3f milliseconds" [/ [- [clock microseconds] $::before] 1000.0]]
		exit
	}
}

set before	[clock microseconds]
$con activate
queue enqueue {hello, world1}
queue enqueue {hello, world2}
queue enqueue {hello, world3}
queue enqueue {hello, world4}
queue enqueue {hello, world5}

vwait ::forever

