# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

namespace eval netdgram {
	package require netdgram

	class create connectionmethod::uds { #<<<
		superclass netdgram::connectionmethod
		mixin netdgram::debug

		constructor {} { #<<<
			if {[self next] ne {}} {next}
			if {![package vsatisfies [info patchlevel] 8.6-]} {
				error "Coroutines require Tcl 8.6"
			}

			package require unix_sockets
		}

		#>>>

		method listen {uri_obj} { # <<<
			set parts	[$uri_obj as_dict]
			if {[dict get $parts authority] ne ""} {
				error "Unix domain sockets can only be local"
			}
			set path	[dict get $parts path]
			set flags	[dict get $parts query]
			return [netdgram::listener::uds new $path $flags]
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
				if {[dict get $parts authority] ne ""} {
					error "Unix domain sockets can only be local"
				}
				set path	[dict get $parts path]
				set flags	[dict get $parts query]
				set socket	[unix_sockets::connect $path]

				set con	[netdgram::connection::uds new $socket $flags]
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
	class create listener::uds { #<<<
		superclass netdgram::listener
		mixin netdgram::debug

		variable {*}{
			flags
			listen
		}

		constructor {path a_flags} { #<<<
			if {[self next] ne {}} {next}

			set flags $a_flags
			set dir	[file normalize [file dirname $path]]
			if {![file exists $dir]} {
				file mkdir $dir
			}
			if {![file isdirectory $dir]} {
				error "Requested socket path parent exists but is not a directory"
			}
			set listen	[unix_sockets::listen $path [namespace code {my _accept}]]
		}

		#>>>
		destructor { #<<<
			if {[info exists listen]} {
				if {$listen in [chan names]} {
					close $listen
				}
				unset listen
			}
			if {[self next] ne {}} {next}
		}

		#>>>

		method _accept {socket} { #<<<
			try {
				set con		[netdgram::connection::uds new \
						$socket $flags]

				oo::objdefine $con forward human_id apply {
					{human_id} {
						set human_id
					}
				} "con($con) on [my human_id]"

				my accept $con
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
	class create connection::uds { #<<<
		superclass netdgram::connection
		mixin netdgram::debug

		variable {*}{
			socket
			data_waiting
		}

		constructor {a_socket a_flags} { #<<<
			if {[self next] ne {}} {next}

			set socket	$a_socket
			set data_waiting	0
			#puts "[self] initialized socket to: ($socket)"
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
			set coro	"::consumer_[string map {:: _} [self]]"
			coroutine $coro my _consumer
			if {![info exists socket] || $socket ni [chan names]} {
				throw {socket_collapsed} "Socket collapsed"
			}
			chan event $socket readable [list $coro]
		}

		#>>>
		method send {msg} { #<<<
			set data_len	[string length $msg]
			try {
				chan configure $socket \
						-buffering full
				chan puts $socket $data_len
				chan puts -nonewline $socket $msg
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
				chan event $socket writable [namespace code {my _notify_writable}]
			} else {
				chan event $socket writable {}
			}
		}

		#>>>

		method _consumer {} { #<<<
			try {
				while {1} {
					chan configure $socket \
							-blocking 0 \
							-buffering line \
							-translation binary

					while {1} {
						set line	[gets $socket]
						if {[chan eof $socket]} {throw {close} ""}
						if {![chan blocked $socket]} break
						yield
					}

					lassign $line payload_bytecount
					set remaining	$payload_bytecount

					if {![string is integer -strict $payload_bytecount]} {
						throw {close} ""
					}

					chan configure $socket \
							-blocking 0 \
							-buffering none \
							-translation binary
					set payload	""
					while {$remaining > 0} {
						set chunk	[chan read $socket $remaining]
						if {[chan eof $socket]} {throw {close} ""}
						set chunklen	[string length $chunk]
						if {$chunklen == 0} {
							yield
							continue
						}
						append payload	$chunk
						unset chunk
						incr remaining -$chunklen
					}

					my received $payload
				}
			} trap {close} {res options} {
				# Nothing to do.  destructor takes care of it
			} on error {errmsg options} {
				puts stderr "Unhandled error in consumer: $errmsg\n[dict get $options -errorinfo]"
			} finally {
				my destroy
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
	}


	#>>>
}

