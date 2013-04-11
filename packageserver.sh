#!/bin/bash
#############################################################################
## Package server script
##
#############################################################################
# References:
# http://www.debian-administration.org/articles/286
# http://wiki.debian.org/HowToSetupADebianRepository
# http://wiki.debian.org/SettingUpSignedAptRepositoryWithReprepro
# https://help.ubuntu.com/community/LocalAptGetRepository
# http://davehall.com.au/blog/dave/2010/02/06/howto-setup-private-package-repository-reprepro-nginx
# http://blog.jonliv.es/2011/04/26/creating-your-own-signed-apt-repository-and-debian-packages/
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
DEB_KEYNAME=
# List of all repositories you want to support
DEB_DISTRIBS=
# List of all architectures you want to support
#DEB_ARCHS="amd64 i386"
DEB_ARCHS=
#DEB_COMPONENTS="main"
DEB_COMPONENTS=
# Signing is mandatory by default. Clear if not needed
MANDATORY_SIGN=1
# Optional GPG options
GPG_KEYLEN=2048
GPG_OPTS=

#############################################################################
## Logger functions

function log
{
	LEVEL="$1"
	COLOR="$2"
	shift 2
	TEXT="$*"
	# Only colorize if output is a terminal
	DATETIME=`date +"%Y-%m-%d %H:%M:%S"`
	if [ -t 1 ]; then
		echo -e "\e[${COLOR}m${LEVEL}\e[00m [\e[1;30m${DATETIME}\e[00m] $TEXT"
	else
		echo "${LEVEL} [${DATETIME}] $TEXT"
	fi
}

function info
{
	log "INFO " "0;32" "$*"
}

function warn
{
	log "WARN " "1;33" "$*"
}

function error
{
	log "ERROR" "1;31" "$*"
}

function abort
{
	if [ -n "$*" ]; then
		error "$*"
	fi
	error "Aborting..."
	exit 1
}

#############################################################################
# Load optional config files
[ -f "/etc/default/packageserver" ] && . /etc/default/packageserver
[ -f "${HOME}/.packageserver" ] && . ${HOME}/.packageserver

#############################################################################
## Helper functions
CMD=$0
function showhelp
{
	cat <<EOF
Usage $CMD [options] [ <distribution|all> <file1.deb> [file2.deb [ ... ]] ]
	-c|--config <file>:
		Specify a config file to load on the commandline.
		Note that other config files are still loaded, in the following order:
		1. /etc/default/packageserver
		2. ${HOME}/.packageserver
		3. The files you specify on the commandline.
	-g|--generategpg:
		Generate a GPG key for this server if required and exit.
	-r|--remove-existing:
		Remove a package if it already exists with the same version in the
		repository before attempting to add.
		WARNING: This may have unwanted side-effects! You should probably just
	-s|--sampleconfig:
		Generate a default configfile (sent to stdout) that can be saved to:
			${HOME}/.packageserver
		or
			/etc/default/packageserver
		Then this file will be loaded automatically.
		         update the package version.
	-h|--help
		Show this message and exit.
If no distribution is selected and no files are provided on the commandline, and
all settings are correct, the incoming directories will be processed.

Note that files provided on the commandline are NOT archived.

EOF
}

function gen_config
{
	cat <<EOF
## GENERATED CONFIG FILE -- ADJUST TO YOUR OWN NEEDS
# REQUIRED: Incoming dir
INCOMINGDIR="\${HOME}/apt-incoming"

# Archive dir. If not defined, the files are removed - has to be writable by the user!
ARCHDIR="\${INCOMINGDIR}/archive"

# The repository root directory (browsable using a web-server, writable by package generation user)
TARGETDIR="\${HOME}/apt"

# REQUIRED: Debian repository name
DEB_ORIGIN="Your organisation name"

# REQUIRED: Name of the key in the GPG ring, should not contain spaces
DEB_KEYNAME="packages.yourorganisation"

# REQUIRED: Debian repository email
DEB_EMAIL="packages@yourorganisation.com"
DEB_LABEL=""
DEB_DESCRIPTION="yourorganisation package server"

# REQUIRED: List of all distributions you want to support
#DEB_DISTRIBS="precise futuredistrib"
DEB_DISTRIBS=""

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

info "Loaded custom configuration for \${DEB_ORIGIN}."

EOF
}


#############################################################################
## Process commandline options
REMOVE_IFEXISTS=
GENERATE_KEY=
while [ 1 ]; do
	if [ "`echo $1 | sed -e "s/^-.*/##OK##/g"`" != "##OK##" ]; then
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
		-s|--sampleconfig)
			gen_config
			exit 0
			;;
		-r|--remove-existing)
			REMOVE_IFEXISTS=1
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
# Check for optional commandline parameters
DISTSEL=
if [ -n "$1" ]; then
	if [ "$1" == "all" ] || [[ "$DEB_DISTRIBS" == *"$1"* ]]; then
		# Known distribution provided
		DISTSEL="$1"
		shift 1
		if [ -z "$1" ] || [ ! -f "$1" ]; then
			abort "Valid distribution '$DISTSEL' selected,  but no valid files provided"
		fi
		info "Distribution '$1' selected for files provided on commandline."
	else
		abort "Unexpected commandline argument provided or unknown distribution selected"
	fi
fi

#############################################################################
# Basic checks

if [ -z "${DEB_DISTRIBS}" ] || [ -z "${DEB_EMAIL}" ] || [ -z "${DEB_ORIGIN}" ] || [ -z "${DEB_KEYNAME}" ] || [ -z "${INCOMINGDIR}" ] || [ -z "${TARGETDIR}" ] || [ -z "${DEB_ARCHS}" ] || [ -z "${DEB_COMPONENTS}" ]; then
	echo "#############################################################################"
	echo "## !! NO VALID/COMPLETE CONFIGURATION PRESENT:"
	[ -z "${DEB_DISTRIBS}" ]   && echo "##     DEB_DISTRIBS configuration not set"
	[ -z "${DEB_EMAIL}" ]      && echo "##     DEB_EMAIL configuration not set"
	[ -z "${DEB_ORIGIN}" ]     && echo "##     DEB_ORIGIN configuration not set"
	[ -z "${DEB_KEYNAME}" ]    && echo "##     DEB_KEYNAME configuration not set"
	[ -z "${INCOMINGDIR}" ]    && echo "##     INCOMINGDIR configuration not set"
	[ -z "${TARGETDIR}" ]      && echo "##     TARGETDIR configuration not set"
	[ -z "${DEB_ARCHS}" ]      && echo "##     DEB_ARCHS configuration not set"
	[ -z "${DEB_COMPONENTS}" ] && echo "##     DEB_COMPONENTS configuration not set"
	echo "##"
	echo "## You can generate a sample configuration file with the following command:"
	echo "##     $CMD --sampleconfig"
	echo "## Save the output of this command this configuration file as one of these:"
	echo "##     /etc/default/packageserver"
	echo "##     ${HOME}/.packageserver"
	echo "## Then adjust it to your needs"
	echo "##"
	echo "## You can also specify a specific configuration file like this:"
	echo "##    $CMD --config <alternative configfile>"
	echo "##"
	echo "## Run '$CMD --help' for basic usage"
	echo "#############################################################################"
	exit 1
fi

if [ ! -d "$TARGETDIR" ]; then
	mkdir -p "$TARGETDIR/" || abort "Could not create target directory '${TARGETDIR}'!"
fi
if [ ! -d "${INCOMINGDIR}" ]; then
	mkdir -p "${INCOMINGDIR}/" || abort "Could not create incoming directory '${INCOMINGDIR}'!"
fi
[ ! -w "${TARGETDIR}" ] && abort "Target directory '${TARGETDIR}' is not writable for current user!"
TSUBDIRS="conf dists incoming indices logs pool project project tmp"
for SUBDIR in $TSUBDIRS; do
	if [ ! -d "$TARGETDIR/$SUBDIR" ]; then
		mkdir -p "${TARGETDIR}/${SUBDIR}/" || abort "Could not create directory '${TARGETDIR}/${SUBDIR}'!"
	fi
done

#############################################################################

# The ASCII pubkey is exported here with the name "${DEB_KEYNAME}.gpg.key"
[ -z "${KEYPATH}" ] && KEYPATH="${TARGETDIR}/conf"

#############################################################################
## Check for the required packages
INSTPKG=
[ -z `which dpkg-sig` ] && INSTPKG="$INSTPKG dpkg-sig"
[ -z `which reprepro` ] && INSTPKG="$INSTPKG reprepro"
[ -z `which gpg`      ] && INSTPKG="$INSTPKG gnupg"

if [ -n "${INSTPKG}" ]; then
	abort "The following required packages don't seem to be installed: ${INSTPKG}"
fi

#############################################################################
## Generate GPG key if required

DEB_SIGNID=`gpg $GPG_OPTS --list-keys "${DEB_KEYNAME}" 2>/dev/null | grep "^sub" | sed -e 's/^sub.*\/\([0-9A-Za-z]*\).*$/\1/'`
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
			error "Another sollution is to generate a GPG key+subkey for '${DEB_KEYNAME}' on another machine and import them in your keyring manually."
			abort
		fi
		
		# Generate the key
		gpg --batch --gen-key 2>&1 > /dev/null <<EOF
		Key-Type: RSA
		Key-Length: ${GPG_KEYLEN}
		Subkey-Type: RSA
		Subkey-Length: ${GPG_KEYLEN}
		Name-Real: ${DEB_KEYNAME}
		Name-Comment: ${DEB_DESCRIPTION}
		Name-Email: ${DEB_EMAIL}
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
	echo "INFO: Key generation skipped: key for ${DEB_KEYNAME} already found: ${DEB_SIGNID}"
fi
DEB_SIGNID=`gpg ${GPG_OPTS} --list-keys "${DEB_KEYNAME}" 2>/dev/null | grep "^sub" | sed -e 's/^sub.*\/\([0-9A-Za-z]*\).*$/\1/'`

#############################################################################
## Export the GPG key if required

if [ -n "$DEB_SIGNID" ]; then
	[ ! -d "${KEYPATH}" ] && mkdir -p "${KEYPATH}"
	if [ ! -f "${KEYPATH}/${DEB_KEYNAME}.gpg.key" ]; then
		echo "Exporting key..."
		# export gpg key in ascii format
		gpg ${GPG_OPTS} --armor --export ${DEB_KEYNAME} 2>/dev/null > ${KEYPATH}/${DEB_KEYNAME}.gpg.key
	fi
elif [ -n "${MANDATORY_SIGN}" ]; then
	abort "Signing key not available -- package signing disabled, use -g to generate GPG key"
else
	warn "Signing key not available -- package signing disabled, use -g to generate GPG key"
fi

#############################################################################
## Function to add a .deb file to a specific repository
add_deb_to_repo_status=
function add_deb_to_repo
{
	add_deb_to_repo_status=
	DEB_DIST="$1"
	DEBFILE="$2"
	if [ ! -f "$DEBFILE" ]; then
		warn "Attempting to add non-existant $DEBFILE - ignoring"
		add_deb_to_repo_status=0
		return
	fi
	if [ -n "`lsof ${DEBFILE}`" ]; then
		warn "File ${DEBFILE} still open by other processes - skipping..."
		add_deb_to_repo_status=0
		return
	fi
	FN=`basename "${DEBFILE}"`
	FP="${DEBFILE}"
	dpkg --info "${FP}" 2>&1 >/dev/null
	if [ $? -ne 0 ]; then
		error "File '${FP}' is not a valid debian package"
		add_deb_to_repo_status=1
		return
	fi
	PKG_NAME=`dpkg --info "${FP}" 2>/dev/null | grep "^ Package: " | sed -e "s/^.*: \(.*\)$/\1/"`
	PKG_VER=`dpkg --info "${FP}" 2>/dev/null | grep "^ Version: " | sed -e "s/^.*: \(.*\)$/\1/"`
	PKG_ARCH=`dpkg --info "${FP}" 2>/dev/null | grep "^ Architecture: " | sed -e "s/^.*: \(.*\)$/\1/"`
	
	info "-- ${DEB_DIST}|${FN}: ${PKG_NAME} ${PKG_VER} (${PKG_ARCH})"
	if [ -n "`reprepro -b ${TARGETDIR}/ listfilter "${DEB_DIST}" "Package  (==${PKG_NAME}), Version (==${PKG_VER})"`" ]; then
		if [ -n "$REMOVE_IFEXISTS" ]; then
			warn "   ${PKG_NAME} Version ${PKG_VER} already exists for ${DEB_DIST} - removing..."
			reprepro -b ${TARGETDIR}/ remove "${DEB_DIST}" "${PKG_NAME}" 2>&1 > /dev/null
			if [ $? -ne 0 ]; then
				error "Could not remove package ${PKG_NAME}"
				add_deb_to_repo_status=3
				return
			fi
		else
			error "   ${PKG_NAME} Version ${PKG_VER} already exists for ${DEB_DIST} - skipping..."
			add_deb_to_repo_status=2
			return
		fi
	fi

	if [ -n "$DEB_SIGNID" ]; then
		info "   Signing..."
		# Copy to temporary file for signing
		FP="/tmp/$FN"
		cp "${DEBFILE}" "${FP}"
		dpkg-sig -m "${DEB_KEYNAME}" -s builder -g "${GPG_OPTS}" "${FP}" 2>&1 > /dev/null
		if [ $? -ne 0 ]; then
			error "Could not sign package ${FN}"
			add_deb_to_repo_status=3
			return
		fi
	fi
	# Add the file to the repository
	info "   Adding..."
	reprepro -b ${TARGETDIR} includedeb "${DEB_DIST}" "${FP}" 2>&1 > /dev/null
	if [ $? -ne 0 ]; then
		error "   Could not add package ${FN} to ${DEB_DIST} distribution!"
		add_deb_to_repo_status=3
	fi
	
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

RETVAL=0

if [ -n "$DISTSEL" ]; then
	#########################################################################
	## Process the file provided on the commandline
	info "Processing files provided on commandline"
	if [ "$DISTSEL" == "all" ]; then
		for DEB_DIST in $DEB_DISTRIBS; do
			add_deb_to_repo "${DEB_DIST}" "$1"
			[ -n "$add_deb_to_repo_status" ] && RETVAL=$add_deb_to_repo_status
		done
	else
		while [ -n "$1" ]; do
			add_deb_to_repo "${DISTSEL}" "$1"
			[ -n "$add_deb_to_repo_status" ] && RETVAL=$add_deb_to_repo_status
		done
	fi
else
	#########################################################################
	# Get the debian files from the incoming directory.
	# The "all" directory and the incoming directory itself are used for
	# packages suitable for all distributions.
	# The subdirectory with the distribution name is used for packages
	# only suitable for this specific distribution.
	info "Processing incoming directories"
	#########################################################################
	## Process the distribution specific packages
	for DEB_DIST in $DEB_DISTRIBS; do
		ls ${INCOMINGDIR}/${DEB_DIST}/*.deb 2>/dev/null | while read DEBFILE; do
			add_deb_to_repo "${DEB_DIST}" "${DEBFILE}"
			if [ -n "$add_deb_to_repo_status" ]; then
				warn "Problem occured while processing ${DEB_DIST} -> ${DEBFILE} - skipping archiving"
				RETVAL=$add_deb_to_repo_status
			else
				archive_debfile "${DEB_DIST}" "${DEBFILE}"
			fi
		done
	done

	#########################################################################
	## Process the "all" distributions packages
	ls ${INCOMINGDIR}/*.deb ${INCOMINGDIR}/all/*.deb 2>/dev/null | while read DEBFILE; do
		LERR=
		for DEB_DIST in $DEB_DISTRIBS; do
			add_deb_to_repo "${DEB_DIST}" "${DEBFILE}"
			if [ -n "$add_deb_to_repo_status" ]; then
				LERR=$add_deb_to_repo_status
			else
				archive_debfile "${DEB_DIST}" "${DEBFILE}"
			fi
		done
		if [ -n "$LERR" ]; then
			warn "Problem occured while processing ${DEB_DIST} -> ${DEBFILE} - skipping archiving"
			RETVAL=$LERR
		else
			archive_debfile "" "${DEBFILE}"
		fi
	done
fi
	
#############################################################################
## Cleanup
info "Cleaning up repository..."
reprepro -b ${TARGETDIR} clearvanished

if [ $RETVAL -ne 0 ]; then
	warn "Errors occured while processing files!"
fi
#############################################################################
info "Finished."
exit $RETVAL
#############################################################################