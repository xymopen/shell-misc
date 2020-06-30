#! /bin/sh

# The script is based on https://sam.hooke.me/note/2018/08/installing-rpms-offline-using-a-local-yum-repository/

# See https://www.etalabs.net/sh_tricks.html
escape() {
	printf "'%s'" "$(printf "%s" "$1" | sed -e "s/'/'\"'\"'/g" -)";
}

_colorLog() {
    local WHITE='37m' RESET='0m'

	# `echo' interpreting backslash escapes is not portable, use `printf' instead
	# See https://unix.stackexchange.com/questions/168095/how-do-i-print-e-with-echo/168137#168137
	printf '%b' "\033[${1:-$WHITE}" 1>& 2

    shift 1

    if [ $# -gt 0 ]; then
        echo "$@" 1>& 2
    else
        cat - 0<& 0 1>& 2
    fi

	printf '%b' "\033[$RESET" 1>& 2
}

logger() {
    local RED='31m' GREEN='32m' YELLOW='33m' BLUE='36m' WHITE='37m'
    local level=$1
    local min_level=$2

	shift 2

    case "$min_level" in
        debug)
            if [                      \
                "$level" = 'debug'    \
            ]; then
                _colorLog "$BLUE" "$@" 0<& 0
            fi
        ;;
        info)
            if [                      \
                "$level" = 'info'  -o \
                "$level" = 'debug'    \
            ]; then
                _colorLog "$WHITE" "$@" 0<& 0
            fi
        ;;
        warn)
            if [                      \
                "$level" = 'warn'  -o \
                "$level" = 'info'  -o \
                "$level" = 'debug'    \
            ]; then
                _colorLog "$YELLOW" "$@" 0<& 0
            fi
        ;;
        error)
            if [                      \
                "$level" = 'error' -o \
                "$level" = 'warn'  -o \
                "$level" = 'info'  -o \
                "$level" = 'debug'    \
            ]; then
                _colorLog "$RED" "$@" 0<& 0
            fi
        ;;
    esac
}

archive() {
	local SED_PROG_FIND_DIST_ROVER_PKG='
		b main

		:end {
			p
			q
		}

		:main
		/^\[(.+)\]$/ {
			h
		}

		/^distroverpkg=/ {
			G
			s/^distroverpkg=(.+)\n\[main\]$/\1/
			t end
		}

		$ {
			q1
		}
	'

	local SED_PROG_FIND_RELEASE_VER='
		b main

		:end
		q

		:main
		s/^system-release\(releasever\)\s*=\s*(\S+)\s*/\1/p
		t end

		$ {
			q1
		}
	'

	local DBG_LEVEL='info'
	local SW_HELP=1
    local OPT_DOWNLOAD_DIR
    local OPT_INSTALL_ROOT='/var/lib/yum-archiver/install-root'
	local OPT_RELEASE_VER=''
	local OPT_ARGS=''
	local OPT_PKGS=''

	while [ $# -gt 0 ]; do
		case "$1" in
			-h|--help)
				SW_HELP=0
			;;
			-v|--verbose)
				DBG_LEVEL='debug'
			;;
			--installroot=*)
				OPT_INSTALL_ROOT="$(realpath "${1#--installroot=}")"
			;;
			--downloaddir=*)
				OPT_DOWNLOAD_DIR="$(realpath "${1#--downloaddir=}")"
			;;
			--releasever=*)
				OPT_RELEASE_VER="${1#--releasever=}"
			;;
			-*|--*)
				if [ -z "$OPT_ARGS" ]; then
					OPT_ARGS="$(escape "$1")"
				else
					OPT_ARGS="$OPT_ARGS $(escape "$1")"
				fi
			;;
			*)
				if [ -z "$OPT_PKGS" ]; then
					OPT_PKGS="$(escape "$1")"
				else
					OPT_PKGS="$OPT_PKGS $(escape "$1")"
				fi
			;;
		esac

		shift 1
	done

	if [ "$SW_HELP" = "0" ]; then
		logger "$DBG_LEVEL" info <<- "EOF"
			yum-archiver [options] [ARGS...] PKGS...

			Options:
			  -h, --help            show this help message and exit
			  -v, --verbose         verbose operation
			  --installroot=[path]  set install root
			  --releasever=RELEASEVER
			                        set value of $releasever in yum config and repo files
			  --downloaddir=DLDIR   specifies an alternate directory to store packages
			                        set to an existing repository to append packages

			ARGS will be passed to `yum install'

EOF
	else
		if ! rpm --query --quiet rpm 1>& - 2>& -; then
			logger "$DBG_LEVEL" error '`rpm'"'"' is not installed'
			return 2
		fi

		if ! rpm --query --quiet yum; then
			logger "$DBG_LEVEL" error '`yum'"'"' is not installed'
			return 2
		fi

		# On dnf-enableded system createrepo is replaced by createrepo_c
		if ! rpm --query --quiet "$(rpm --query --whatprovides createrepo)"; then
			logger "$DBG_LEVEL" error '`createrepo'"'"' was not installed'
			logger "$DBG_LEVEL" info 'Install `createrepo'"'"' by `yum install -y createrepo'"'"
			return 2
		fi

		if ! \
			yum help | grep -q -- '--downloadonly'      || \
			rpm --query --quiet yum-plugin-downloadonly || \
			rpm --query --quiet yum-downloadonly
		then
			logger "$DBG_LEVEL" error 'yum does not support `--downloadonly'"'"' option'
			logger "$DBG_LEVEL" info << "EOF"
				*) Upgrade yum
				*) Install `yum-plugin-downloadonly' plugin by `yum install -y yum-plugin-downloadonly'
				*) Install `yum-downloadonly' plugin by `yum install -y yum-downloadonly'
EOF
			return 38
		fi

		if [ -z "$OPT_RELEASE_VER" ]; then
			# Since no package is installed and no /etc/yum.conf
			# is present at $OPT_INSTALL_ROOT, yum cannot determine
			# the $releasever variable, so it is necessary to
			# duplicate yum's logics which can be found at
			# https://github.com/rpm-software-management/yum/tree/master/yum/config.py
			local distroverpkg distroverpkg_info

			if ! distroverpkg="$(sed -nre "$SED_PROG_FIND_DIST_ROVER_PKG" '/etc/yum.conf')"; then
				if ! distroverpkg="$(rpm --query --whatprovides "system-release(releasever)")"; then
					distroverpkg='redhat-release'
				fi
			fi

			if distroverpkg_info="$(rpm --query --provides "$distroverpkg")"; then
				OPT_RELEASE_VER="$(echo -n "$distroverpkg_info" | sed -nre "$SED_PROG_FIND_RELEASE_VER")"
			else
				OPT_RELEASE_VER='$releasever'
			fi
		fi

		if tty -s; then
			logger "$DBG_LEVEL" debug 'Interactive shell'

			if [ -z "$OPT_DOWNLOAD_DIR" ]; then
				read -ep 'Where do you want to save the repository: ' 'OPT_DOWNLOAD_DIR'
			fi

			if [ -z "$OPT_PKGS" ]; then
				local pkg

				while read -ep 'Which package wouuld you like to archive (Leave empty to finish submission): ' 'pkg' && [ -n "$pkg" ]; do
					if [ -z "$OPT_PKGS" ]; then
						OPT_PKGS="$(escape "$pkg")"
					else
						OPT_PKGS="$OPT_PKGS $(escape "$pkg")"
					fi
				done
			fi
		else
			logger "$DBG_LEVEL" debug 'Non-interactive shell'
		fi

		logger "$DBG_LEVEL" debug 'DIST_ROVER_PKG =' "$distroverpkg"
		logger "$DBG_LEVEL" debug 'OPT_DOWNLOAD_DIR =' "$OPT_DOWNLOAD_DIR"
		logger "$DBG_LEVEL" debug 'OPT_INSTALL_ROOT =' "$OPT_INSTALL_ROOT"
		logger "$DBG_LEVEL" debug 'OPT_RELEASE_VER =' "$OPT_RELEASE_VER"
		logger "$DBG_LEVEL" debug 'OPT_ARGS =' "$OPT_ARGS"
		logger "$DBG_LEVEL" debug 'OPT_PKGS =' "$OPT_PKGS"

		if [ -z "$OPT_DOWNLOAD_DIR" ]; then
			logger "$DBG_LEVEL" error '`--downloaddir'"'"' is not provided'
			return 1
		fi

		if [ -z "$OPT_PKGS" ] && tty -s; then
			logger "$DBG_LEVEL" error 'no packages to archive'
			return 1
		fi

		mkdir -p "$OPT_DOWNLOAD_DIR" "$OPT_INSTALL_ROOT" 1>& - 2>& -

		logger "$DBG_LEVEL" debug 'Execute' "yum install $OPT_ARGS --downloadonly --installroot=$(escape "$OPT_INSTALL_ROOT")" \
			"--downloaddir=$(escape "$OPT_DOWNLOAD_DIR") --releasever='$OPT_RELEASE_VER' $OPT_PKGS"

		eval "yum install $OPT_ARGS -y --downloadonly --installroot=$(escape "$OPT_INSTALL_ROOT")" \
			"--downloaddir=$(escape "$OPT_DOWNLOAD_DIR") --releasever='$OPT_RELEASE_VER' $OPT_PKGS"

		local errno=$?

		createrepo --database "$OPT_DOWNLOAD_DIR" --update

		return $errno
	fi
}

archive "$@"
