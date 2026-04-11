#!/bin/bash
################################################################################
# MITMRouter Error Handling System
# Provides centralised error handling, trapping, and recovery
################################################################################

set -o pipefail

# Global error state
# Exported so trap handlers and sub-processes can read / set them.
declare -gx LAST_ERROR=""
declare -g  ERROR_COUNT=0
declare -gx SCRIPT_FAILED=0

# Error trap handler
trap_error() {
    local line_number=$1
    local exit_code=$2

    log_error "Error on line ${line_number} (exit code: ${exit_code})"
    (( ERROR_COUNT++ ))

    if [[ -n "${BASH_SOURCE[1]:-}" ]]; then
        log_error "Location: ${BASH_SOURCE[1]}:${line_number}"
    fi

    LAST_ERROR="Error at line ${line_number} with exit code ${exit_code}"
    SCRIPT_FAILED=1
    return 0
}

# Exit trap handler for cleanup
trap_exit() {
    local exit_code=$?
    if [[ ${exit_code} -ne 0 ]]; then
        log_error "Script exiting with code: ${exit_code}"
    else
        log_info "Script completed successfully"
    fi
    cleanup_on_exit
}

# Cleanup function — override in your script as needed
cleanup_on_exit() {
    return 0
}

# Register traps
set -E
trap 'trap_error ${LINENO} $?' ERR
trap trap_exit EXIT

# Execute command with error handling
try_run() {
    local cmd="$*"
    log_debug "Running: ${cmd}"
    if eval "${cmd}"; then
        log_debug "Command succeeded: ${cmd}"
        return 0
    else
        local exit_code=$?
        log_error "Command failed (exit code: ${exit_code}): ${cmd}"
        return ${exit_code}
    fi
}

# Execute command with retry logic
try_run_with_retry() {
    local max_attempts="${1:-3}"
    local delay="${2:-2}"
    shift 2
    local cmd="$*"

    local attempt=1
    while [[ ${attempt} -le ${max_attempts} ]]; do
        log_info "Attempt ${attempt}/${max_attempts}: ${cmd}"
        if eval "${cmd}"; then
            log_success "Command succeeded on attempt ${attempt}"
            return 0
        fi
        if [[ ${attempt} -lt ${max_attempts} ]]; then
            log_warn "Attempt ${attempt} failed, retrying in ${delay}s..."
            sleep "${delay}"
        fi
        (( attempt++ ))
    done

    log_error "Command failed after ${max_attempts} attempts: ${cmd}"
    return 1
}

# Check command exists
require_command() {
    local cmd="$1"
    if ! command -v "${cmd}" &>/dev/null; then
        log_error "Required command not found: ${cmd}"
        return 1
    fi
    return 0
}

# Check file exists and is readable
require_file() {
    local file="$1"
    if [[ ! -r "${file}" ]]; then
        log_error "Required file not found or not readable: ${file}"
        return 1
    fi
    return 0
}

# Check directory exists and is writable
require_directory() {
    local dir="$1"
    if [[ ! -w "${dir}" ]]; then
        log_error "Required directory not found or not writable: ${dir}"
        return 1
    fi
    return 0
}

# Verify command output
verify_output() {
    local cmd="$1"
    local expected_pattern="$2"
    local output
    output=$(eval "${cmd}" 2>&1) || return 1
    if [[ ${output} =~ ${expected_pattern} ]]; then
        return 0
    else
        log_error "Output verification failed. Expected pattern: ${expected_pattern}"
        log_error "Actual output: ${output}"
        return 1
    fi
}

# Assert condition is true
assert() {
    local condition="$1"
    local message="${2:-Assertion failed: ${condition}}"
    if ! eval "[[ ${condition} ]]" 2>/dev/null; then
        log_error "${message}"
        return 1
    fi
    return 0
}

# Handle error and optionally exit
handle_error() {
    local message="$1"
    local should_exit="${2:-true}"
    log_error "${message}"
    (( ERROR_COUNT++ ))
    SCRIPT_FAILED=1
    if [[ "${should_exit}" == "true" ]]; then
        exit 1
    fi
    return 1
}

# Get error count
get_error_count()  { echo "${ERROR_COUNT}"; }
reset_error_count() { ERROR_COUNT=0; }
had_errors()        { [[ ${ERROR_COUNT} -gt 0 ]]; }
