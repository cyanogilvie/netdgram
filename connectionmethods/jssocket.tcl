# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

namespace eval netdgram {
	package require netdgram

	class create connectionmethod::jssocket { #<<<
		superclass netdgram::connectionmethod
		mixin netdgram::debug

		constructor {} { #<<<
			if {[self next] ne {}} {next}
			namespace path [concat [namespace path] {
				::oo::Helpers::cflib
			}]

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
		method connect {uri_obj} { # <<<
			try {
				set parts	[$uri_obj as_dict]
				set params	[split [dict get $parts authority] :]
				if {[llength $params] != 2} {
					error "Invalid connection parameters, expecting [self class]://ip:port"
				}
				lassign $params host port
				set flags	[dict get $parts query]
				set socket	[socket $host $port]

				set con	[netdgram::connection::jssocket new new $socket $host $port $flags]
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

			namespace path [concat [namespace path] {
				::oo::Helpers::cflib
			}]

			set flags $a_flags
			if {$host in {* 0.0.0.0 ""}} {
				set listen	[socket -server [code _accept] $port]
			} else {
				set listen	[socket -server [code _accept] -myaddr $host $port]
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
			log notice "Accepting socket ($socket) from ($cl_ip:$cl_port)"
			try {
				set con		[netdgram::connection::jssocket new \
						new $socket $cl_ip $cl_port $flags [code accept]]

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
			} trap {socket_collapsed} {errmsg options} {
				if {[info object is object $con]} {
					$con destroy
					unset con
				}
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
			buf
			flags

			teleporting
		}

		constructor {create_mode a_socket a_cl_ip a_cl_port a_flags a_onaccept} { #<<<
			if {[self next] ne ""} next

			namespace path [concat [namespace path] {
				::tcl::mathop
				::oo::Helpers::cflib
			}]

			set cl_ip			$a_cl_ip
			set cl_port			$a_cl_port
			set flags			$a_flags

			if {$create_mode eq "new"} {
				set socket			$a_socket

				chan configure $socket \
						-blocking		0 \
						-translation	binary \
						-encoding		binary \
						-buffering		none

				set buf				""
				set data_waiting	0
				set accepted		0
				set onaccept		$a_onaccept
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
					}
				} on error {errmsg options} {
					?? {log error "Error initializing socket: $errmsg\n[dict get $options -errorinfo]"}
					return -options $options $errmsg
				}
			} elseif {$create_mode eq "teleport"} {
				my _restore_state $a_socket
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
				if {[info exists socket] && $socket in [chan names]} {
					chan close $socket
					unset socket
				}

				my closed
			}

			if {[self next] ne ""} next
		}

		#>>>

		method activate {} { #<<<
			if {![info exists socket] || $socket ni [chan names]} {
				throw socket_collapsed "Socket collapsed"
			}
			?? {log debug "Activating socket ($socket) [self] in thread [thread::id], accepted? $accepted"}
			if {!($accepted)} {
				chan event $socket readable [code _readable_preaccepted]
			} else {
				chan event $socket readable [code _readable]
			}

			if {$data_waiting} {
				#my variable writable_kickoff
				#set writable_kickoff	[clock microseconds]
				chan event $socket writable [code _notify_writable]
			} else {
				chan event $socket writable {}
			}
		}

		#>>>
		method send msg { #<<<
			try {
				set msg	[binary encode base64 $msg[unset msg]]
				append msg "\x0"
				chan puts -nonewline $socket $msg
				?? {
					if {[dict exists $flags tap]} {
						my _tap rx $msg
					}
				}
				#puts stderr "Sending null terminated packet: ($msg)"
				#puts "writing msg: ($msg) to $socket"
				#chan flush $socket
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
				chan event $socket writable [code _notify_writable]
			} else {
				chan event $socket writable {}
			}
		}

		#>>>
		method teleport thread_id { #<<<
			?? {log debug "Teleporting to thread $thread_id (from [thread::id])"}
			if {!($accepted)} {
				log warning "Teleporting a not-yet-accepted jssocket connection.  This will most likely fail"
			}
			chan event $socket readable {}
			chan event $socket writable {}
			thread::detach $socket
			thread::send $thread_id {package require netdgram::jssocket}
			set new	[thread::send $thread_id [list [self class] new teleport [my _save_state] $cl_ip $cl_port $flags $onaccept]]
			unset socket
			set teleporting	1
			my destroy
			set new
		}

		#>>>

		method _save_state {} { #<<<
			list $socket $data_waiting $accepted $buf
		}

		#>>>
		method _restore_state serialized { #<<<
			lassign $serialized socket data_waiting accepted buf
			?? {log trivia "Restoring state from ($serialized)"}
		}

		#>>>
		method _readable_preaccepted {} { #<<<
			?? {log trivia "socket $socket _readable_preaccepted"}
			while {1} {
				try {
					chan read $socket
				} on ok chunk {
					append buf $chunk
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
					?? {log trivia "Chan blocked ($socket)"}
					return
				}
				?? {log trivia "Processing [string length $buf] bytes of buf"}
				?? {log trivia [regexp -all -inline .. [binary encode hex $buf]]}

				while {1} {
					set idx	[string first "\x0" $buf]
					?? {log trivia "idx: ($idx)"}
					if {$idx == -1} return

					set packet	[string range $buf 0 [- $idx 1]]
					?? {log trivia "Got packet: ($packet)"}
					set buf		[string range $buf[unset buf] [+ $idx 1] end]

					if {[string trim $packet] eq "<policy-file-request/>"} {
						?? {log debug "[self] Saw policy request, sending policy"}
						my _send_policy
						chan event $socket readable {}
						chan event $socket writable {}
						tailcall my destroy
					}

					try {
						?? {log debug "Dispatching deferred accept callback"}
						chan event $socket readable {}
						chan event $socket writable {}
						uplevel #0 $onaccept [self] $cl_ip $cl_port
					} trap dont_activate {} {
						?? {log debug "Got signal not to activate [self] yet"}
						set accepted	1
						return
					} on error {errmsg options} {
						log error "Error in accept: $errmsg\n[dict get $options -errorinfo]"
						tailcall my destroy
					} on ok {} {
						?? {log debug "[self] feels accepted"}
						set accepted	1
						my activate
					}
				}
			}
		}

		#>>>
		method _readable {} { #<<<
			?? {log trivia "socket $socket _readable"}
			while {1} {
				try {
					chan read $socket
				} on ok chunk {
					append buf $chunk
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
				if {[chan blocked $socket]} return

				while {1} {
					set idx	[string first \x0 $buf]
					if {$idx == -1} return

					set epacket	[string range $buf 0 [- $idx 1]]
					set buf		[string range $buf[unset buf] [+ $idx 1] end]
					if {$epacket eq "ready"} continue
					my received [binary decode base64 $epacket]
				}
			}
		}

		#>>>
		method _send_policy {} { #<<<
			#puts stderr "Sending policy"
			set policy	[string trim {
<?xml version="1.0"?>
<!DOCTYPE cross-domain-policy SYSTEM "http://www.macromedia.com/xml/dtds/cross-domain-policy-dtd">
<cross-domain-policy>
	<allow-access-from domain="*" to-ports="*" />
</cross-domain-policy>
			}]
			chan puts $socket $policy
			?? {
				if {[dict exists $flags tap]} {
					my _tap tx $policy
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

			try {
				my writable
			} on error {errmsg options} {
				puts stderr "Error in writable handler: $errmsg\n[dict get $options -errorinfo]"
			}
		}

		#>>>
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
