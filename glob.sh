#! /bin/sh

if [ $# -eq 0 -o "$1" = '-h' -o "$1" = '--help' ]; then
	cat - 1>& 2 <<- EOF
		Usage: glob [ -C DIR ] PATTERN...

		Expand glob PATTERN

			-h, --help                 give this help
			-C, --directory=DIR        change to directory DIR

		Quote PATTERNs to prevent expanded too early

EOF
else
	wd=''

	case "$1" in
		-C)
			wd="$2"
			wd="${wd%/}/"

			shift && shift
		;;
		--directory*)
			wd="${1#--directory=}"
			wd="${wd%/}/"

			shift
		;;
	esac

	# glob always expands in current working
	# directory so we fork a child shell
	(
		cd "$wd" || return $?

		# glob expanded here
		for file in $@; do
			# Skip glob failed expanding
			if [ -e "$file" ]; then
				echo "$wd$file"
			fi
		done
	)
fi
