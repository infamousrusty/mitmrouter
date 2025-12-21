#!/bin/bash
################################################################################
# MITMRouter v2.1.0 - Test Suite
# Automated testing for all v2.1 features
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MITMROUTER_DIR="$(dirname "${SCRIPT_DIR}")"

# Colors for test output
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_RED='\033[0;31m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_NC='\033[0m'

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test result tracking
declare -a FAILED_TESTS

# Test helper functions
test_assert() {
    local condition="$1"
    local test_name="$2"
    
    ((TESTS_RUN++))
    
    if eval "[[ ${condition} ]]" 2>/dev/null; then
        echo -e "${COLOR_GREEN}✓${COLOR_NC} ${test_name}"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${COLOR_RED}✗${COLOR_NC} ${test_name}"
        ((TESTS_FAILED++))
        FAILED_TESTS+=("${test_name}")
        return 1
    fi
}

test_command_exists() {
    local cmd="$1"
    local test_name="$2"
    
    if command -v "${cmd}" &>/dev/null; then
        test_assert "true" "${test_name}"
    else
        test_assert "false" "${test_name}"
    fi
}

test_file_exists() {
    local file="$1"
    local test_name="$2"
    
    test_assert "-f ${file}" "${test_name}"
}

test_directory_exists() {
    local dir="$1"
    local test_name="$2"
    
    test_assert "-d ${dir}" "${test_name}"
}

# Test Suite 1: Core Dependencies
test_core_dependencies() {
    echo ""
    echo "=========================================="
    echo "Test Suite 1: Core Dependencies"
    echo "=========================================="
    
    test_command_exists "bash" "Bash shell available"
    test_command_exists "hostapd" "hostapd available"
    test_command_exists "dnsmasq" "dnsmasq available"
    test_command_exists "brctl" "bridge-utils (brctl) available"
    test_command_exists "ip" "iproute2 (ip) available"
    test_command_exists "iptables" "iptables available"
    test_command_exists "python3" "Python 3 available"
    test_command_exists "openssl" "OpenSSL available"
}

# Test Suite 2: File Structure
test_file_structure() {
    echo ""
    echo "=========================================="
    echo "Test Suite 2: File Structure"
    echo "=========================================="
    
    test_file_exists "${MITMROUTER_DIR}/mitmrouter.sh" "Main script exists"
    test_file_exists "${MITMROUTER_DIR}/lib/logging.sh" "Logging library exists"
    test_file_exists "${MITMROUTER_DIR}/lib/error_handling.sh" "Error handling library exists"
    test_file_exists "${MITMROUTER_DIR}/lib/config_parser.sh" "Config parser library exists"
    test_file_exists "${MITMROUTER_DIR}/lib/network_setup.sh" "Network setup library exists"
    test_file_exists "${MITMROUTER_DIR}/lib/mitmproxy_manager.sh" "MITMProxy manager library exists"
    test_file_exists "${MITMROUTER_DIR}/lib/monitoring.sh" "Monitoring library exists"
    
    # v2.1 new libraries
    test_file_exists "${MITMROUTER_DIR}/lib/traffic_classifier.sh" "Traffic classifier library exists (v2.1)"
    test_file_exists "${MITMROUTER_DIR}/lib/addon_manager.sh" "Addon manager library exists (v2.1)"
    test_file_exists "${MITMROUTER_DIR}/lib/evidence_export.sh" "Evidence export library exists (v2.1)"
    test_file_exists "${MITMROUTER_DIR}/lib/cert_toolkit.sh" "Certificate toolkit library exists (v2.1)"
    test_file_exists "${MITMROUTER_DIR}/lib/profile_orchestrator.sh" "Profile orchestrator library exists (v2.1)"
}

# Test Suite 3: Configuration Files
test_configuration_files() {
    echo ""
    echo "=========================================="
    echo "Test Suite 3: Configuration Files"
    echo "=========================================="
    
    test_directory_exists "${MITMROUTER_DIR}/config" "Config directory exists"
    test_directory_exists "${MITMROUTER_DIR}/config/profiles" "Profiles directory exists"
    test_file_exists "${MITMROUTER_DIR}/config/profiles/default.yml" "Default profile exists"
}

# Test Suite 4: Traffic Classifier
test_traffic_classifier() {
    echo ""
    echo "=========================================="
    echo "Test Suite 4: Traffic Classifier (v2.1)"
    echo "=========================================="
    
    # Source the library
    source "${MITMROUTER_DIR}/lib/logging.sh" 2>/dev/null || true
    source "${MITMROUTER_DIR}/lib/traffic_classifier.sh" 2>/dev/null || true
    
    # Test function existence
    test_assert "$(type -t initialize_classifier)" "initialize_classifier function exists"
    test_assert "$(type -t start_traffic_classifier)" "start_traffic_classifier function exists"
    test_assert "$(type -t classify_active_flows)" "classify_active_flows function exists"
    test_assert "$(type -t list_classification_rules)" "list_classification_rules function exists"
}

# Test Suite 5: Addon Manager
test_addon_manager() {
    echo ""
    echo "=========================================="
    echo "Test Suite 5: Addon Manager (v2.1)"
    echo "=========================================="
    
    source "${MITMROUTER_DIR}/lib/addon_manager.sh" 2>/dev/null || true
    
    test_assert "$(type -t initialize_addon_manager)" "initialize_addon_manager function exists"
    test_assert "$(type -t load_addons)" "load_addons function exists"
    test_assert "$(type -t install_default_addons)" "install_default_addons function exists"
    test_assert "$(type -t validate_addon)" "validate_addon function exists"
}

# Test Suite 6: Evidence Export
test_evidence_export() {
    echo ""
    echo "=========================================="
    echo "Test Suite 6: Evidence Export (v2.1)"
    echo "=========================================="
    
    source "${MITMROUTER_DIR}/lib/evidence_export.sh" 2>/dev/null || true
    
    test_assert "$(type -t export_evidence_json)" "export_evidence_json function exists"
    test_assert "$(type -t export_evidence_pcap)" "export_evidence_pcap function exists"
    test_assert "$(type -t export_evidence_sqlite)" "export_evidence_sqlite function exists"
    test_assert "$(type -t export_evidence_html)" "export_evidence_html function exists"
    test_assert "$(type -t log_chain_of_custody)" "log_chain_of_custody function exists"
    test_assert "$(type -t verify_evidence_integrity)" "verify_evidence_integrity function exists"
}

# Test Suite 7: Certificate Toolkit
test_cert_toolkit() {
    echo ""
    echo "=========================================="
    echo "Test Suite 7: Certificate Toolkit (v2.1)"
    echo "=========================================="
    
    source "${MITMROUTER_DIR}/lib/cert_toolkit.sh" 2>/dev/null || true
    
    test_assert "$(type -t generate_root_ca)" "generate_root_ca function exists"
    test_assert "$(type -t deploy_pinning_certs)" "deploy_pinning_certs function exists"
    test_assert "$(type -t generate_mobile_certs)" "generate_mobile_certs function exists"
    test_assert "$(type -t start_cert_server)" "start_cert_server function exists"
    test_assert "$(type -t generate_ios_profile)" "generate_ios_profile function exists"
}

# Test Suite 8: Profile Orchestrator
test_profile_orchestrator() {
    echo ""
    echo "=========================================="
    echo "Test Suite 8: Profile Orchestrator (v2.1)"
    echo "=========================================="
    
    source "${MITMROUTER_DIR}/lib/profile_orchestrator.sh" 2>/dev/null || true
    
    test_assert "$(type -t list_available_profiles)" "list_available_profiles function exists"
    test_assert "$(type -t switch_profile)" "switch_profile function exists"
    test_assert "$(type -t compare_profiles)" "compare_profiles function exists"
    test_assert "$(type -t validate_profile)" "validate_profile function exists"
    test_assert "$(type -t clone_profile)" "clone_profile function exists"
}

# Test Suite 9: Integration Tests
test_integration() {
    echo ""
    echo "=========================================="
    echo "Test Suite 9: Integration Tests"
    echo "=========================================="
    
    # Test script syntax
    if bash -n "${MITMROUTER_DIR}/mitmrouter.sh" 2>/dev/null; then
        test_assert "true" "Main script has valid bash syntax"
    else
        test_assert "false" "Main script has valid bash syntax"
    fi
    
    # Test all library scripts
    for lib_file in "${MITMROUTER_DIR}"/lib/*.sh; do
        if bash -n "${lib_file}" 2>/dev/null; then
            test_assert "true" "$(basename ${lib_file}) has valid syntax"
        else
            test_assert "false" "$(basename ${lib_file}) has valid syntax"
        fi
    done
}

# Test Suite 10: Version Check
test_version() {
    echo ""
    echo "=========================================="
    echo "Test Suite 10: Version Check"
    echo "=========================================="
    
    local version=$(grep "MITMROUTER_VERSION=" "${MITMROUTER_DIR}/mitmrouter.sh" | head -n1 | cut -d'"' -f2)
    test_assert "'${version}' == '2.1.0'" "Version is 2.1.0"
}

# Main test runner
run_all_tests() {
    echo "=========================================="
    echo "MITMRouter v2.1.0 Test Suite"
    echo "=========================================="
    echo "Started: $(date)"
    echo ""
    
    test_core_dependencies
    test_file_structure
    test_configuration_files
    test_traffic_classifier
    test_addon_manager
    test_evidence_export
    test_cert_toolkit
    test_profile_orchestrator
    test_integration
    test_version
    
    # Summary
    echo ""
    echo "=========================================="
    echo "Test Summary"
    echo "=========================================="
    echo "Total Tests: ${TESTS_RUN}"
    echo -e "Passed: ${COLOR_GREEN}${TESTS_PASSED}${COLOR_NC}"
    echo -e "Failed: ${COLOR_RED}${TESTS_FAILED}${COLOR_NC}"
    
    if [[ ${TESTS_FAILED} -gt 0 ]]; then
        echo ""
        echo "Failed Tests:"
        for failed_test in "${FAILED_TESTS[@]}"; do
            echo -e "  ${COLOR_RED}✗${COLOR_NC} ${failed_test}"
        done
        echo ""
        echo -e "${COLOR_RED}TEST SUITE FAILED${COLOR_NC}"
        exit 1
    else
        echo ""
        echo -e "${COLOR_GREEN}ALL TESTS PASSED${COLOR_NC}"
        exit 0
    fi
}

# Run tests
run_all_tests
