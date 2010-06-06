# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

tcl::tm::path add [file normalize [file join [file dirname [info script]] .. tm tcl]]

package require netdgram 0.5.4
package require cflib

cflib::config create cfg $argv {
	variable uri	"tcp://"
}

package require netdgram::tcp
oo::define netdgram::connectionmethod::tcp method default_port {} {return 4300}

set listener	[netdgram::listen_uri [cfg get uri]]

oo::objdefine $listener method accept {con args} {
	puts "Accept: ($con)"

	set queue	[netdgram::queue new]
	oo::objdefine $queue method assign {msg} {
		# Returns the target queue name
		set choices	{foo bar baz}
		set target	[lindex $choices [expr {int(rand() * [llength $choices])}]]
		puts "Queueing to $target"
		return $target
	}

	oo::objdefine $queue method pick {queues} {
		set source	[lindex $queues [expr {int(rand() * [llength $queues])}]]
		puts "randomly picked $source from ($queues)"
		return $source
	}

	$queue attach $con
	oo::objdefine $queue method receive {msg} {
		puts "Got msg from ([self]): ($msg)"
		my enqueue "echo: ($msg)"
	}
}

puts "Created listener on port 1234: ($listener)"
vwait ::forever
