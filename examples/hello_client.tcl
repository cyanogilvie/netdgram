# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

package require netdgram

set con	[netdgram::connect_uri "tcp://:4300"]
oo::objdefine $con method received {msg} {
	puts "Got reply: ($msg)"
	exit 0
}

$con activate

$con send "Test message"

vwait ::forever
