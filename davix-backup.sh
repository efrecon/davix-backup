#!/bin/bash

# TODO:
# add a --uploads option to specify the number of latest files to uploads. Good
# in case we missed some.

#set -x

# All (good?) defaults
DAVIX_BACKUP_VERBOSE=${DAVIX_BACKUP_VERBOSE:-0}
DAVIX_BACKUP_TRACE=${DAVIX_BACKUP_TRACE:-0}
DAVIX_BACKUP_KEEP=${DAVIX_BACKUP_KEEP:-}
DAVIX_BACKUP_DESTINATION=${DAVIX_BACKUP_DESTINATION:-"."}
DAVIX_BACKUP_COMPRESS=${DAVIX_BACKUP_COMPRESS:--1}
DAVIX_BACKUP_THEN=${DAVIX_BACKUP_THEN:-}
DAVIX_BACKUP_PASSWORD=${DAVIX_BACKUP_PASSWORD:-}
DAVIX_BACKUP_DAVIX=${DAVIX_BACKUP_DAVIX:-davix}
DAVIX_BACKUP_OPTS=${DAVIX_BACKUP_OPTS:-}
DAVIX_BACKUP_COMPRESSOR=${DAVIX_BACKUP_COMPRESSOR:-}
DAVIX_BACKUP_WAIT=${DAVIX_BACKUP_WAIT:-0}
DAVIX_BACKUP_REPEAT=${DAVIX_BACKUP_REPEAT:-0}

# Dynamic vars
cmdname=$(basename "$(readlink -f $0)")
appname=${cmdname%.*}

# Print usage on stderr and exit
usage() {
  exitcode="$1"
  cat << USAGE >&2

Description:

  $cmdname will find the latest file matching a pattern, possbily compress it,
  move it to a destination (remote) directory and rotate files in this
  directory to keep disk space under control. Compression via zip is
  preferred, otherwise gzip. Remote copying is performed through davix, which
  supports WebDAV, S3, Azure and Google buckets.

Usage:
  $cmdname [-option arg --long-option(=)arg] pattern

  where all dash-led options are as follows (long options can be followed by
  an equal sign):
    -v | --verbose       Be more verbose
    -d | --destination   Directory where to place (and rotate) (compressed)
                         copies, default to current dir. Can be a remote
                         resource starting with http:// or https://
    -k | --keep          Number of compressed copies to keep, defaults to empty,
                         meaning all
    -c | --compression   Compression level, defaults to -1, meaning no
                         compression attempt made, file kept as is.
    -w | --password      Password for compressed archive, only works when zip
                         available
    -W | --password-file Same as -w, but read content of password from
                         specified file instead.
    -z | --compressor    Path to compressor binary (zip or gzip)
    -t | --then          Command to execute once done, location of copied
                         resource will be passed as an argument
    -x | --davix         Path to davix command, defaults to davix. For
                         uncompressed scenarios, you can use something such as:
                            docker run -it --rm --entrypoint= \
                                -v ${HOME}:${HOME} efrecon/davix davix
    --wait               Wait this much before starting backup, it colon present
                         choose random time between each periods. Periods can
                         be expressed in human-readable form, e.g. 5M for 5
                         minutes.
    -r | --repeat        Repeat copy at the given period. Period can be
                         specified in a human-readable form, e.g. 2H for 2
                         hours. Default is not to repeat.
    -o | --davix-options Options to pass to davix commands
    -O | --davix-opts-file Same as above, but read from path passed as argument
                           instead

  Note that --davix-options and other options for setting options to davix are
  cumulative. Every value is appended to the original empty set of davix options
  with a space. This allows to acquire secrets from file instead of the command
  line.

  Most options can be set using environment variables starting with
  DAVIX_BACKUP_ followed by the name of the long option in uppercase, e.g.
  DAVIX_BACKUP_DESTINATION.

USAGE
  exit "$exitcode"
}


# Parse options
while [ $# -gt 0 ]; do
    case "$1" in
        -k | --keep)
            DAVIX_BACKUP_KEEP=$2; shift 2;;
        --keep=*)
            DAVIX_BACKUP_KEEP="${1#*=}"; shift 1;;

        -c | --compress | --compression)
            DAVIX_BACKUP_COMPRESS=$2; shift 2;;
        --compress=* | --compression=*)
            DAVIX_BACKUP_COMPRESS="${1#*=}"; shift 1;;

        -d | --destination | --dest)
            DAVIX_BACKUP_DESTINATION=$2; shift 2;;
        --dest=* | --destination=*)
            DAVIX_BACKUP_DESTINATION="${1#*=}"; shift 1;;

        -w | --password | --pass)
            DAVIX_BACKUP_PASSWORD=$2; shift 2;;
        --password=* | --pass=*)
            DAVIX_BACKUP_PASSWORD="${1#*=}"; shift 1;;

        -W | --pass-file | --password-file)
            DAVIX_BACKUP_PASSWORD=$(cat $2); shift 2;;
        --pass-file=* | --password-file=*)
            DAVIX_BACKUP_PASSWORD=$(cat ${1#*=}); shift 1;;

        -z | --compressor | --zipper)
            DAVIX_BACKUP_COMPRESSOR=$2; shift 2;;
        --compressor=* | --zipper=*)
            DAVIX_BACKUP_COMPRESSOR="${1#*=}"; shift 1;;

        -t | --then)
            DAVIX_BACKUP_THEN=$2; shift 2;;
        --then=*)
            DAVIX_BACKUP_THEN="${1#*=}"; shift 1;;

        -x | --davix)
            DAVIX_BACKUP_DAVIX=$2; shift 2;;
        --davix=*)
            DAVIX_BACKUP_DAVIX="${1#*=}"; shift 1;;

        -r | --repeat)
            DAVIX_BACKUP_REPEAT=$2; shift 2;;
        --repeat=*)
            DAVIX_BACKUP_REPEAT="${1#*=}"; shift 1;;

        --wait)
            DAVIX_BACKUP_WAIT=$2; shift 2;;
        --wait=*)
            DAVIX_BACKUP_WAIT="${1#*=}"; shift 1;;

        -o | --davix-opts | --davix-options)
            DAVIX_BACKUP_OPTS="$DAVIX_BACKUP_OPTS $2"; shift 2;;
        --davix-opts=* | --davix-options=*)
            DAVIX_BACKUP_OPTS="$DAVIX_BACKUP_OPTS ${1#*=}"; shift 1;;

        -O | --davix-opts-file | --davix-options-file)
            DAVIX_BACKUP_OPTS="$DAVIX_BACKUP_OPTS $(cat $2)"; shift 2;;
        --davix-opts-file=* | --davix-options-file=*)
            DAVIX_BACKUP_OPTS="$DAVIX_BACKUP_OPTS $(cat ${1#*=})"; shift 1;;

        -v | --verbose)
            DAVIX_BACKUP_VERBOSE=1; shift;;

        --trace)
            DAVIX_BACKUP_TRACE=1; shift;;

        -h | --help)
            usage 0;;
        --)
            shift; break;;
        -*)
            echo "Unknown option: $1 !" >&2 ; usage 1;;
        *)
            break;;
    esac
done

if [ $# -eq 0 ]; then
    echo "You need to specify sources to copy for offline backup" >& 2
    usage 1
fi

# Decide upon which compressor to use. Prefer zip to be able to encrypt
if [ -z "$DAVIX_BACKUP_COMPRESSOR" ]; then
    ZIP=$(which zip)
    if [ -n "${ZIP}" ]; then
        DAVIX_BACKUP_COMPRESSOR=${ZIP}
    else
        GZIP=$(which gzip)
        if [ -n "${GZIP}" ]; then
            DAVIX_BACKUP_COMPRESSOR=${GZIP}
        fi
    fi
fi

# Decide extension
ZEXT=
if [ -n "$DAVIX_BACKUP_COMPRESSOR" ]; then
    case "$(basename "$DAVIX_BACKUP_COMPRESSOR")" in
        zip)
            ZEXT="zip";;
        gzip)
            ZEXT="gz";;
        *)
            echo "Compressor $DAVIX_BACKUP_COMPRESSOR not recognised!" >& 2
    esac
fi

# Conditional logging
log() {
    local txt=$1

    if [ "$DAVIX_BACKUP_VERBOSE" == "1" ]; then
        echo "$txt"
    fi
}

howlong() {
    if echo "$1"|grep -Eqo '^[0-9]+[[:space:]]*[yY]'; then
        len=$(echo "$1"  | sed -En 's/([0-9]+)[[:space:]]*[yY].*/\1/p')
        expr "$len" \* 31536000
        return
    fi
    if echo "$1"|grep -Eqo '^[0-9]+[[:space:]]*[Mm][Oo]'; then
        len=$(echo "$1"  | sed -En 's/([0-9]+)[[:space:]]*[Mm][Oo].*/\1/p')
        expr "$len" \* 2592000
        return
    fi
    if echo "$1"|grep -Eqo '^[0-9]+[[:space:]]*[Mm][Ii]'; then
        len=$(echo "$1"  | sed -En 's/([0-9]+)[[:space:]]*[Mm][Ii].*/\1/p')
        expr "$len" \* 60
        return
    fi
    if echo "$1"|grep -Eqo '^[0-9]+[[:space:]]*m'; then
        len=$(echo "$1"  | sed -En 's/([0-9]+)[[:space:]]*m.*/\1/p')
        expr "$len" \* 2592000
        return
    fi
    if echo "$1"|grep -Eqo '^[0-9]+[[:space:]]*[Ww]'; then
        len=$(echo "$1"  | sed -En 's/([0-9]+)[[:space:]]*[Ww].*/\1/p')
        expr "$len" \* 604800
        return
    fi
    if echo "$1"|grep -Eqo '^[0-9]+[[:space:]]*[Dd]'; then
        len=$(echo "$1"  | sed -En 's/([0-9]+)[[:space:]]*[Dd].*/\1/p')
        expr "$len" \* 86400
        return
    fi
    if echo "$1"|grep -Eqo '^[0-9]+[[:space:]]*[Hh]'; then
        len=$(echo "$1"  | sed -En 's/([0-9]+)[[:space:]]*[Hh].*/\1/p')
        expr "$len" \* 3600
        return
    fi
    if echo "$1"|grep -Eqo '^[0-9]+[[:space:]]*M'; then
        len=$(echo "$1"  | sed -En 's/([0-9]+)[[:space:]]*M.*/\1/p')
        expr "$len" \* 60
        return
    fi
    if echo "$1"|grep -Eqo '^[0-9]+[[:space:]]*[Ss]'; then
        len=$(echo "$1"  | sed -En 's/([0-9]+)[[:space:]]*[Ss].*/\1/p')
        echo "$len"
        return
    fi
    if echo "$1"|grep -Eqo '^[0-9]+'; then
        echo "$1"
        return
    fi
}

davix() {
    local op=$1
    shift

    if [ "$DAVIX_BACKUP_TRACE" == "1" ]; then
        echo "Executing: ${DAVIX_BACKUP_DAVIX}-${op} ${DAVIX_BACKUP_OPTS} $@" >& 2
    fi
    ${DAVIX_BACKUP_DAVIX}-${op} ${DAVIX_BACKUP_OPTS} $@
}

dir_exists() {
    local dir=${1%%/}/

    if [ -z "$DAVIX_BACKUP_DAVIX" ]; then
        if [ -d "${dir}" ]; then
            echo "1"
        else
            echo "0"
        fi
    else
        ${DAVIX_BACKUP_DAVIX}-ls ${DAVIX_BACKUP_OPTS} ${dir} >/dev/null 2>&1
        if [ "$?" = "0" ]; then
            echo "1"
        else
            echo "0"
        fi
    fi
}

dir_make() {
    local dir=${1%%/}/

    if [ -z "$DAVIX_BACKUP_DAVIX" ]; then
        mkdir -p $dir
    else
        start=$(echo "$dir" | sed -E -e 's,^((.*:)//([A-Za-z0-9\-\.]+)(:[0-9]+)?)(.*)$,\1,')
        path=$(echo "$dir" | sed -E -e 's,^((.*:)//([A-Za-z0-9\-\.]+)(:[0-9]+)?)(.*)$,\5,')
        path=${path##/}
        url=$start
        for part in $(echo "$path" | sed -E -e 's,/, ,g'); do
            url="${url}/${part}"
            if [ "$(dir_exists ${url}/)" = "0" ]; then
                davix mkdir ${url}/
            fi
        done 
    fi
}

dir_ls_time() {
    local dir=${1%%/}/

    if [ -z "$DAVIX_BACKUP_DAVIX" ]; then
        ls $dir -1 -t
    else
        davix ls -l ${dir} | awk -F' ' '{$1=$2=$3="";$0=$0;$1=$1}1' | sort -r | awk -F' ' '{print $NF}' | sed -E -e "s,\r$,,g"
    fi
}

file_copy() {
    local src=$1
    local dir=${2%%/}/

    if [ -z "$DAVIX_BACKUP_DAVIX" ]; then
        cp "${src}" "${dir}"
    else
        davix put "${src}" "${dir}$(basename "$src")"
    fi
}

file_delete() {
    if [ -z "$DAVIX_BACKUP_DAVIX" ]; then
        rm -rf "$1"
    else
        davix rm "$1"
    fi
}

file_exists() {
    if [ -z "$DAVIX_BACKUP_DAVIX" ]; then
        if [ -e "$1" ]; then
            echo "1"
        else
            echo "0"
        fi
    else
        if [ -n "$(${DAVIX_BACKUP_DAVIX}-ls ${DAVIX_BACKUP_OPTS} $1 2>/dev/null)" ]; then
            echo "1"
        else
            echo "0"
        fi
    fi
}

if echo "$DAVIX_BACKUP_WAIT" | grep -q '.*:.*'; then
    min=$(echo "$DAVIX_BACKUP_WAIT" | sed -En 's/(.*):.*/\1/p')
    MIN=$(howlong "$min")
    max=$(echo "$DAVIX_BACKUP_WAIT" | sed -En 's/.*:(.*)/\1/p')
    MAX=$(howlong "$max")
    DAVIX_BACKUP_WAIT=$(expr "$MIN" + $RANDOM % \( "$MAX" - "$MIN" \))
else
    DAVIX_BACKUP_WAIT=$(howlong "$DAVIX_BACKUP_WAIT")
fi

if [ "$DAVIX_BACKUP_WAIT" -gt 0 ]; then
    log "Waiting $DAVIX_BACKUP_WAIT s. before operation"
    sleep "$DAVIX_BACKUP_WAIT"
fi

# Create destination directory if it does not exist (including all leading
# directories in the path)
if [ "$(dir_exists "${DAVIX_BACKUP_DESTINATION}")" = "0" ]; then
    log "Creating destination directory ${DAVIX_BACKUP_DESTINATION}"
    dir_make "${DAVIX_BACKUP_DESTINATION}"
fi

DAVIX_BACKUP_REPEAT=$(howlong "$DAVIX_BACKUP_REPEAT")
while :; do
    BEGIN=$(date +%s)

    # Create temporary directory for storage of compressed and encrypted files.
    TMPDIR=$(mktemp -d -t "${appname}.XXXXXX")

    LATEST=$(ls $@ -1 -t -d | head -n 1)
    if [ -n "$LATEST" ]; then
        if [ "$DAVIX_BACKUP_COMPRESS" -ge "0" -a -n "$DAVIX_BACKUP_COMPRESSOR" ]; then
            ZTGT=${TMPDIR}/$(basename "$LATEST").${ZEXT}
            SRC=
            log "Compressing $LATEST to $ZTGT"
            case "$ZEXT" in
                gz)
                    gzip -${DAVIX_BACKUP_COMPRESS} -c ${LATEST} > ${ZTGT}
                    SRC="$ZTGT"
                    ;;
                zip)
                    # ZIP in directory of latest file to have relative directories
                    # stored in the ZIP file
                    cwd=$(pwd)
                    cd $(dirname ${LATEST})
                    if [ -z "${DAVIX_BACKUP_PASSWORD}" ]; then
                        zip -${DAVIX_BACKUP_COMPRESS} -r ${ZTGT} $(basename ${LATEST})
                    else
                        zip -${DAVIX_BACKUP_COMPRESS} -P "${DAVIX_BACKUP_PASSWORD}" -r ${ZTGT} $(basename ${LATEST})
                    fi
                    cd ${cwd}
                    SRC="$ZTGT"
                    ;;
            esac
        else
            SRC="$LATEST"
        fi

        if [ -n "${SRC}" ]; then
            log "Copying ${SRC} to ${DAVIX_BACKUP_DESTINATION}"
            file_copy "$(readlink -f "${SRC}")" "${DAVIX_BACKUP_DESTINATION}"
        fi
    fi

    if [ -n "${DAVIX_BACKUP_KEEP}" ]; then
        if [ "${DAVIX_BACKUP_KEEP}" -gt "0" ]; then
            log "Keeping only ${DAVIX_BACKUP_KEEP} copie(s) at ${DAVIX_BACKUP_DESTINATION}"
            while [ "$(dir_ls_time "$DAVIX_BACKUP_DESTINATION" | wc -l)" -gt "$DAVIX_BACKUP_KEEP" ]; do
                DELETE=$(dir_ls_time "$DAVIX_BACKUP_DESTINATION" | tail -n 1)
                log "Removing old copy $DELETE"
                file_delete "${DAVIX_BACKUP_DESTINATION%/}/$DELETE"
            done
        fi
    fi

    # Cleanup temporary directory
    rm -rf "$TMPDIR"

    if [ -n "${DAVIX_BACKUP_THEN}" ]; then
        log "Executing ${DAVIX_BACKUP_THEN}"
        if [ "$(file_exists "${DAVIX_BACKUP_DESTINATION%/}/$(basename "${SRC}")")" = "1" ]; then
            eval "${DAVIX_BACKUP_THEN}" "${DAVIX_BACKUP_DESTINATION%/}/$(basename "${SRC}")"
        else
            eval "${DAVIX_BACKUP_THEN}"
        fi
    fi

    if [ "$DAVIX_BACKUP_REPEAT" -gt "0" ]; then
        END=$(date +%s)
        NEXT=$(expr "$DAVIX_BACKUP_REPEAT" - \( "$END" - "$BEGIN" \))
        if [ "$NEXT" -lt 0 ]; then
            NEXT=0
        fi
        log "Waiting $NEXT s. to next copy"
        sleep $NEXT
    else
        break
    fi
done