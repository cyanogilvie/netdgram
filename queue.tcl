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

			# worked out to 1500 MTU and msgid up to 9,999,999,999 or 14.63
			# days of full frames on a 100Mb network
			set target_payload_size		[expr {1447 - 10}]

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
			set target	[my assign $msg {*}$args]

			set msgid		[incr msgid_seq]
			#dict lappend queues $target [list $msgid [zlib deflate [encoding convertto utf-8 $msg] 3]]
			dict lappend queues $target [list $msgid [encoding convertto utf-8 $msg] $args]
			#dict lappend queues $target [list $msgid $msg $args]
			$rawcon data_waiting 1
			set target
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
				$rawcon data_waiting 0
				throw {queue_empty} ""
			}

			set source	[my pick [dict keys $queues]]

			set new	[lassign [dict get $queues $source] next]

			lassign $next msgid msg msgargs
			if {$max_payload < [string length $msg]} {
				set is_tail	0

				set fragment		[string range $msg 0 [- $max_payload 1]]
				set remaining_msg	[string range $msg $max_payload end]
				set new	[linsert $new[unset new] 0 [list $msgid $remaining_msg $msgargs]]
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
			}

			if {[string length $payload] > 0} {
				$rawcon send $payload
			}
		}

		#>>>
		method _rawcon_writable {} { #<<<
			lassign [my dequeue $target_payload_size] \
					msgid is_tail fragment
			$rawcon send "$msgid $is_tail [string length $fragment]\n$fragment"
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
