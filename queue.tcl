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
		}

		constructor {} { #<<<
			if {[self next] ne {}} {next}
			set queues		[dict create]
			set defrag_buf	[dict create]
			set msgid_seq	0
			set target_payload_size		10000
			set roundrobin				{}
			#set target_payload_size	1400
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

			oo::objdefine $rawcon forward writable \
					{*}[namespace code {my _rawcon_writable}]
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
			set target	[my assign $msg {*}$args]

			set msgid		[incr msgid_seq]
			#dict lappend queues $target [list $msgid [zlib deflate [encoding convertto utf-8 $msg] 3]]
			dict lappend queues $target [list $msgid [encoding convertto utf-8 $msg] $args]
			$rawcon data_waiting 1
			return $target
		}

		#>>>
		method pick {queues} { # returns the queue to dequeue a msg from <<<
			# Default behaviour: roundrobin of queues
			set new_roundrobin	{}

			# Trim queues that have gone away
			foreach queue $roundrobin {
				if {$queue ni $queues} continue
				lappend new_roundrobin $queue
			}

			# Append any new queues to the end of the roundrobin
			foreach queue $queues {
				if {$queue in $new_roundrobin} continue
				lappend new_roundrobin $queue
			}

			# Pull the next queue off head and add it to the tail
			set roundrobin	[lassign $new_roundrobin next]
			lappend roundrobin	$next

			return $next
		}

		#>>>
		method dequeue {max_payload} { # returns a {msgid is_tail fragment} <<<
			if {[dict size $queues] == 0} {
				throw {queue_empty} ""
			}

			set source	[my pick [dict keys $queues]]

			set new	[lassign [dict get $queues $source] next]

			lassign $next msgid msg msgargs
			if {$max_payload < [string length $msg]} {
				set is_tail	0

				set fragment		[string range $msg 0 $max_payload-1]
				set remaining_msg	[string range $msg $max_payload end]
				set new	[linsert $new 0 [list $msgid $remaining_msg]]
			} else {
				set is_tail	1

				my sent {*}$msgargs

				set fragment		$msg
			}

			if {[llength $new] > 0} {
				dict set queues $source $new
			} else {
				dict unset queues $source
			}
			if {[dict size $queues] == 0} {
				$rawcon data_waiting 0
			}
			return [list $msgid $is_tail $fragment]
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
			}
		}

		#>>>
		method _receive_raw {msg} { #<<<
			set p	0
			while {$p <= [string length $msg]} {
				set idx	[string first "\n" $msg $p]
				set head	[string range $msg $p $idx-1]
				lassign $head msgid is_tail fragment_len
				set end_idx	[expr {$idx + $fragment_len + 1}]
				set frag	[string range $msg $idx+1 $end_idx]
				set p		[expr {$end_idx + 1}]
				my _receive_fragment $msgid $is_tail $frag
			}
		}

		#>>>
		method _rawcon_closed {} { #<<<
			my destroy
		}

		#>>>
		method _rawcon_writable {} { #<<<
			set remaining_target	$target_payload_size

			try {
				lassign [my dequeue $remaining_target] \
						msgid is_tail fragment

				set fragment_len	[string length $fragment]
				set payload_portion	"$msgid $is_tail $fragment_len\n$fragment"
				incr remaining_target -$fragment_len
				append payload	$payload_portion

				$rawcon send $payload
			} trap {queue_empty} {} {
				return
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

			return [list $firstonly $intersection $secondonly]
		}

		#>>>
	}
}
