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
				::tcl::mathfunc
			}]

			set socket	$a_socket
			set cl_ip	$a_cl_ip
			set cl_port	$a_cl_port
			set data_waiting	0
			set mode			0
			set buf				""
			set payload			""

			chan configure $socket \
					-blocking 0 \
					-buffering full \
					-translation binary

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
			if {[info exists socket]} {
				if {$socket in [chan names]} {
					close $socket
				}
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
			chan event $socket readable [code _readable]
		}

		#>>>
		method send {msg} { #<<<
			try {
				chan puts -nonewline $socket "[string length $msg]\n$msg"
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
				my _notify_writable
			} else {
				chan event $socket writable {}
			}
		}

		#>>>
		method is_data_waiting {} {set data_waiting}

		method _readable {} { #<<<
			try {
				append buf	[chan read $socket]
			} trap {POSIX EHOSTUNREACH} {errmsg options} {
				puts stderr "Host unreachable from $cl_ip:$cl_port"
				tailcall my destroy
			} trap {POSIX ETIMEDOUT} {errmsg options} {
				puts stderr "Host timeout from $cl_ip:$cl_port"
				tailcall my destroy
			}

			if {[chan eof $socket]} {
				tailcall my destroy
			}
			if {[chan blocked $socket]} return

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
					set consume	[min $buflen $remaining]
					if {$consume == $buflen} {
						append payload	$buf
						set buf			""
					} else {
						append payload	[string range $buf 0 [- $consume 1]]
						set buf			[string range $buf $consume end]
					}
					if {[incr remaining -$consume] > 0} return

					try {
						# TODO: take care of re-entrant issues here, which
						# occur if the code called here enters vwait, and more
						# data arrives and wakes up _readable again
						my received $payload
					} on error {errmsg options} {
						puts stderr "Error processing datagram: [dict get $options -errorinfo]"
					}
					set mode	0
					set payload	""
				}
			}
		}

		#>>>
		method _notify_writable {} { #<<<
			# Also called for eof
			if {[chan eof $socket]} {
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
				my writable
			} on error {errmsg options} {
				puts stderr "Error in writable handler: $errmsg\n[dict get $options -errorinfo]"
			}
		}

		#>>>
	}

	#>>>
}
