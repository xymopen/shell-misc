#! /bin/sh

if [ "$1" = '-h' -o "$1" = '--help' ]; then
	cat - 1>& 2 <<- EOF
		Usage: findclass CLASS

		Find Java class in CLASSPATH

EOF
else
	# For Bash just use "${1//.//}.class"
	SED_PROG='
		s/\./\//g;
		s/$/\.class/;
	'

	AWK_PROG='
		BEGIN { retv = 1; }
		$4 == clzfile { retv = 0; }
		END { exit retv; }
	'

	clzfile="$(echo -n "$1" | sed -e "$SED_PROG" -)"

	IFS=":"

	for path in ${CLASSPATH:-.}; do
		if [ -d "$path" ]; then
			if [ -f "$path/$clzfile" ]; then
				echo "$path/$clzfile"

				return
			fi
		elif [ -f "$path" ]; then
			case "$path" in
				*.jar|*.zip)
					if unzip -lqq "$path" | awk -v "clzfile=$clzfile" -e "$AWK_PROG" -; then
						echo "$path"

						return
					fi
			esac
		fi
	done

	return 1
fi
