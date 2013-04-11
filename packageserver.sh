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
INCOMINGDIR=

# Archive dir. If not defined, the files are removed - has to be writable by the user!
ARCHDIR=

# The repository root directory (browsable using a web-server, writable by package generation user)
TARGETDIR=

# Debian repository 
DEB_ORIGIN=
DEB_EMAIL=
DEB_LABEL=
DEB_DESCRIPTION=

# List of all repositories you want to support
#DEB_DISTRIBS="precise futuredistrib"
DEB_DISTRIBS=

# List of all architectures you want to support
#DEB_ARCHS="amd64 i386"
DEB_ARCHS=

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
## Helper functions
CMD=$0
function showhelp
{
	echo "Usage $CMD <options>"
	cat <<EOF
	-g|--generategpg:
		Generate a GPG key for this server if required and exit.
	-d|--defaultconfig:
		Generate a default configfile (sent to stdout) that can be saved to:
			${HOME}/.packageserver
		or
			/etc/default/packageserver
		Then this file will be loaded automatically.
	-h|--help
		Show this message and exit.
EOF
}

function gen_config
{
	cat <<EOF
## GENERATED CONFIG FILE -- ADJUST TO YOUR OWN NEEDS
# Incoming dir
INCOMINGDIR="\${HOME}/apt-incoming"

# Archive dir. If not defined, the files are removed - has to be writable by the user!
ARCHDIR="\${INCOMINGDIR}/archive"

# The repository root directory (browsable using a web-server, writable by package generation user)
TARGETDIR="\${HOME}/apt"

# REQUIRED: Debian repository name
DEB_ORIGIN="Your organisation name"
# REQUIRED: Debian repository email
DEB_EMAIL="packages@yourorganisation.com"
DEB_LABEL=""
DEB_DESCRIPTION="yourorganisation package server"

# REQUIRED: List of all distriburions you want to support
#DEB_DISTRIBS="precise futuredistrib"
DEB_DISTRIBS=

# REQUIRED: List of all architectures you want to support
#DEB_ARCHS="amd64 i386"
DEB_ARCHS=""

# REQUIRED: Components to support
DEB_COMPONENTS="main"

# Optional GPG options
#GPG_KEYLEN=${GPG_KEYLEN}
#GPG_OPTS=${GPG_OPTS}

# Signing is mandatory by default. Uncomment if you don't want package signing.
# Please note that when a sub key is present for the 
#MANDATORY_SIGN=

EOF
}

#############################################################################
## Logger functions
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

#############################################################################
## Process commandline options
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
		-d|--defaultconfig)
			gen_config
			exit 0
			;;
		-c|--config)
			if [ -f "$1" ]; then
				. $1
			else
				abort "Parameter -f/--file expected a file as parameter"
			fi
			shift 1
			;;
		*)
	esac
done

#############################################################################
# Basic checks

if [ -z "${DEB_DISTRIBS}" ] || [ -z "${DEB_EMAIL}" ] || [ -z "${DEB_ORIGIN}" ] || [ -z "${INCOMINGDIR}" ] || [ -z "${TARGETDIR}" ] || [ -z "${DEB_ARCHS}" ] || [ -z "${DEB_COMPONENTS}" ]; then
	echo "#############################################################################"
	echo "## !! NO VALID/COMPLETE CONFIGURATION PRESENT:"
	[ -z "${DEB_DISTRIBS}" ]   && echo "##     DEB_DISTRIBS configuration empty"
	[ -z "${DEB_EMAIL}" ]      && echo "##     DEB_EMAIL configuration empty"
	[ -z "${DEB_ORIGIN}" ]     && echo "##     DEB_ORIGIN configuration empty"
	[ -z "${INCOMINGDIR}" ]    && echo "##     INCOMINGDIR configuration empty"
	[ -z "${TARGETDIR}" ]      && echo "##     TARGETDIR configuration empty"
	[ -z "${DEB_ARCHS}" ]      && echo "##     DEB_ARCHS configuration empty"
	[ -z "${DEB_COMPONENTS}" ] && echo "##     DEB_COMPONENTS configuration empty"
	echo "##"
	echo "## You can generate a sameple configfile with the following command:"
	echo "##     $CMD --defaultconfig"
	echo "## Save the output of this command this configuration file as one of these:"
	echo "##     /etc/default/packageserver"
	echo "##     ${HOME}/.packageserver"
	echo "## Then adjust it to your needs"
	echo "##"
	echo "## You can also specify a specific configuration file like this:"
	echo "##    $CMD --config <alternative configfile>"
	echo "##"
	echo "#############################################################################"
	exit 1
fi

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

#############################################################################
## Check for the required packages
INSTPKG=
[ -z `which dpkg-sig` ] && INSTPKG="$INSTPKG dpkg-sig"
[ -z `which reprepro` ] && INSTPKG="$INSTPKG reprepro"

if [ -n "${INSTPKG}" ]; then
	abort "The following required packages don't seem to be installed: ${INSTPKG}"
fi

#############################################################################
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

#############################################################################
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

#############################################################################
## Function to add a .deb file to a specific repository
function add_deb_to_repo
{
	DEB_DIST="$1"
	DEBFILE="$2"
	if [ ! -f "$DEBFILE" ]; then
		abort "Attempting to add non-existant $DEBFILE"
	fi
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
		# Copy to temporary file for signing
		FP="/tmp/$FN"
		cp "${DEBFILE}" "${FP}"
		dpkg-sig -m "${DEB_ORIGIN}" -s builder -g "${GPG_OPTS}" "${FP}" 2>&1 > /dev/null
		[ $? -ne 0 ] && abort "Could not sign package ${FN}"
	fi
	# Add the file to the repository
	info "   Adding..."
	reprepro -b ${TARGETDIR} includedeb "${DEB_DIST}" "${FP}" 2>&1 > /dev/null
	[ $? -ne 0 ] && abort "   Could not add package ${FN} to ${DEB_DIST} distribution!"
	
	# Delete temporary signed file 
	[ "${FP}" != "${DEBFILE}" ] && rm "${FP}"
	info "   Done."
}
#############################################################################
## Function to archive a .deb file from the incoming directory
function archive_debfile
{
	DEB_DIST="$1"
	DEBFILE="$2"
	if [ -n "${ARCHDIR}" ]; then
		# Move the file to the archive dir
		info "   Archiving incoming file '${DEBFILE}'..."
		[ ! -d "${ARCHDIR}/${DEB_DIST}" ] && mkdir -p "${ARCHDIR}/${DEB_DIST}"
		mv "${DEBFILE}" "${ARCHDIR}/${DEB_DIST}" || abort "Could not move ${DEBFILE} to ${ARCHDIR}/${DEB_DIST}"
		info "   Archiving incoming file done."
	elif [ -w "${DEBFILE}" ]; then
		info "   Removing incoming file '${DEBFILE}'..."
		rm "${DEBFILE}" || abort "Could not remove ${DEBFILE}"
		info "   Removing incoming file done."
	fi
}
#############################################################################
## Initialize/check all distributions
for DEB_DIST in ${DEB_DISTRIBS}; do
	info "## Processing distribution ${DEB_DIST}"
	if [ ! -d "${TARGETDIR}/dists/${DEB_DIST}" ]; then
		# Distribution directory missing: add distribution to config file
		cat >> "${TARGETDIR}/conf/distributions" <<EOF
Origin: ${DEB_ORIGIN}
Label: ${DEB_LABEL}
Codename: ${DEB_DIST}
Architectures: ${DEB_ARCHS}
Components: ${DEB_COMPONENTS}
Description: ${DEB_DESCRIPTION}
SignWith: ${DEB_SIGNID}
Pull: ${DEB_DIST}

EOF
		mkdir -p "${TARGETDIR}/dists/${DEB_DIST}"
	fi
	info "Checking distribution repository..."
	reprepro -b "${TARGETDIR}" check "${DEB_DIST}"
done

#############################################################################
## Process the distribution specific packages
for DEB_DIST in $DEB_DISTRIBS; do
	# Get the debian files from the incoming directory.
	# The "all" directory and the incoming directory itself are used for packages suitable for all distributions
	# The subdirectory with the distribution name is used for packages only suitable for this specific distribution.
	ls ${INCOMINGDIR}/${DEB_DIST}/*.deb 2>/dev/null | while read DEBFILE; do
		add_deb_to_repo "${DEB_DIST}" "${DEBFILE}"
		archive_debfile "${DEB_DIST}" "${DEBFILE}"
	done
done

#############################################################################
## Process the "all" distributions packages
ls ${INCOMINGDIR}/*.deb ${INCOMINGDIR}/all/*.deb 2>/dev/null | while read DEBFILE; do
	for DEB_DIST in $DEB_DISTRIBS; do
		add_deb_to_repo "${DEB_DIST}" "${DEBFILE}"
	done
	archive_debfile "" "${DEBFILE}"
done

#############################################################################
## Cleanup
info "Cleaning up repository..."
reprepro -b ${TARGETDIR} clearvanished


#############################################################################
info "Finished."
#############################################################################