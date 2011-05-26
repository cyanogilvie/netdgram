# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

# Aims to be RFC2396 compliant

namespace eval netdgram {
	namespace path ::oo

	# The reason that this is here is so that the sets, lists and charmaps
	# are generated only once, making the instantiation of uri objects much
	# lighter
	variable uri_common	[dict create \
		reserved {
			; / ? : @ & = + $ ,
		} \
		lowalpha {
			a b c d e f g h i j k l m n o p q r s t u v w x y z
		} \
		upalpha {
			A B C D E F G H I J K L M N O P Q R S T U V W X Y Z
		} \
		digit {
			0 1 2 3 4 5 6 7 8 9
		} \
		mark {
			- _ . ! ~ * ' ( )
		} \
		alpha		{} \
		alphanum	{} \
		unreserved	{} \
		charmap		{} \
	]

	dict with uri_common {
		set alpha		[concat $lowalpha $upalpha]
		set alphanum	[concat $alpha $digit]
		set unreserved	[concat $alphanum $mark]
	}
}

oo::class create netdgram::uri {
	mixin netdgram::debug

	variable {*}{
		charmap
		parts
		cached_encoding
	}

	constructor {uri_encoded {encoding "utf-8"}} { #<<<
		if {[self next] ne {}} {next}

		if {[llength [dict get $::netdgram::uri_common charmap]] == 0} {
			my _generate_charmap
		}
		set charmap	[dict get $::netdgram::uri_common charmap]
		my _parseuri $uri_encoded $encoding
	}

	#>>>

	method type {} { #<<<
		expr {
			[dict exists $parts scheme] &&
			[dict get $parts scheme] ne ""
			? "absolute" : "relative"
		}
	}

	#>>>
	method as_dict {} { #<<<
		set parts
	}

	#>>>
	method set_part {part newvalue} { #<<<
		if {$part ni {
			scheme
			authority
			path
			query
			fragment
		}} {
			error "Invalid URI part \"$part\""
		}

		if {$newvalue ne [dict get $parts $part]} {
			if {[info exists cached_encoding]} {unset cached_encoding}
			dict set parts $part $newvalue
		}
	}

	#>>>
	method encoded {{encoding "utf-8"}} { #<<<
		if {![info exists cached_encoding]} {
			if {[dict get $parts scheme] ne ""} {
				# is absolute
				set scheme	[my _hexhex_encode [encoding convertto $encoding [string tolower [dict get $parts scheme]]]]
				set authority	[my _hexhex_encode [encoding convertto $encoding [string tolower [dict get $parts authority]]] ":"]
			}
			if {[dict get $parts path] eq ""} {
				set path	"/"
			} else {
				set path	[dict get $parts path]
			}
			set path	[my _hexhex_encode [encoding convertto $encoding $path] "/"]
			if {[dict size [dict get $parts query]] == 0} {
				set query	""
			} else {
				set query	"?[my query_encode [dict get $parts query]]"
			}

			if {[dict get $parts fragment] eq ""} {
				set fragment	""
			} else {
				set fragment	"#[my _hexhex_encode [encoding convertto $encoding [dict get $parts fragment]]]"
			}

			if {[dict get $parts scheme] eq ""} {
				# is relative
				set cached_encoding "${path}${query}${fragment}"
			} else {
				# is absolute
				set cached_encoding	"${scheme}://${authority}${path}${query}${fragment}"
			}
		}

		set cached_encoding
	}

	#>>>
	method query_decode {query {encoding "utf-8"}} { #<<<
		set build	[dict create]
		foreach term [split $query &] {
			# Warning: doesn't check for less or more than 1 "="
			lassign [split $term =] key val
			dict set build [my _urldecode $key $encoding] [my _urldecode $val $encoding]
		}
		set build
	}

	#>>>
	method query_encode {query {encoding "utf-8"}} { #<<<
		set terms	{}
		dict for {key value} $query {
			set ekey	[my _hexhex_encode [encoding convertto $encoding $key]]
			set evalue	[my _hexhex_encode [encoding convertto $encoding $value]]
			lappend terms	"${ekey}=${evalue}"
		}
		join $terms &
	}

	#>>>

	method _parseuri {uri {encoding "utf-8"}} { #<<<
		if {[info exists cached_encoding]} {unset cached_encoding}
		# Regex from RFC2396
		if {![regexp {^(([^:/?#]+)://)?(([^/?#]*))?([^?#]*)(\?([^#]*))?(#(.*))?} $uri x x1 scheme x2 authority path x3 query x4 fragment]} {
			throw [list invalid_uri $uri] "Invalid URI"
		}

		set parts	[dict create \
				scheme		[my _urldecode [string tolower $scheme] $encoding] \
				authority	[my _urldecode [string tolower $authority] $encoding] \
				path		[my _urldecode $path $encoding] \
				query		[my query_decode $query $encoding] \
				fragment	[my _urldecode $fragment $encoding] \
		]

		set parts
	}

	#>>>
	method _urldecode {data {encoding "utf-8"}} { #<<<
		regsub -all {([][$\\])} $data {\\\1} data
		regsub -all {%([0-9a-fA-F][0-9a-fA-F])} $data  {[binary format H2 \1]} data
		encoding convertfrom $encoding [subst $data]
	}

	#>>>
	method _generate_charmap {} { #<<<
		set charmap	{}
		dict with ::netdgram::uri_common {
			for {set i 0} {$i < 256} {incr i} {
				set c	[binary format c $i]
				if {$c in $unreserved} {
					lappend charmap	$c
				} else {
					lappend charmap	[format "%%%02X" $i]
				}
			}
		}

		dict set ::netdgram::uri_common charmap $charmap
	}

	#>>>
	method _hexhex_encode {data {exceptions ""}} { #<<<
		binary scan $exceptions c* elist
		binary scan $data c* byteslist
		set out	""
		foreach byte $byteslist {
			set byte	[expr {$byte & 0xff}]	;# convert to unsigned
			if {$byte in $elist} {
				append out	[format %c $byte] 
			} else {
				append out	[lindex $charmap $byte]
			}
		}
		set out
	}

	#>>>
}
