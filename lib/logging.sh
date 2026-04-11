#!/bin/bash
################################################################################
# MITMRouter Logging System
# Provides structured logging with timestamps and severity levels
################################################################################

# Logging configuration
readonly LOG_DIR="${LOG_DIR:-/var/log/mitmrouter}"
readonly LOG_FILE="${LOG_DIR}/mitmrouter.log"
readonly LOG_LEVEL="${LOG_LEVEL:-INFO}"

# Colour codes for terminal output
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_NC='\033[0m' # No Colour

# Ensure log directory exists
mkdir -p "${LOG_DIR}" 2>/dev/null || true

# Log level hierarchy
declare -A LOG_LEVELS=(
    [DEBUG]=0
    [INFO]=1
    [WARN]=2
    [ERROR]=3
    [CRITICAL]=4
)

# Get current log level numeric value
get_log_level() {
    echo "${LOG_LEVELS[${LOG_LEVEL}]:-1}"
}

# Check if message should be logged
should_log() {
    local message_level="${LOG_LEVELS[$1]:-1}"
    local current_level
    current_level=$(get_log_level)
    [[ ${message_level} -ge ${current_level} ]]
}

# Core logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    if ! should_log "${level}"; then
        return 0
    fi

    local formatted_msg="[${timestamp}] [${level}] ${message}"

    echo "${formatted_msg}" >> "${LOG_FILE}" 2>/dev/null || true

    if [[ -t 2 ]]; then
        case "${level}" in
            DEBUG)    echo -e "${COLOR_BLUE}${formatted_msg}${COLOR_NC}"   >&2 ;;
            INFO)     echo -e "${COLOR_GREEN}${formatted_msg}${COLOR_NC}"  >&2 ;;
            WARN)     echo -e "${COLOR_YELLOW}${formatted_msg}${COLOR_NC}" >&2 ;;
            ERROR|CRITICAL) echo -e "${COLOR_RED}${formatted_msg}${COLOR_NC}" >&2 ;;
        esac
    else
        echo "${formatted_msg}" >&2
    fi
}

# Convenience logging functions
log_debug()    { log DEBUG    "$@"; }
log_info()     { log INFO     "$@"; }
log_warn()     { log WARN     "$@"; }
log_error()    { log ERROR    "$@"; }
log_critical() { log CRITICAL "$@"; }

# Log success (green INFO message)
log_success() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local message="[${timestamp}] [SUCCESS] $*"

    echo "${message}" >> "${LOG_FILE}" 2>/dev/null || true

    if [[ -t 2 ]]; then
        echo -e "${COLOR_GREEN}${message}${COLOR_NC}" >&2
    else
        echo "${message}" >&2
    fi
}

# Log command execution for debugging
log_command() {
    local cmd="$*"
    log_debug "Executing: ${cmd}"
    eval "${cmd}"
}

# Rotate log files
rotate_logs() {
    local max_size=$((100 * 1024)) # 100 MB

    if [[ -f "${LOG_FILE}" ]]; then
        local size
        size=$(stat -f%z "${LOG_FILE}" 2>/dev/null || stat -c%s "${LOG_FILE}")

        if [[ ${size} -gt ${max_size} ]]; then
            local timestamp
            timestamp=$(date +%Y%m%d_%H%M%S)
            mv "${LOG_FILE}" "${LOG_FILE}.${timestamp}"
            gzip "${LOG_FILE}.${timestamp}" &>/dev/null || true
        fi
    fi
}

# Initialize logging on script start
initialize_logging() {
    mkdir -p "${LOG_DIR}"
    chmod 755 "${LOG_DIR}"
    touch "${LOG_FILE}"
    chmod 644 "${LOG_FILE}"
    log_info "========================================="
    log_info "MITMRouter started at $(date)"
    log_info "Log level: ${LOG_LEVEL}"
    log_info "Log file:  ${LOG_FILE}"
    log_info "========================================="
}

# Call on script load
initialize_logging
