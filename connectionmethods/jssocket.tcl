# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

namespace eval netdgram {
	package require netdgram

	class create connectionmethod::jssocket { #<<<
		superclass netdgram::connectionmethod
		mixin netdgram::debug

		constructor {} { #<<<
			if {[self next] ne {}} {next}
			if {![package vsatisfies [info patchlevel] 8.6-]} {
				error "Coroutines require Tcl 8.6"
			}
		}

		#>>>

		method listen {uri_obj} { # <<<
			set parts	[$uri_obj as_dict]
			set params	[split [dict get $parts authority] :]
			if {[llength $params] != 2} {
				error "Invalid connection parameters, expecting [self class]://ip:port specify ip as \"*\" to bind to all interfaces"
			}
			lassign $params host port
			if {![info exists port] || $port eq ""} {
				set port	5301
			}
			set flags	[dict get $parts query]
			set listen [netdgram::listener::jssocket new $host $port $flags]
			oo::objdefine $listen forward human_id apply {
				{human_id} {
					set human_id
				}
			} "uri([$uri_obj encoded]) pid([pid])"
			return $listen
		}

		#>>>
		method connect {uri_obj} {	;# <<<
			try {
				set parts	[$uri_obj as_dict]
				set params	[split [dict get $parts authority] :]
				if {[llength $params] != 2} {
					error "Invalid connection parameters, expecting [self class]://ip:port"
				}
				lassign $params host port
				set flags	[dict get $parts query]
				set socket	[socket $host $port]

				set con	[netdgram::connection::jssocket new $socket $host $port $flags]
				oo::objdefine $con forward human_id apply {
					{human_id} {
						set human_id
					}
				} "uri([$uri_obj encoded]) pid([pid]) con($con)"
				return $con
			} on error {errmsg options} {
				if {[info exists con] && [info object isa object $con]} {
					$con destroy
					unset con
				}
				if {[info exists socket] && $socket in [chan names]} {
					close $socket
					unset socket
				}

				return -options $options $errmsg
			}
		}

		#>>>
	}


	#>>>
	class create listener::jssocket { #<<<
		superclass netdgram::listener
		mixin netdgram::debug

		variable {*}{
			flags
			listen
		}

		constructor {host port a_flags} { #<<<
			if {[self next] ne {}} {next}

			set flags $a_flags
			if {$host in {* 0.0.0.0 ""}} {
				set listen	[socket -server [namespace code {my _accept}] $port]
			} else {
				set listen	[socket -server [namespace code {my _accept}] -myaddr $host $port]
			}
		}

		#>>>
		destructor { #<<<
			if {[info exists listen]} {
				close $listen
				unset listen
			}

			if {[self next] ne {}} {next}
		}

		#>>>

		method _accept {socket cl_ip cl_port} { #<<<
			try {
				set con		[netdgram::connection::jssocket new \
						$socket $cl_ip $cl_port $flags [namespace code {my accept}]]

				oo::objdefine $con forward human_id return \
						"con($con) fromaddr($cl_ip:$cl_port) on [my human_id]"

				#my accept $con $cl_ip $cl_port
			} on error {errmsg options} {
				puts "Error in accept: $errmsg\n[dict get $options -errorinfo]"
				if {[info exists con] && [info object is object $con]} {
					$con destroy
					unset con
				}
				return
			}

			if {![info exists con] || ![info object is object $con]} {
				# $con died, most likely killed by the accept handler
				return
			}
			try {
				$con activate
			} on error {errmsg options} {
				puts stderr "Unexpected error activating $con: $errmsg\n[dict get $options -errorinfo]"
				if {[info object is object $con]} {
					$con destroy
					unset con
				}
			}
		}

		#>>>
	}


	#>>>
	class create connection::jssocket { #<<<
		superclass netdgram::connection
		mixin netdgram::debug

		variable {*}{
			socket
			cl_ip
			cl_port
			data_waiting
			accepted
			onaccept
		}

		constructor {a_socket a_cl_ip a_cl_port a_flags a_onaccept} { #<<<
			if {[self next] ne {}} {next}
			set socket	$a_socket
			set cl_ip	$a_cl_ip
			set cl_port	$a_cl_port
			set data_waiting	0
			set accepted		0
			set onaccept		$a_onaccept
			try {
				try {
					package require sockopt
				} on error {errmsg options} {
					#puts stderr "Could not load sockopts: $errmsg"
				} on ok {} {
					sockopt::setsockopt $socket SOL_SOCKET SO_KEEPALIVE 1
					sockopt::setsockopt $socket SOL_TCP TCP_KEEPIDLE 120
					sockopt::setsockopt $socket SOL_TCP TCP_KEEPCNT 2
					sockopt::setsockopt $socket SOL_TCP TCP_KEEPINTVL 20
					sockopt::setsockopt $socket SOL_TCP TCP_NODELAY 1
				}
			} on error {errmsg options} {
				puts stderr "Error initializing socket: $errmsg\n[dict get $options -errorinfo]"
				return -options $options $errmsg
			}
		}

		#>>>
		destructor { #<<<
			if {[info exists socket] && $socket in [chan names]} {
				close $socket
				unset socket
			}

			my closed
			if {[self next] ne {}} {next}
		}

		#>>>

		method activate {} { #<<<
			if {![info exists socket] || $socket ni [chan names]} {
				throw {socket_collapsed} "Socket collapsed"
			}
			set coro	"::consumer_[string map {:: _} [self]]"
			coroutine $coro my _consumer
			chan event $socket readable [list $coro]
		}

		#>>>
		method send {msg} { #<<<
			try {
				chan configure $socket \
						-buffering full
				append msg "\x0"
				chan puts -nonewline $socket $msg
				#puts stderr "Sending null terminated packet: ($msg)"
				#puts "writing msg: ($msg) to $socket"
				chan flush $socket
			} on error {errmsg options} {
				puts stderr "Error writing message to socket: $errmsg\n[dict get $options -errorinfo]"
				my destroy
				return
			}
		}

		#>>>
		method data_waiting {newstate} { #<<<
			if {$newstate == $data_waiting} return
			set data_waiting	$newstate

			if {$data_waiting} {
				#my variable writable_kickoff
				#set writable_kickoff	[clock microseconds]
				chan event $socket writable [namespace code {my _notify_writable}]
			} else {
				chan event $socket writable {}
			}
		}

		#>>>

		method _consumer {} { #<<<
			try {
				chan configure $socket \
						-blocking		0 \
						-translation	binary \
						-encoding		binary \
						-buffering		none

				set buf	""
				while {1} {
					set chunk	[chan read $socket]
					if {[chan eof $socket]} {throw {close} ""}
					set chunklen	[string length $chunk]
					if {$chunklen == 0} {
						yield
						continue
					}

					append buf	$chunk
					set buf	[my _process_packets $buf]
				}
			} trap {close} {res options} {
				# Nothing to do.  destructor takes care of it
				#puts stderr "Closing [self] (by falling through to destructor)"
			} on error {errmsg options} {
				puts stderr "Unhandled error in consumer: $errmsg"
				array set e $options
				parray e
				puts stderr "[dict get $options -errorinfo]"
			} finally {
				my destroy
			}
		}

		#>>>
		method _process_packets {buf} { #<<<
			set parts		[split $buf "\x0"]
			set remaining	[lindex $parts end]
			set parts		[lrange $parts 0 end-1]
			foreach part $parts {
				if {[string trim $part] eq "<policy-file-request/>"} {
					puts stderr "[self] Saw policy request, sending policy"
					my _send_policy
					throw {close} ""
				}
				if {!($accepted)} {
					try {
						#puts stderr "[self] seeking acceptance"
						uplevel #0 $onaccept [self] $cl_ip $cl_port
					} on error {errmsg options} {
						puts "Error in accept: $errmsg\n[dict get $options -errorinfo]"
						my destroy
						return
					} on ok {} {
						#puts stderr "[self] feels accepted"
						set accepted	1
					}
				}
				if {$part eq "ready"} {continue}

				# Prevent message handling code higher up the stack
				# from yielding our consumer coroutine
				coroutine coro_received_[incr ::coro_seq] \
						my received $part
			}
		}

		#>>>
		method _send_policy {} { #<<<
			#puts stderr "Sending policy"
			chan puts $socket [string trim {
<?xml version="1.0"?>
<!DOCTYPE cross-domain-policy SYSTEM "http://www.macromedia.com/xml/dtds/cross-domain-policy-dtd">
<cross-domain-policy>
	<allow-access-from domain="*" to-ports="*" />
</cross-domain-policy>
			}]
		}

		#>>>
		method _notify_writable {} { #<<<
			# Also called for eof
			if {[chan eof $socket]} {
				my destroy
				return
			}

			try {
				my writable
			} on error {errmsg options} {
				puts stderr "Error in writable handler: $errmsg\n[dict get $options -errorinfo]"
			}
		}

		#>>>
	}


	#>>>
}
