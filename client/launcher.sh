#
# Application flasher for nordic platform
# supporting x86 and ARM architectures.
#
# Note:
#   When using the current user, make sure you have access to dialout, otherwise
#   force root:dialout in the container user or simply run the script with
#   sudo powers.
#
# Author:
#   Pedro Silva

#!/bin/bash
trap 'echo "Aborting due to errexit on line $LINENO. Exit code: $?" >&2' ERR
set -o nounset
set -o errexit
set -o errtrace
set -o pipefail

SAFER_IFS=$'\n\t'
IFS="${SAFER_IFS}"

_ME=$(basename "${0}")

_print_help() {
  cat <<HEREDOC
Flasher and logger for nordic platforms

Usage:
  ${_ME} [<arguments>]
  ${_ME} -h | --help
  ${_ME} --docker --build --flash --log

Options:
  -h --help    Show this screen.
  --build   Disable build
  --flash   Enables flash
  --log     Starts logging (docker or screen)
  --port    Starting port for RTT Telnet (increments by 1)
  --app     Application name
  --board   Target board name, eg, NRF52
  --device  Device serial number
  --list    List all devices
  --clean   Forces cleanup of old containers
HEREDOC
}

_parse()
{
    # Gather commands
    POSITIONAL=()
    while [[ $# -gt 0 ]]
    do
    key="$1"

    case $key in
        --flash)
        FLASH=true
        shift # past argument
        ;;
        --clean)
        CLEAN=true
        shift # past argument
        ;;
        --build)
        BUILD=true
        shift # past argument
        ;;
        --log)
        LOG=true
        shift # past argument
        ;;
        --port)
        PORT="$2"
        shift # past argument
        shift # past value
        ;;
        --app)
        APP_NAME="$2"
        shift # past argument
        shift # past value
        ;;
        --board)
        BOARD="$2"
        shift # past argument
        shift # past value
        ;;
        --device)
        DEVICE="$2"
        shift # past argument
        shift # past value
        ;;
        --list)
        LIST=true
        shift # past argument
        ;;
        --fluentd)
        FLUENTD=true
        shift # past argument
        ;;
        --erase)
        ERASE=true
        shift # past argument
        ;;
        --hex_path)
        PATH_HEX="$2"
        shift # past argument
        shift # past value
        ;;
        --fluentd-host)
        FLUENTD_HOST="$2"
        shift # past argument
        shift # past value
        ;;
        *)    # unknown option
        POSITIONAL+=("$1") # save it in an array for later
        shift # past argument
        ;;
    esac
    done
    #set -- "${POSITIONAL[@]}" # restore positional parameters

    DISTRO=$(uname -m)

    if [ "${DISTRO}" == "armv7l" ]
    then
        DOCKER_IMAGE=${DOCKER_IMAGE:-"pfigs/jlink-arm"}
    else
        DOCKER_IMAGE=${DOCKER_IMAGE:-"pfigs/armbuilder"}
    fi

    ARM=${ARM:-false};
    LIST=${LIST:-false};
    FLASH=${FLASH:-false};
    CLEAN=${CLEAN:-false};

    LOG=${LOG:-false};
    FLUENTD=${FLUENTD:-false};
    ERASE=${ERASE:-false};

    BOARD=${BOARD:-nrf52};
    PORT=${PORT:-8000}
    APP_NAME=${APP_NAME:-""};
    DEVICE=${DEVICE:-""};
    PATH_HEX=${PATH_HEX:-"$(pwd)/app.hex"};

    FLUENTD_HOST=${FLUENTD_HOST:-"localhost:24224"}

    if [ "${BOARD}" == "nrf52" ]
    then
        BOARD_CHIP="pca10040";
    else
        BOARD_CHIP="pca10020";
    fi

    if [ -z "${DEVICE}" ]
    then
        echo "Looking up local devices ...";
        docker run --rm \
              -w /builder \
              -v $(pwd):/home \
              --privileged \
              --user=$(id -u):$(id -g) \
              -v /dev/:/dev/ \
              ${DOCKER_IMAGE} bash \
               -c "cd /builder; ./find_devices.sh; cp devices.rst /home;"
        DEVICE=$(<./devices.rst)
    fi

    if [ -z "${APP_NAME}" ]
        then
        APP_NAME=$(hostname)
    fi
}


_list()
{
    echo "Connected devices";
    for TARGET in ${DEVICE}
    do
        echo "${TARGET}";
    done
}


_force_clean()
{
    docker rm -f $(docker ps -qa --filter ancestor=${DOCKER_IMAGE}) || true
}


_clean()
{

    for TARGET in ${DEVICE}
    do
        echo "Removing containers ...";
        docker stop "CONNECTION-"${APP_NAME}-${TARGET} --time 0 || true;
        docker rm "CONNECTION-"${APP_NAME}-${TARGET}  || true;

        # this could be restarted one
        docker stop "LOG-"${APP_NAME}-${TARGET} --time 0 || true;
        docker rm "LOG-"${APP_NAME}-${TARGET}  || true;
    done

}

_docker()
{
    # proceeds to flash one or multiple target devices
    if ${FLASH}
    then
        echo "Available devices:"
        _list

        # make sure the container is removed
        _clean;

        for TARGET in ${DEVICE}
        do

            echo "Flashing ${APP_NAME} >> ${TARGET} ..."
            docker run --rm \
                       --user=$(id -u):$(id -g) \
                       -w /builder \
                       --privileged \
                       --net=none \
                       -v /dev/:/dev/ \
                       -v ${PATH_HEX}:/builder/target.hex \
                       ${DOCKER_IMAGE} \
                       bash \
                       -c "JLinkExe -Device ${BOARD} \
                                    -SelectEmuBySN ${TARGET} \
                                    -if SWD \
                                    -speed auto \
                                    -AutoConnect 1 \
                                    -CommanderScript ./flash.jlink"
        done
    fi

    if ${LOG}
    then
        _clean;

        if ${FLASH}
        then
            echo "waiting for flashing processes...";
            for job in $(jobs -p)
            do
                wait $job || true
            done
        fi

        PORT=${PORT};
        for TARGET in $DEVICE
        do
            echo "LOGGING ${APP_NAME} >> ${TARGET} @ ${PORT}";
            # starts connection containers
            NAME="CONNECTION-"${APP_NAME}-${TARGET};
            docker run -itd \
                       --name=${NAME} \
                       -w /builder \
                       --user=$(id -u):$(id -g) \
                       --net=host\
                       --privileged \
                       -v /dev/:/dev/ \
                       ${DOCKER_IMAGE} \
                       bash \
                       -c "JLinkExe -Device ${BOARD} \
                                    -SelectEmuBySN ${TARGET} \
                                    -if SWD \
                                    -speed auto \
                                    -AutoConnect 1 \
                                    -RTTTelnetPort ${PORT};"

            # starts logging containers
            if ${FLUENTD}
            then
                NAME="LOG-"${APP_NAME}-${TARGET};
                docker run -id \
                           --name=${NAME} \
                           --net=host\
                           -w /builder \
                           --log-driver=fluentd  \
                           --log-opt fluentd-address=FLUENTD_HOST \
                           --log-opt tag=docker.{{.Name}} \
                           --user=$(id -u):$(id -g) \
                           ${DOCKER_IMAGE} \
                           bash -c "./ts_print.sh ${PORT}"
            else
                NAME="LOG-"${APP_NAME}-${TARGET};
                docker run -id \
                           --name=${NAME} \
                           --net=host\
                           --env=${PORT} \
                           -w /builder \
                           --log-driver=journald \
                           --user=$(id -u):$(id -g) \
                           ${DOCKER_IMAGE} \
                           bash -c "./ts_print.sh ${PORT}"
            fi
            let PORT=PORT+1;
        done
    fi

    if ${ERASE}
    then
        for TARGET in $DEVICE
        do
            echo "ERASING ${TARGET}";
            # starts connection containers
            docker run --rm \
                       -w /builder \
                       --user=$(id -u):$(id -g) \
                       --privileged \
                       -v /dev/:/dev/ \
                       ${DOCKER_IMAGE} \
                       bash \
                       -c "JLinkExe -Device ${BOARD} \
                                    -SelectEmuBySN ${TARGET} \
                                    -if SWD \
                                    -speed auto \
                                    -AutoConnect 1 \
                                    -CommanderScript ./erase.jlink"
        done
    fi
}


# main execution loop
_main()
{
    if [[ $# -eq 0 ]] ; then
        _print_help;
        exit 0
    fi

    if [[ "${1:-}" =~ ^-h|--help$   ]]
    then
        _print_help;
    else
        _parse "$@";

        if ${CLEAN}
        then
            _force_clean;
        fi

        if ${LIST}
        then
            _list;
            exit 0;
        fi
        _docker;
    fi
    exit 0;
}

# Call `_main` after everything has been defined.
_main "$@"

