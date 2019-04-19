#!/bin/sh

# TODO:
# add a --uploads option to specify the number of latest files to uploads. Good
# in case we missed some.
# add options to wait before starting, similar to mirror.tcl
# add option to sleep and restart automatically

#set -x

# All (good?) defaults
VERBOSE=0
KEEP=""
DESTINATION="."
COMPRESS=-1
THEN=""
PASSWORD=""
DAVIX=davix
OPTS=
COMPRESSOR=

# Dynamic vars
cmdname=$(basename $(readlink -f $0))
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
    -o | --davix-options Options to pass to davix commands
    -O | --davix-opts-file Same as above, but read from path passed as argument
                           instead

  Note that --davix-options and other options for setting options to davix are
  cumulative. Every value is appended to the original empty set of davix options
  with a space. This allows to acquire secrets from file instead of the command
  line.
USAGE
  exit "$exitcode"
}


# Parse options
while [ $# -gt 0 ]; do
    case "$1" in
        -k | --keep)
            KEEP=$2; shift 2;;
        --keep=*)
            KEEP="${1#*=}"; shift 1;;

        -c | --compress | --compression)
            COMPRESS=$2; shift 2;;
        --compress=* | --compression=*)
            NS="${1#*=}"; shift 1;;

        -d | --dest*)
            DESTINATION=$2; shift 2;;
        --dest=* | --destination=*)
            DESTINATION="${1#*=}"; shift 1;;

        -w | --password | --pass)
            PASSWORD=$2; shift 2;;
        --password=* | --pass=*)
            PASSWORD="${1#*=}"; shift 1;;

        -W | --pass-file | --password-file)
            PASSWORD=$(cat $2); shift 2;;
        --pass-file=* | --password-file=*)
            PASSWORD=$(cat ${1#*=}); shift 1;;

        -z | --compressor | --zipper)
            COMPRESSOR=$2; shift 2;;
        --compressor=* | --zipper=*)
            COMPRESSOR="${1#*=}"; shift 1;;

        -t | --then)
            THEN=$2; shift 2;;
        --then=*)
            THEN="${1#*=}"; shift 1;;

        -x | --davix)
            DAVIX=$2; shift 2;;
        --davix=*)
            DAVIX="${1#*=}"; shift 1;;

        -o | --davix-opts | --davix-options)
            OPTS="$OPTS $2"; shift 2;;
        --davix-opts=* | --davix-options=*)
            OPTS="$OPTS ${1#*=}"; shift 1;;

        -O | --davix-opts-file | --davix-options-file)
            OPTS="$OPTS $(cat $2)"; shift 2;;
        --davix-opts-file=* | --davix-options-file=*)
            OPTS="$OPTS $(cat ${1#*=})"; shift 1;;

        -v | --verbose)
            VERBOSE=1; shift;;

        -h | --help)
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
if [ -z "$COMPRESSOR" ]; then
    ZIP=$(which zip)
    if [ -n "${ZIP}" ]; then
        COMPRESSOR=${ZIP}
    else
        GZIP=$(which gzip)
        if [ -n "${GZIP}" ]; then
            COMPRESSOR=${GZIP}
        fi
    fi
fi

# Decide extension
ZEXT=
if [ -n "$COMPRESSOR" ]; then
    case "$(basename "$COMPRESSOR")" in
        zip)
            ZEXT="zip";;
        gzip)
            ZEXT="gz";;
        *)
            echo "Compressor $COMPRESSOR not recognised!" >& 2
    esac
fi

# Conditional logging
log() {
    local txt=$1

    if [ "$VERBOSE" == "1" ]; then
        echo "$txt"
    fi
}

dir_exists() {
    local dir=${1%%/}/

    if [ -z "$DAVIX" ]; then
        if [ -d "${dir}" ]; then
            echo "1"
        else
            echo "0"
        fi
    else
        ${DAVIX}-ls ${OPTS} ${dir} >/dev/null 2>&1
        if [ "$?" = "0" ]; then
            echo "1"
        else
            echo "0"
        fi
    fi
}

dir_make() {
    local dir=${1%%/}/

    if [ -z "$DAVIX" ]; then
        mkdir -p $dir
    else
        start=$(echo "$dir" | sed -E -e 's,^((.*:)//([A-Za-z0-9\-\.]+)(:[0-9]+)?)(.*)$,\1,')
        path=$(echo "$dir" | sed -E -e 's,^((.*:)//([A-Za-z0-9\-\.]+)(:[0-9]+)?)(.*)$,\5,')
        path=${path##/}
        url=$start
        for part in $(echo "$path" | sed -E -e 's,/, ,g'); do
            url="${url}/${part}"
            if [ $(dir_exists ${url}/) = "0" ]; then
                ${DAVIX}-mkdir ${OPTS} ${url}/
            fi
        done 
    fi
}

dir_ls_time() {
    local dir=${1%%/}/

    if [ -z "$DAVIX" ]; then
        ls $dir -1 -t
    else
        ${DAVIX}-ls ${OPTS} -l ${dir} | awk -F' ' '{$1=$2=$3="";$0=$0;$1=$1}1' | sort -r | awk -F' ' '{print $NF}' | sed -E -e "s,\r$,,g"
    fi
}

file_copy() {
    local src=$1
    local dir=${2%%/}/

    if [ -z "$DAVIX" ]; then
        cp ${src} ${dir}
    else
        ${DAVIX}-put ${OPTS} ${src} ${dir}$(basename $src)
    fi
}

file_delete() {
    if [ -z "$DAVIX" ]; then
        rm -rf $1
    else
        ${DAVIX}-rm ${OPTS} $1
    fi
}

file_exists() {
    if [ -z "$DAVIX" ]; then
        if [ -e "$1" ]; then
            echo "1"
        else
            echo "0"
        fi
    else
        if [ -n "$(${DAVIX}-ls ${OPTS} $1 2>/dev/null)" ]; then
            echo "1"
        else
            echo "0"
        fi
    fi
}

# Create destination directory if it does not exist (including all leading
# directories in the path)
if [ $(dir_exists ${DESTINATION}) = "0" ]; then
    log "Creating destination directory ${DESTINATION}"
    dir_make ${DESTINATION}
fi


# Create temporary directory for storage of compressed and encrypted files.
TMPDIR=$(mktemp -d -t ${appname}.XXXXXX)

LATEST=$(ls $@ -1 -t | head -n 1)
if [ -n "$LATEST" ]; then
    if [ "$COMPRESS" -ge "0" -a -n "$COMPRESSOR" ]; then
        ZTGT=${TMPDIR}/$(basename $LATEST).${ZEXT}
        SRC=
        log "Compressing $LATEST to $ZTGT"
        case "$ZEXT" in
            gz)
                gzip -${COMPRESS} -c ${LATEST} > ${ZTGT}
                SRC="$ZTGT"
                ;;
            zip)
                # ZIP in directory of latest file to have relative directories
                # stored in the ZIP file
                cwd=$(pwd)
                cd $(dirname ${LATEST})
                if [ -z "${PASSWORD}" ]; then
                    zip -${COMPRESS} ${ZTGT} $(basename ${LATEST})
                else
                    zip -${COMPRESS} -P "${PASSWORD}" ${ZTGT} $(basename ${LATEST})
                fi
                cd ${cwd}
                SRC="$ZTGT"
                ;;
        esac
    else
        SRC="$LATEST"
    fi

    if [ -n "${SRC}" ]; then
        log "Copying ${SRC} to ${DESTINATION}"
        file_copy $(readlink -f ${SRC}) ${DESTINATION}
    fi
fi

if [ -n "${KEEP}" -a "${KEEP}" -gt "0" ]; then
    log "Keeping only ${KEEP} copies at ${DESTINATION}"
    while [ $(dir_ls_time $DESTINATION | wc -l) -gt $KEEP ]; do
        DELETE=$(dir_ls_time $DESTINATION | tail -n 1)
        log "Removing old copy $DELETE"
        file_delete ${DESTINATION%/}/$DELETE
    done
fi

# Cleanup temporary directory
rm -rf $TMPDIR

if [ -n "${THEN}" ]; then
    log "Executing ${THEN}"
    if [ "$(file_exists ${DESTINATION%/}/$(basename ${SRC}))" = "1" ]; then
        eval "${THEN}" ${DESTINATION%/}/$(basename ${SRC})
    else
        eval "${THEN}"
    fi
fi
