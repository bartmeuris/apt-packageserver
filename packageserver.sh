#!/bin/bash
#############################################################################
## Package server script
##
#############################################################################
#
# To add the repository: 
#   wget -q -O - http://localhost/apt/conf/packages@intoit.be.gpg.key | sudo apt-key add -
#   sudo echo "deb http://localhost/apt/ precise main" > /etc/apt/sources.list.d/00-intoit.list
# 

#############################################################################
# Generic settings
#############################################################################

# Incoming dir
INCOMINGDIR="${HOME}/apt-incoming"

# Archive dir. If not defined, the files are removed - has to be writable by the user!
ARCHDIR="${INCOMINGDIR}/archive"

# The repository root directory (browsable using a web-server, writable by package generation user)
TARGETDIR="${HOME}/apt"

# Debian repository 
DEB_ORIGIN="Origin name"
DEB_EMAIL="packages@packageserver.com"
DEB_LABEL="samplelabel"
DEB_DESCRIPTION="test packages server"

# List of all repositories you want to support
#DEB_DISTRIBS="precise futuredistrib"
DEB_DISTRIBS=

# List of all architectures you want to support
#DEB_ARCHS="amd64 i386"
DEB_ARCHS=""

#DEB_COMPONENTS="main"
DEB_COMPONENTS=

# Optional GPG options
GPG_KEYLEN=2048
GPG_OPTS=

# Don't generate key by default
GENERATE_KEY=
# Signing is mandatory by default. Clear if not needed
MANDATORY_SIGN=1
#############################################################################
# Load optional config files
[ -f "/etc/default/packageserver" ] && . /etc/default/packageserver
[ -f "${HOME}/.packageserver" ] && . ${HOME}/.packageserver
#############################################################################

CMD=$0
function showhelp
{
	echo "Usage $CMD <options>"
	cat <<EOF
	-g|--generategpg:
		Generate a GPG key for this server if required and exit.
	-h|--help
		Show this message and exit.
EOF
}

function info
{
	echo "INFO : $*"
}

function warn
{
	echo "WARN : $*"
}

function error
{
	echo "ERROR: $*"
}

function abort
{
	if [ -n "$*" ]; then
		error "$*"
	fi
	echo "Aborting..."
	exit 0
}

while [ 1 ]; do
	if [ "`echo $1 | sed -e "s/^-.*/OK/g"`" != "OK" ]; then
		break;
	fi
	OPT=$1
	shift 1
	case "$OPT" in
		-h|--help)
			showhelp
			exit 0
			;;
		-g|--generategpg)
			GENERATE_KEY=1
			;;
		*)
	esac
done

#############################################################################
# Basic check
if [ ! -d "$TARGETDIR" ]; then
	mkdir -p "$TARGETDIR/$SUBDIR" || abort "Could not create target directory '${TARGETDIR}' !"
fi
[ ! -w "${TARGETDIR}" ] && abort "Target directory '${TARGETDIR}' is not writable for current user!"
TSUBDIRS="conf dists incoming indices logs pool project project tmp"
for SUBDIR in $TSUBDIRS; do
	[ ! -d "$TARGETDIR/$SUBDIR" ] && mkdir -p "$TARGETDIR/$SUBDIR"
done

#############################################################################

# The ASCII pubkey is exported here with the name "${DEB_ORIGIN}.gpg.key"
[ -z "${KEYPATH}" ] && KEYPATH="${TARGETDIR}/conf"

#########################################
## Install required packages if needed

sudo -n ls / 2>&1 > /dev/null
NO_SUDO=$?

INSTPKG=
[ -z `which dpkg-sig` ] && INSTPKG="$INSTPKG dpkg-sig"
[ -z `which reprepro` ] && INSTPKG="$INSTPKG reprepro"

if [ -n "${INSTPKG}" ]; then
	abort "The following required packages don't seem to be installed: ${INSTPKG}"
fi


#########################################
## Generate GPG key if required

DEB_SIGNID=`gpg $GPG_OPTS --list-keys "${DEB_ORIGIN}" 2>/dev/null | grep "^sub" | sed -e 's/^sub.*\/\([0-9A-Za-z]*\).*$/\1/'`
if [ -n "${GENERATE_KEY}" ]; then
	if [ -z "${DEB_SIGNID}" ]; then
		## Generate GPG key if needed
		if [ `cat /proc/sys/kernel/random/entropy_avail` -lt 300 ]; then
			error "Not enough entropy (we have `cat /proc/sys/kernel/random/entropy_avail`, minimum 300 required) to generate a GPG key."
			error "You can generate more entropy mouse/keyboard input on the physical machine or by generating i/o"
			error ""
			error "For virtual machines this can be problematic, since they have few valid entropy sources."
			error "To circumvent this, you could install/run one of the following packages:"
			error "  - haveged (recommended if needed)"
			error "  - rng-tools (using /dev/urandom is NOT secure but works for testing)"
			error "Note that using these has security implications recarding key-strenght, so make sure you know what you're doing."
			error ""
			error "Another sollution is to generate a GPG key+subkey for '${DEB_ORIGIN}' on another machine and import them in your keyring manually."
			abort
		fi
		
		# Generate the key
		gpg --batch --gen-key 2>&1 > /dev/null <<EOF
		Key-Type: RSA
		Key-Length: ${GPG_KEYLEN}
		Subkey-Type: RSA
		Subkey-Length: ${GPG_KEYLEN}
		Name-Real: ${DEB_ORIGIN}
		Name-Comment: ${DEB_DESCRIPTION}
		Name-Email: ${DEB_ORIGIN}
		Expire-Date: 0
		%no-ask-passphrase
		%commit
EOF
		echo "Key generation finished."
	else
		echo "Key already existed. Skipping..."
	fi
	exit 0
elif [ -n "${GENERATE_KEY}" ] && [ -n "${DEB_SIGNID}" ]; then
	echo "INFO: Key generation skipped: key for ${DEB_ORIGIN} already found: ${DEB_SIGNID}"
fi
DEB_SIGNID=`gpg ${GPG_OPTS} --list-keys "${DEB_ORIGIN}" 2>/dev/null | grep "^sub" | sed -e 's/^sub.*\/\([0-9A-Za-z]*\).*$/\1/'`

#########################################
## Export the GPG key if required

if [ -n "$DEB_SIGNID" ]; then
	[ ! -d "${KEYPATH}" ] && mkdir -p "${KEYPATH}"
	if [ ! -f "${KEYPATH}/${DEB_ORIGIN}.gpg.key" ]; then
		echo "Exporting key..."
		# export gpg key in ascii format
		gpg ${GPG_OPTS} --armor --export ${DEB_ORIGIN} 2>/dev/null > ${KEYPATH}/${DEB_ORIGIN}.gpg.key
	fi
elif [ -n "${MANDATORY_SIGN}" ]; then
	abort "Signing key not available -- package signing disabled, use -g to generate GPG key"
else
	warn "Signing key not available -- package signing disabled, use -g to generate GPG key"
fi

for DEB_DIST in $DEB_DISTRIBS; do
	info "## Processing distribution ${DEB_DIST}"
	if [ ! -d "${TARGETDIR}/dists/${DEB_DIST}" ]; then
		# Distribution directory missing: add distribution to config file
		echo "Origin: ${DEB_ORIGIN}" >> "$TARGETDIR/conf/distributions"
		echo "Label: ${DEB_LABEL}" >> "$TARGETDIR/conf/distributions"
		echo "Codename: ${DEB_DIST}" >> "$TARGETDIR/conf/distributions"
		echo "Architectures: ${DEB_ARCHS}" >> "$TARGETDIR/conf/distributions"
		echo "Components: ${DEB_COMPONENTS}" >> "$TARGETDIR/conf/distributions"
		echo "Description: ${DEB_DESCRIPTION}" >> "$TARGETDIR/conf/distributions"
		echo "SignWith: ${DEB_SIGNID}" >> "$TARGETDIR/conf/distributions"
		echo "Pull: ${DEB_DIST}" >> "$TARGETDIR/conf/distributions"
		echo "" >> "$TARGETDIR/conf/distributions"
	fi
	info "Checking distribution repository..."
	reprepro -b "${TARGETDIR}" check "${DEB_DIST}"

	# Get the debian files from the incoming directory.
	# The "all" directory and the incoming directory itself are used for packages suitable for all distributions
	# The subdirectory with the distribution name is used for packages only suitable for this specific distribution.
	ls ${INCOMINGDIR}/*.deb ${INCOMINGDIR}/${DEB_DIST}/*.deb ${INCOMINGDIR}/all/*.deb 2>/dev/null | while read DEBFILE; do
		FN=`basename "${DEBFILE}"`
		FP="${DEBFILE}"
		
		PKG_NAME=`dpkg --info "${FP}" | grep "^ Package: " | sed -e "s/^.*: \(.*\)$/\1/"`
		PKG_VER=`dpkg --info "${FP}" | grep "^ Version: " | sed -e "s/^.*: \(.*\)$/\1/"`
		PKG_ARCH=`dpkg --info "${FP}" | grep "^ Architecture: " | sed -e "s/^.*: \(.*\)$/\1/"`
		
		info "-- ${DEB_DIST}|${FN}: ${PKG_NAME} ${PKG_VER} (${PKG_ARCH})"
		if [ -n "`reprepro -b ${TARGETDIR}/ listfilter "${DEB_DIST}" "Package  (==${PKG_NAME}), Version (==${PKG_VER})"`" ]; then
			error "   ${PKG_NAME} Version ${PKG_VER} already exists for ${DEB_DIST} - skipping..."
			continue;
		fi

		if [ -n "$DEB_SIGNID" ]; then
			info "   Signing..."
			FP="/tmp/$FN"
			cp "${DEBFILE}" "${FP}"
			dpkg-sig -m "${DEB_ORIGIN}" -s builder -g "${GPG_OPTS}" "${FP}" 2>&1 > /dev/null
			[ $? -ne 0 ] && abort "Could not sign package ${FN}"
		fi
		# Add the file to the repository
		info "   Adding..."
		reprepro -b ${TARGETDIR} includedeb "${DEB_DIST}" "${FP}" 2>&1 > /dev/null
		[ $? -ne 0 ] && abort "   Could not add package ${FN} to ${DEB_DIST} distribution!"
		
		if [ -n "$ARCHDIR" ]; then
			# Move the file to the archive dir
			info "   Archiving..."
			[ ! -d "$ARCHDIR/$DEB_DIST" ] && mkdir -p "$ARCHDIR/$DEB_DIST"
			mv "${DEBFILE}" "${ARCHDIR}/$DEB_DIST"
			[ -f "${FP}" ] && rm "${FP}"
		else
			rm "${DEBFILE}"
			[ -f "${FP}" ] && rm "${FP}"
		fi
		info "   Done."
	done
done
info "Cleaning up repository..."
reprepro -b ${TARGETDIR} clearvanished

info "Finished."
