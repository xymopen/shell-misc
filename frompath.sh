#! /bin/sh

if [ "$1" = '-h' -o "$1" = '--help' ]; then
	cat - 1>& 2 <<- "EOF"
		Usage: frompath [ VALUE ] [ DELIM ]

		Split VALUE by DELIM
		By default print directories in $PATH

EOF
else
	IFS="${2:-:}"

	for i in ${1:-$PATH}; do
		echo "$i"
	done
fi
