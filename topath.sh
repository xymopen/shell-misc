#! /bin/sh

if [ "$1" = '-h' -o "$1" = '--help' ]; then
	cat - 1>& 2 <<- "EOF"
		Usage: topath [ DELIM ] [ FILE ]...

		Concat elements from FILE by DELIM
		By default print STDIN in $PATH format

EOF
else
	delim="${1:-:}"
	ret=""

	for i in $(cat "${2:--}"); do
		ret="${ret}${delim}${i}"
	done

	# Remove leading delimiter
	echo "${ret#${delim}}"
fi
