# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

# Connection method plugins must implement this API

namespace eval netdgram {
	namespace path ::oo

	variable managers	[dict create]

	proc connect_uri {uri} { #<<<
		try {
			set uri_obj		[netdgram::uri new $uri]
			set uri_parts	[$uri_obj as_dict]

			if {[$uri_obj type] eq "relative"} {
				if {
					[dict get $uri_parts authority] eq "" &&
					[dict get $uri_parts path] ne ""
				} {
					$uri_obj set_part scheme uds
				} else {
					$uri_obj set_part scheme tcp
				}
				set uri_parts	[$uri_obj as_dict]
			}

			set manager	[netdgram::_get_manager [dict get $uri_parts scheme]]

			$manager connect $uri_obj
		} finally {
			if {[info exists uri_obj] && [info object is object $uri_obj]} {
				$uri_obj destroy
				unset uri_obj
			}
		}
	}

	#>>>
	proc listen_uri {uri} { #<<<
		try {
			set uri_obj		[netdgram::uri new $uri]
			set uri_parts	[$uri_obj as_dict]

			set manager	[netdgram::_get_manager [dict get $uri_parts scheme]]

			return [$manager listen $uri_obj]
		} finally {
			if {[info exists uri_obj] && [info object is object $uri_obj]} {
				$uri_obj destroy
				unset uri_obj
			}
		}
	}

	#>>>

	proc _get_manager {scheme} { #<<<
		variable managers

		if {![dict exists $managers $scheme]} {
			package require netdgram::$scheme
			dict set managers $scheme \
					[netdgram::connectionmethod::${scheme} new]
		}
		dict get $managers $scheme
	}

	#>>>

	class create debug { #<<<
		#filter _foolog
		method _foolog {args} { #<<<
			puts "Calling: [self] [join [self target] ->] $args"
			next {*}$args
		}

		#>>>
	}

	#>>>

	class create connectionmethod { #<<<
		mixin netdgram::debug

		method listen {uri_obj} {}		;# Returns netdgram::Listener instance
		method connect {uri_obj} {}		;# Returns netdgram::Connection instance
	}

	#>>>
	class create connection { #<<<
		mixin netdgram::debug

		constructor {} {
			if {[llength [info commands log]] == 0} {proc log {lvl msg} {puts stderr $msg}}
			if {[self next] ne ""} next
		}

		# Forward / override these to add high level behaviour
		method human_id {} {return "not set: [self]"}
		method received {msg} {}
		method closed {} {}
		method writable {} {}
		method teleport thread_id {throw not_teleportable "Cannot teleport connections of type [self class]"}

		method send {msg} {}
		method activate {} {}	;# Called when accept checks are passed
		method data_waiting {newstate} {}
		method is_data_waiting {} {}
	}

	#>>>
	class create listener { #<<<
		mixin netdgram::debug

		# Forward / override these to add high level behaviour
		method accept {con args} {}
		method human_id {} {return "not set: [self]"}
	}

	#>>>
}

