# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

package require cflib
package require netdgram
package require netdgram::tcp
oo::define netdgram::connectionmethod::tcp method default_port {} {return 4300}

cflib::config create cfg $argv {
	variable uri	"tcp://"
}

set con	[netdgram::connect_uri [cfg get uri]]

oo::objdefine $con method received {msg} {
	puts "Got reply: ($msg)"
	exit 0
}
oo::objdefine $con method closed {} {
	puts "Connection closed"
	exit 1
}

$con activate
puts "Connected"

#$con send "Test message"

vwait ::forever
