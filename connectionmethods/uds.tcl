# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

namespace eval netdgram {
	package require netdgram

	class create connectionmethod::uds { #<<<
		superclass netdgram::connectionmethod
		mixin netdgram::debug

		constructor {} { #<<<
			if {[self next] ne ""} next

			package require unix_sockets
		}

		#>>>

		method listen {uri_obj} { #<<<
			set parts	[$uri_obj as_dict]
			if {[dict get $parts authority] ne ""} {
				error "Unix domain sockets can only be local"
			}
			set path	[dict get $parts path]
			set flags	[dict get $parts query]
			set listen	[netdgram::listener::uds new $path $flags]
			oo::objdefine $listen forward human_id apply {
				{human_id} {set human_id}
			} "uri([$uri_obj encoded]) pid([pid])"
			set listen
		}

		#>>>
		method connect {uri_obj} { #<<<
			try {
				set parts	[$uri_obj as_dict]
				if {[dict get $parts authority] ne ""} {
					error "Unix domain sockets can only be local"
				}
				set path	[dict get $parts path]
				set flags	[dict get $parts query]
				set socket	[unix_sockets::connect $path]

				set con	[netdgram::connection::uds new new $socket $flags]
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
	}


	#>>>
	class create listener::uds { #<<<
		superclass netdgram::listener
		mixin netdgram::debug

		variable {*}{
			flags
			listen
		}

		constructor {path a_flags} { #<<<
			if {[self next] ne ""} next

			set flags $a_flags
			set dir	[file normalize [file dirname $path]]
			if {![file exists $dir]} {
				file mkdir $dir
			}
			if {![file isdirectory $dir]} {
				error "Requested socket path parent exists but is not a directory"
			}
			if {[file exists $path] && (![file writable $path] || ![file writable $dir])} {
				error "Requested socket path \"$path\" exists but is not writable by us"
			}
			set listen	[unix_sockets::listen $path [namespace code {my _accept}]]
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

		method _accept {socket} { #<<<
			try {
				set con		[netdgram::connection::uds new \
						new $socket $flags]

				$con set_human_id "con($con) on [my human_id]"

				my accept $con
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
	class create connection::uds { #<<<
		superclass netdgram::connection
		mixin netdgram::debug

		variable {*}{
			socket
			data_waiting
			buf
			mode
			remaining
			payload
			human_id

			teleporting
		}

		constructor {create_mode a_socket a_flags} { #<<<
			if {[self next] ne ""} next

			namespace path [concat [namespace path] {
				::oo::Helpers::cflib
				::tcl::mathop
			}]

			if {$create_mode eq "new"} {
				set socket	$a_socket
				set data_waiting	0
				set mode			0
				set buf				""
				set payload			""
				set remaining		0

				chan configure $socket \
						-blocking 0 \
						-buffering none \
						-translation binary

			} elseif {$create_mode eq "teleport"} {
				lassign $a_socket \
						socket \
						data_waiting \
						buf \
						mode \
						remaining \
						payload \
						human_id
				thread::attach $socket
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
			chan event $socket readable [code _readable]
		}

		#>>>
		method send {msg} { #<<<
			try {
				chan puts -nonewline $socket "[string length $msg]\n$msg"
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
				chan event $socket writable [code _notify_writable]
				my _notify_writable
			} else {
				chan event $socket writable {}
			}
		}

		#>>>
		method is_data_waiting {} {set data_waiting}
		method teleport thread_id { #<<<
			chan event $socket readable {}
			chan event $socket writable {}
			thread::detach $socket
			thread::send $thread_id {package require netdgram::uds}
			set new	[thread::send $thread_id [list [self class] new teleport [list \
					$socket \
					$data_waiting \
					$buf \
					$mode \
					$remaining \
					$payload \
					$human_id] -]]
			unset socket
			set teleporting	1
			my destroy
			set new
		}

		#>>>
		method _readable {} { #<<<
			while {1} {
				try {
					append buf	[chan read $socket]
				} trap {POSIX EHOSTUNREACH} {errmsg options} {
					log error "Host unreachable"
					tailcall my destroy
				} trap {POSIX ETIMEDOUT} {errmsg options} {
					log error "Host timeout"
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
							my received $payload
						} on error {errmsg options} {
							log error "Error processing datagram: [dict get $options -errorinfo]"
						}
						set mode	0
						set payload	""
					}
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
				log error "Error in writable handler: $errmsg\n[dict get $options -errorinfo]"
			}
		}

		#>>>
		method human_id {} {set human_id}
		method set_human_id {new_human_id} {set human_id $new_human_id}
	}

	#>>>
}
