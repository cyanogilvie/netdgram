# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

# TODO: take care of readable re-entrant issues

namespace eval netdgram {
	package require netdgram

	class create connectionmethod::tcp { #<<<
		superclass netdgram::connectionmethod
		mixin netdgram::debug

		constructor {} { #<<<
			if {[self next] ne {}} {next}
			if {![package vsatisfies [info patchlevel] 8.6-]} {
				error "Coroutines require Tcl 8.6"
			}
		}

		#>>>

		method listen {uri_obj} { #<<<
			set parts	[$uri_obj as_dict]
			set params	[split [dict get $parts authority] :]
			switch -- [llength $params] {
				0 {
					set host	"*"
					set port	[my default_port]
				}

				1 {
					set host	[lindex $params 0]
					set port	[my default_port]
				}

				2 {
					lassign $params host port
					if {$host eq ""} {
						set host	"*"
					}
					if {$port eq ""} {
						set port	[my default_port]
					}
				}

				default {
					error "Invalid connection parameters, expecting [self class]://ip:port"
				}
			}
			set flags	[dict get $parts query]
			set listen [netdgram::listener::tcp new $host $port $flags]
			oo::objdefine $listen forward human_id apply {
				{human_id} {
					set human_id
				}
			} "uri([$uri_obj encoded]) pid([pid])"
			return $listen
		}

		#>>>
		method connect {uri_obj} { #<<<
			try {
				set parts	[$uri_obj as_dict]
				set params	[split [dict get $parts authority] :]
				switch -- [llength $params] {
					0 {
						set host	"localhost"
						set port	[my default_port]
					}

					1 {
						set host	[lindex $params 0]
						set port	[my default_port]
					}

					2 {
						lassign $params host port
						if {$host eq ""} {
							set host	"localhost"
						}
						if {$port eq ""} {
							set port	[my default_port]
						}
					}

					default {
						error "Invalid connection parameters, expecting [self class]://ip:port"
					}
				}
				set flags	[dict get $parts query]
				set socket	[socket $host $port]

				set con	[netdgram::connection::tcp new $socket $host $port $flags]
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
		method default_port {} { #<<<
			# Override this to implement default port behaviour
			error "No default port defined, must be specified in the URI"
		}

		#>>>
	}


	#>>>
	class create listener::tcp { #<<<
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
				if {$listen in [chan names]} {
					chan close $listen
				}
				unset listen
			}

			if {[self next] ne {}} {next}
		}

		#>>>

		method _accept {socket cl_ip cl_port} { #<<<
			try {
				set con		[netdgram::connection::tcp new \
						$socket $cl_ip $cl_port $flags]

				oo::objdefine $con forward human_id apply {
					{human_id} {
						set human_id
					}
				} "con($con) fromaddr($cl_ip:$cl_port) on [my human_id]"

				my accept $con $cl_ip $cl_port
			} on error {errmsg options} {
				puts stderr "Error in accept: $errmsg\n[dict get $options -errorinfo]"
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
	class create connection::tcp { #<<<
		superclass netdgram::connection
		mixin netdgram::debug

		variable {*}{
			socket
			cl_ip
			cl_port
			data_waiting
			buf
			mode
			remaining
			payload
		}

		constructor {a_socket a_cl_ip a_cl_port a_flags} { #<<<
			if {[self next] ne {}} {next}

			namespace path [concat [namespace path] {
				::oo::Helpers::cflib
				::tcl::mathop
			}]

			set socket	$a_socket
			set cl_ip	$a_cl_ip
			set cl_port	$a_cl_port
			set data_waiting	0
			set mode			0
			set buf				""
			set payload			""

			#chan configure $socket \
			#		-blocking 0 \
			#		-buffering full \
			#		-translation binary
			chan configure $socket \
					-blocking 0 \
					-buffering none \
					-translation binary

			try {
				try {
					package require sockopt
				} on error {errmsg options} {
					?? {log warning "Could not load sockopts: $errmsg"}
				} on ok {} {
					sockopt::setsockopt $socket SOL_SOCKET SO_KEEPALIVE 1
					sockopt::setsockopt $socket SOL_TCP TCP_KEEPIDLE 120
					sockopt::setsockopt $socket SOL_TCP TCP_KEEPCNT 2
					sockopt::setsockopt $socket SOL_TCP TCP_KEEPINTVL 20
					sockopt::setsockopt $socket SOL_TCP TCP_NODELAY 1
					?? {log debug "Loaded sockopt and configured keepalive and nodelay"}
				}
			} on error {errmsg options} {
				puts stderr "Error initializing socket: $errmsg\n[dict get $options -errorinfo]"
				return -options $options $errmsg
			}
		}

		#>>>
		destructor { #<<<
			?? {log debug "tcp connection handler dieing [self]"}
			if {[info exists socket]} {
				if {$socket in [chan names]} {
					?? {log debug "Closing socket [self]"}
					close $socket
				}
				unset socket
			}

			?? {log debug "Calling closed hooks [self]"}
			my closed
			?? {log debug "Done calling closed hooks [self]"}

			if {[self next] ne {}} {next}
			?? {log debug "All done [self]"}
		}

		#>>>

		method activate {} { #<<<
			if {![info exists socket] || $socket ni [chan names]} {
				throw {socket_collapsed} "Socket collapsed"
			}
			?? {log debug "Activating socket [self]"}
			chan event $socket readable [code _readable]
		}

		#>>>
		method send {msg} { #<<<
			try {
				?? {log debug "Sending message [self]"}
				chan puts -nonewline $socket "[string length $msg]\n$msg"
				#puts "writing msg: ($msg) to $socket"
				#?? {set before [clock microseconds]}
				#chan flush $socket
				#?? {log debug "chan flush time: [expr {[clock microseconds] - $before}] microseconds"}
			} on error {errmsg options} {
				puts stderr "Error writing message to socket: $errmsg\n[dict get $options -errorinfo]"
				my destroy
				return
			}
		}

		#>>>
		method data_waiting {newstate} { #<<<
			if {$newstate == $data_waiting} return
			if {[set data_waiting $newstate]} {
				#my variable writable_kickoff
				#set writable_kickoff	[clock microseconds]
				?? {log debug "data waiting [self] 0 -> 1"}
				chan event $socket writable [code _notify_writable]
				my _notify_writable
			} else {
				?? {log debug "data waiting [self] 1 -> 0"}
				chan event $socket writable {}
			}
		}

		#>>>
		method is_data_waiting {} {set data_waiting}

		method _readable {} { #<<<
			?? {log debug "readable [self], sizes buf: [string length $buf], payload: [string length $payload], mode: $mode"}
			while {1} {
				try {
					chan read $socket
				} on ok {chunk} {
					?? {log debug "after chan read, chunk: [string length $chunk]"}
					append buf	$chunk
				} trap {POSIX EHOSTUNREACH} {errmsg options} {
					log error "Host unreachable from $cl_ip:$cl_port"
					tailcall my destroy
				} trap {POSIX ETIMEDOUT} {errmsg options} {
					log error "Host timeout from $cl_ip:$cl_port"
					tailcall my destroy
				}

				if {[chan eof $socket]} {
					?? {log debug "socket closed [self]"}
					tailcall my destroy
				}
				if {[string length $chunk] == 0} return
				if {[chan blocked $socket]} {
					?? {log debug "socket blocked, returning [self]"}
					return
				}

				while {1} {
					if {$mode == 0} {
						if {[scan $buf "%\[^\n\]\n%n" line datastart] == -1} return
						#set idx	[string first \n $buf]
						#if {$idx == -1} return
						#set line	[string range $buf 0 [- $idx 1]]
						#set datastart	[+ $idx 1]
						lassign $line remaining
						set buf		[string range $buf[unset buf] $datastart end]
						set mode	1
					}
					if {$mode == 1} {
						set buflen	[string length $buf]
						set consume	[tcl::mathfunc::min $buflen $remaining]
						if {$consume == $buflen} {
							append payload	$buf
							set buf			""
						} else {
							append payload	[string range $buf 0 [- $consume 1]]
							set buf			[string range $buf $consume end]
						}
						if {[incr remaining -$consume] > 0} break

						try {
							# TODO: take care of re-entrant issues here, which
							# occur if the code called here enters vwait, and more
							# data arrives and wakes up _readable again
							?? {log debug "dispatching payload of [string length $payload] bytes"}
							my received $payload
						} on error {errmsg options} {
							puts stderr "Error processing datagram: [dict get $options -errorinfo]"
						}
						set mode	0
						set payload	""
					}
				}
			}
			?? {log debug "leaving readable [self]"}
		}

		#>>>
		method _notify_writable {} { #<<<
			?? {log debug "_notify_writable [self]"}
			# Also called for eof
			if {[chan eof $socket]} {
				?? {log debug "eof [self]"}
				my destroy
				return
			}

			#my variable writable_kickoff
			#if {[info exists writable_kickoff]} {
			#	set writable_delay	[expr {[clock microseconds] - $writable_kickoff}]
			#	unset writable_kickoff
			#	puts stderr "delay in getting writable after asking for it: $writable_delay usec"
			#}
			try {
				?? {log debug "Calling writable handler [self]"}
				my writable
			} on error {errmsg options} {
				puts stderr "Error in writable handler: $errmsg\n[dict get $options -errorinfo]"
			}
		}

		#>>>
	}

	#>>>
}
