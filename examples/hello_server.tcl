# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

package require netdgram

set listener	[netdgram::listen_uri "tcp://:4300"]
oo::objdefine $listener method accept {con args} {
	oo::objdefine $con method received {msg} {
		puts "Got message: ($msg)"
		my send "echo $msg"
	}

	$con activate
}

vwait ::forever
