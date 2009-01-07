#!/usr/bin/env tclsh

set sourcefiles	[lindex $argv 0]
set destpath	[lindex $argv 1]
set ver			[lindex $argv 2]

foreach file [glob -nocomplain -type f $sourcefiles] {
	set basename	[file rootname [file tail $file]]
	set new			[file join $destpath "${basename}-${ver}.tm"]
	file copy $file $new
}

