# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

namespace eval netdgram {
	namespace path ::oo

	class create queue {
		mixin netdgram::debug

		variable {*}{
			queues
			rawcon
			msgid_seq
			defrag_buf
			target_payload_size
			roundrobin
			write_combining
			next_frag
			prequeueing
		}

		constructor {} { #<<<
			if {[self next] ne {}} {next}

			namespace path [concat [namespace path] {
				::tcl::mathop
			}]

			set queues		[dict create]
			set defrag_buf	[dict create]
			set msgid_seq	0
			#set target_payload_size		10000
			set roundrobin				{}
			set write_combining			0
			set prequeueing				1

			# worked out to 1500 MTU and msgid up to 9,999,999,999 or 14.63
			# days of full frames on a 100Mb network
			#set target_payload_size		[expr {1447 - 10}]
			#set target_payload_size			8937

			set target_payload_size			4076
			#set target_payload_size			131009
			#set target_payload_size			1048576

			#set target_payload_size	8
		}

		#>>>
		destructor { #<<<
			my closed

			if {[self next] ne {}} {next}
		}

		#>>>

		method attach {con} { #<<<
			set rawcon	$con

			if {$write_combining} {
				oo::objdefine $rawcon forward writable \
						{*}[namespace code {my _rawcon_writable_combining}]
			} else {
				oo::objdefine $rawcon forward writable \
						{*}[namespace code {my _rawcon_writable}]
			}
			oo::objdefine $rawcon forward received \
					{*}[namespace code {my _receive_raw}]
			oo::objdefine $rawcon forward closed \
					{*}[namespace code {my _rawcon_closed}]
		}

		#>>>
		method con {} { #<<<
			if {![info exists rawcon]} {
				throw {not_attached} "Not attached to a con"
			}

			return $rawcon
		}

		#>>>

		method assign {msg args} { # returns queue name to enqueue $msg to <<<
			return "_fifo"
		}

		#>>>
		method enqueue {msg args} { #<<<
			set msgid		[incr msgid_seq]
			set emsg		[encoding convertto utf-8 $msg]
			if {
				[dict size $queues] == 0 &&
				![info exists next_frag] &&
				[string length $emsg] <= $target_payload_size &&
				[my shortcut_ok {*}$args]
			} {
				# Optimize the 90% case of a small message with empty queues
				# we assume the rawcon is writable because the queues were empty
				my sent {*}$args
				$rawcon send "$msgid 1 [string length $emsg]\n$emsg"
				?? {log debug "Followed shortcut path"}
				return
			}
			set target	[my assign $msg {*}$args]
			dict lappend queues $target [list $msgid $emsg $args 0]
			#dict lappend queues $target [list $msgid [zlib deflate [encoding convertto utf-8 $msg] 3]]
			$rawcon data_waiting 1
			set target
		}

		#>>>
		method shortcut_ok args {return 0}
		method pick a_queues { # returns the queue to dequeue a msg from <<<
			# Default behaviour: roundrobin of queues
			set new_roundrobin	{}

			# Trim queues that have gone away
			foreach queue $roundrobin {
				if {$queue ni $a_queues} continue
				lappend new_roundrobin $queue
			}

			# Append any new queues to the end of the roundrobin
			foreach queue $a_queues {
				if {$queue in $new_roundrobin} continue
				lappend new_roundrobin $queue
			}

			# Pull the next queue off head and add it to the tail
			set roundrobin	[lassign $new_roundrobin next]
			lappend roundrobin	$next

			set next
		}

		#>>>
		method dequeue {max_payload} { # returns a {msgid is_tail fragment} <<<
			?? {
				set times	{}
				set last	[clock microseconds]
			}
			if {[info exists next_frag]} {
				?? {log debug "Using next_frag"}
				if {[dict size $queues] == 0} {
					?? {log debug "next_frag Queues empty, flagging data_waiting 0"}
					$rawcon data_waiting 0
					#?? {lappend times notify_data_waiting_0  [- [set tmp [clock microseconds]] $last]; set last $tmp}
				}
				return $next_frag[unset next_frag]
			}
			if {[dict size $queues] == 0} {
				$rawcon data_waiting 0
				throw {queue_empty} ""
			}
			?? {lappend times test_empty [- [set tmp [clock microseconds]] $last]; set last $tmp}

			set source	[my pick [dict keys $queues]]
			?? {lappend times pick [- [set tmp [clock microseconds]] $last]; set last $tmp}

			set new	[lassign [dict get $queues $source] next]

			lassign $next msgid msg msgargs ofs
			?? {lappend times pull_next  [- [set tmp [clock microseconds]] $last]; set last $tmp}
			if {[string length $msg] - $ofs > $max_payload} {
				set is_tail	0

				set fragment		[string range $msg $ofs [+ $ofs $max_payload -1]]
				set new	[linsert $new[unset new] 0 [list $msgid $msg $msgargs [+ $ofs $max_payload]]]
			} else {
				set is_tail	1

				my sent {*}$msgargs

				set fragment		[string range $msg $ofs end]
			}
			?? {lappend times frag_handler  [- [set tmp [clock microseconds]] $last]; set last $tmp}

			if {[llength $new] > 0} {
				dict set queues $source $new
			} else {
				dict unset queues $source
			}
			?? {lappend times update_queues_state  [- [set tmp [clock microseconds]] $last]; set last $tmp}
			if {!$prequeueing} {
				if {[dict size $queues] == 0} {
					?? {log debug "Queues empty, flagging data_waiting 0"}
					$rawcon data_waiting 0
					#?? {lappend times notify_data_waiting_0  [- [set tmp [clock microseconds]] $last]; set last $tmp}
				}
			}
			#?? {log debug "dequeue times: $times\nreturning: msgid: $msgid, tail: $is_tail, fragment: ($fragment)"}
			?? {log debug "dequeue times: $times"}
			list $msgid $is_tail $fragment
		}

		#>>>
		method sent {args} { #<<<
		}

		#>>>
		method receive {msg} { #<<<
		}

		#>>>
		method closed {} { #<<<
		}

		#>>>
		method _receive_fragment {msgid is_tail fragment} { #<<<
			dict append defrag_buf $msgid $fragment
			if {$is_tail == 1} {
				set complete	[dict get $defrag_buf $msgid]
				dict unset defrag_buf $msgid
				#my receive [encoding convertfrom utf-8 [zlib inflate $complete]]
				my receive [encoding convertfrom utf-8 $complete]
				#my receive $complete
			}
		}

		#>>>
		method _new_receive_raw {msg} { #<<<
			set p	0
			while {$p < [string length $msg]} {
				#puts "start: ([string range $msg $p [+ $p 40]])"
				scan [string range $msg $p end] "%lld %1d %ld\n%n" \
						msgid is_tail fragment_len datastart
				incr datastart	$p
				set p	[+ $datastart $fragment_len]
				my _receive_fragment $msgid $is_tail \
						[string range $msg $datastart [- $p 1]]
			}
		}

		#>>>
		method _receive_raw {msg} { #<<<
			set p	0
			while {$p < [string length $msg]} {
				set idx		[string first "\n" $msg $p]
				lassign [string range $msg $p [- $idx 1]] \
						msgid is_tail fragment_len
				set p		[+ $idx $fragment_len 1]
				my _receive_fragment $msgid $is_tail \
						[string range $msg [+ $idx 1] [- $p 1]]
			}
		}

		#>>>
		method _rawcon_closed {} { #<<<
			my destroy
		}

		#>>>
		method _rawcon_writable_combining {} { #<<<
			set remaining_target	$target_payload_size
			set payload				""

			set c	0
			while {[$rawcon is_data_waiting] && $remaining_target > 0} {
				lassign [my dequeue $remaining_target] \
						msgid is_tail fragment

				set fragment_len	[string length $fragment]
				incr remaining_target -$fragment_len
				append payload	"$msgid $is_tail $fragment_len\n$fragment"
				incr c
				if {[dict size $queues] == 0} {
					$rawcon data_waiting 0
					break
				}
			}

			if {[string length $payload] > 0} {
				$rawcon send $payload
			}
		}

		#>>>
		method _rawcon_writable {} { #<<<
			?? {log debug "_rawcon_writable [self]"}
			lassign [my dequeue $target_payload_size] \
					msgid is_tail fragment
			#?? {log debug "_rawcon_writable [self], got dequeue"}
			$rawcon send "$msgid $is_tail [string length $fragment]\n$fragment"
			if {$prequeueing} {
				if {[dict size $queues] > 0} {
					# Prepare the next fragment
					?? {log debug "queue size: [dict size $queues], preparing next_frag"}
					set qs_was	[dict size $queues]
					set next_frag	[my dequeue $target_payload_size]
					?? {log debug "after next_frag prep, queue size: [dict size $queues]"}
				} else {
					$rawcon data_waiting 0
				}
			}
		}

		#>>>
		method intersect3 {list1 list2} { #<<<
			set firstonly		{}
			set intersection	{}
			set secondonly		{}

			set list1	[lsort -unique $list1]
			set list2	[lsort -unique $list2]

			foreach item $list1 {
				if {[lsearch -sorted $list2 $item] == -1} {
					lappend firstonly $item
				} else {
					lappend intersection $item
				}
			}

			foreach item $list2 {
				if {[lsearch -sorted $intersection $item] == -1} {
					lappend secondonly $item
				}
			}

			list $firstonly $intersection $secondonly
		}

		#>>>
	}
}
