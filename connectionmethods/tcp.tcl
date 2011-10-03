# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

# TODO: take care of readable re-entrant issues

namespace eval netdgram {
	package require netdgram

	class create connectionmethod::tcp { #<<<
		superclass netdgram::connectionmethod
		mixin netdgram::debug

		variable {*}{
			connected_vwait
			connected_vwait_seq
		}

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
			set listen	[netdgram::listener::tcp new $host $port $flags]
			oo::objdefine $listen forward human_id apply {
				{human_id} {set human_id}
			} "uri([$uri_obj encoded]) pid([pid])"
			set listen
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
				if {[dict exists $flags timeout] && [dict get $flags timeout] != 0} {
					set socket	[socket -async $host $port]
					if {[info coroutine] ne ""} {
						chan event $socket writable [list apply {
							{coro args} {$coro {*}$args}
						} [info coroutine] _netdgram_connected]
						set afterid	[after [dict get $flags timeout] [list apply {
							{coro args} {$coro {*}$args}
						} [info coroutine] _netdgram_timeout]]
						while {1} {
							set rest	[lassign [yield] wakeup_reason]
							switch -- $wakeup_reason {
								_netdgram_connected {
									try {
										chan puts -nonewline $socket "0\n"
										chan flush $socket
									} trap {POSIX EPIPE} {} {
										throw {POSIX ECONNREFUSED} "connection refused"
									}
									after cancel $afterid; set afterid	""
									chan event $socket writable {}
									break
								}

								_netdgram_timeout {
									chan event $socket writable {}
									chan close $socket
									throw timeout "Timeout waiting for netdgram connection to [$uri_obj encoded]"
								}

								default {
									log error "Unexpected wakeup reason while waiting for netdgram connection to [$uri_obj encoded]"
								}
							}
						}
					} else {
						set myseq	[incr connected_vwait_seq]
						chan event $socket writable [list set [namespace which -variable connected_vwait]($myseq) _netdgram_connected]
						set afterid	[after [dict get $flags timeout] [list set [namespace which -variable connected_vwait]($myseq) _netdgram_timeout]]
						vwait [namespace which -variable connected_vwait]($myseq)
						after cancel $afterid; set afterid	""
						set res	$connected_vwait($myseq)
						array unset connected_vwait $myseq
						switch -- $res {
							_netdgram_connected {
								try {
									chan puts -nonewline $socket "0\n"
									chan flush $socket
								} trap {POSIX EPIPE} {} {
									throw {POSIX ECONNREFUSED} "connection refused"
								}
								chan event $socket writable {}
							}
							_netdgram_timeout {
								chan event $socket writable {}
								chan close $socket
								throw timeout "Timeout waiting for netdgram connection to [$uri_obj encoded]"
							}
							default {
								chan close $socket
								error "Unexpected outcome waiting for netdgram connection to [$uri_obj encoded]: \"$res\""
							}
						}
					}
				} else {
					set socket	[socket $host $port]
				}

				set con	[netdgram::connection::tcp new new $socket $host $port $flags]
				$con set_human_id "uri([$uri_obj encoded]) pid([pid]) con($con)"
				set con
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
			if {[self next] ne ""} next

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

			if {[self next] ne ""} next
		}

		#>>>

		method _accept {socket cl_ip cl_port} { #<<<
			try {
				set con		[netdgram::connection::tcp new \
						new $socket $cl_ip $cl_port $flags]

				$con set_human_id "con($con) fromaddr($cl_ip:$cl_port) on [my human_id]"

				my accept $con $cl_ip $cl_port
			} trap dont_activate {} {
				return
			} on error {errmsg options} {
				log error "Error in accept: $errmsg\n[dict get $options -errorinfo]"
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
				log error "Unexpected error activating $con: $errmsg\n[dict get $options -errorinfo]"
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
			human_id
			flags

			teleporting
		}

		constructor {create_mode a_socket a_cl_ip a_cl_port a_flags} { #<<<
			if {[self next] ne ""} next

			set flags	$a_flags

			namespace path [concat [namespace path] {
				::oo::Helpers::cflib
				::tcl::mathop
			}]

			if {$create_mode eq "new"} {
				set socket	$a_socket
				set cl_ip	$a_cl_ip
				set cl_port	$a_cl_port
				set data_waiting	0
				set mode			0
				set buf				""
				set payload			""
				set remaining		0

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
						?? {log trivia "Loaded sockopt and configured keepalive and nodelay"}
					}
				} on error {errmsg options} {
					log error "Error initializing socket: $errmsg\n[dict get $options -errorinfo]"
					return -options $options $errmsg
				}
			} elseif {$create_mode eq "teleport"} {
				lassign $a_socket \
						socket \
						cl_ip \
						cl_port \
						data_waiting \
						buf \
						mode \
						remaining \
						payload \
						human_id
				thread::attach $socket
				?? {log debug "Thread [thread::id] attaching to teleported socket $socket"}
				if {$data_waiting} {
					chan event $socket writable [code _notify_writable]
				}
			} else {
				error "Invalid create_mode \"$create_mode\""
			}
		}

		#>>>
		destructor { #<<<
			if {![info exists teleporting]} {
				?? {log debug "tcp connection handler dieing [self]"}
				if {[info exists socket]} {
					if {$socket in [chan names]} {
						close $socket
					}
					unset socket
				}

				my closed
			}

			if {[self next] ne ""} next
		}

		#>>>

		method activate {} { #<<<
			if {![info exists socket] || $socket ni [chan names]} {
				throw {socket_collapsed} "Socket collapsed"
			}
			?? {log debug "Activating socket ($socket) [self] in thread [thread::id]"}
			chan event $socket readable [code _readable]
		}

		#>>>
		method send {msg} { #<<<
			try {
				?? {log trivia "Sending message [self]"}
				chan puts -nonewline $socket "[string length $msg]\n$msg"
				?? {
					if {[dict exists $flags tap]} {
						my _tap tx "[string length $msg]\n$msg"
					}
				}
				#puts "writing msg: ($msg) to $socket"
				#?? {set before [clock microseconds]}
				#chan flush $socket
				#?? {log debug "chan flush time: [expr {[clock microseconds] - $before}] microseconds"}
			} on error {errmsg options} {
				log error "Error writing message to socket: $errmsg\n[dict get $options -errorinfo]"
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
				?? {log trivia "data waiting [self] 0 -> 1"}
				chan event $socket writable [code _notify_writable]
				my _notify_writable
			} else {
				?? {log trivia "data waiting [self] 1 -> 0"}
				chan event $socket writable {}
			}
		}

		#>>>
		method is_data_waiting {} {set data_waiting}
		method teleport thread_id { #<<<
			?? {log debug "Teleporting to thread $thread_id (from [thread::id])"}
			chan event $socket readable {}
			chan event $socket writable {}
			thread::detach $socket
			thread::send $thread_id {package require netdgram::tcp}
			set new	[thread::send $thread_id [list [self class] new teleport [list \
					$socket \
					$cl_ip \
					$cl_port \
					$data_waiting \
					$buf \
					$mode \
					$remaining \
					$payload \
					$human_id] - - $flags]]
			unset socket
			set teleporting	1
			my destroy
			set new
		}

		#>>>
		method _readable {} { #<<<
			?? {log trivia "readable [self], sizes buf: [string length $buf], payload: [string length $payload], mode: $mode, thread: [thread::id]"}
			while {1} {
				try {
					chan read $socket
				} on ok {chunk} {
					?? {log trivia "after chan read, chunk: [string length $chunk] [regexp -all -inline .. [binary encode hex [string range $chunk 0 5]]]"}
					append buf	$chunk
					?? {
						if {[dict exists $flags tap]} {
							my _tap rx $chunk
						}
					}
				} trap {POSIX EHOSTUNREACH} {errmsg options} {
					log error "Host unreachable from $cl_ip:$cl_port"
					tailcall my destroy
				} trap {POSIX ETIMEDOUT} {errmsg options} {
					log error "Host timeout from $cl_ip:$cl_port"
					tailcall my destroy
				}

				if {[chan eof $socket]} {
					?? {log trivia "socket closed [self]"}
					tailcall my destroy
				}
				if {[string length $chunk] == 0} return
				if {[chan blocked $socket]} {
					?? {log trivia "socket blocked, returning [self]"}
					return
				}

				while {1} {
					if {$mode == 0} {
						# The scan method fails badly on a short read that cuts
						# the remaining length number in half
						#if {[scan $buf "%\[^\n\]\n%n" line datastart] == -1} return
						set idx	[string first \n $buf]
						if {$idx == -1} return
						set line	[string range $buf 0 [- $idx 1]]
						set datastart	[+ $idx 1]
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
							?? {log trivia "dispatching payload of [string length $payload] bytes"}
							if {$payload ne ""} {
								my received $payload
							}
						} on error {errmsg options} {
							log error "Error processing datagram: [dict get $options -errorinfo]"
						}
						set mode	0
						set payload	""
					}
				}
			}
			?? {log trivia "leaving readable [self]"}
		}

		#>>>
		method _notify_writable {} { #<<<
			?? {log trivia "_notify_writable [self]"}
			# Also called for eof
			if {[chan eof $socket]} {
				?? {log trivia "eof [self]"}
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
				?? {log trivia "Calling writable handler [self]"}
				my writable
			} on error {errmsg options} {
				log error "Error in writable handler: $errmsg\n[dict get $options -errorinfo]"
			}
		}

		#>>>
		method human_id {} {set human_id}
		method set_human_id {new_human_id} {set human_id $new_human_id}

		method _tap {dir data} { #<<<
			set h	[open [dict get $flags tap] a]
			try {
				chan puts $h [list $dir $data]
			} finally {
				chan close $h
			}
		}

		#>>>
	}

	#>>>
}
