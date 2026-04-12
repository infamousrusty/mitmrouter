#!/bin/bash
################################################################################
# MITMRouter v2.1.0 - Evidence Export Engine
# Multi-format export with chain-of-custody and integrity verification
################################################################################

readonly EXPORT_DIR="${EVIDENCE_DIR}/exports"
readonly COC_LOG="${STATE_DIR}/chain_of_custody.log"
# EXPORT_METADATA is read by external reporting pipelines; export it.
export EXPORT_METADATA="${EXPORT_DIR}/.metadata"

initialize_evidence_export() {
    log_info "Initialising evidence export engine..."
    mkdir -p "${EXPORT_DIR}"
    chmod 700 "${EXPORT_DIR}"
    if [[ ! -f "${COC_LOG}" ]]; then
        cat > "${COC_LOG}" << EOF
# MITMRouter v2.1.0 Chain of Custody Log
# Format: timestamp|action|file|hash|operator
# Initialised: $(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
        chmod 600 "${COC_LOG}"
    fi
    log_success "Evidence export engine initialised"
    return 0
}

export_evidence_json() {
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local output_file="${EXPORT_DIR}/evidence_${timestamp}.json"
    log_info "Exporting evidence to JSON: ${output_file}"

    cat > "${output_file}" << EOF
{
  "metadata": {
    "version": "${MITMROUTER_VERSION}",
    "export_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "profile": "$(cat "${STATE_DIR}/active_profile" 2>/dev/null || echo 'unknown')",
    "operator": "${SUDO_USER:-${USER}}",
    "hostname": "$(hostname)",
    "export_format": "json"
  },
  "evidence": {
EOF

    if [[ -f "${EVIDENCE_DIR}/requests.jsonl" ]]; then
        echo '    "http_requests": [' >> "${output_file}"
        local first=true
        while read -r line; do
            [[ "${first}" == "true" ]] && first=false || echo "," >> "${output_file}"
            echo "      ${line}" >> "${output_file}"
        done < "${EVIDENCE_DIR}/requests.jsonl"
        echo '    ],' >> "${output_file}"
    fi

    if [[ -f "${EVIDENCE_DIR}/tls_connections.jsonl" ]]; then
        echo '    "tls_connections": [' >> "${output_file}"
        local first=true
        while read -r line; do
            [[ "${first}" == "true" ]] && first=false || echo "," >> "${output_file}"
            echo "      ${line}" >> "${output_file}"
        done < "${EVIDENCE_DIR}/tls_connections.jsonl"
        echo '    ],' >> "${output_file}"
    fi

    if [[ -f "${CLASSIFIER_STATE_DIR}/flows.log" ]]; then
        echo '    "classifications": [' >> "${output_file}"
        local first=true
        while IFS='|' read -r ts remote class; do
            [[ "${first}" == "true" ]] && first=false || echo "," >> "${output_file}"
            cat >> "${output_file}" << INNER_EOF
      {
        "timestamp": "${ts}",
        "remote_address": "${remote}",
        "classification": "${class}"
      }
INNER_EOF
        done < "${CLASSIFIER_STATE_DIR}/flows.log"
        echo '    ]' >> "${output_file}"
    fi

    cat >> "${output_file}" << EOF
  },
  "integrity": {
    "sha256": ""
  }
}
EOF

    local file_hash
    file_hash=$(sha256sum "${output_file}" | awk '{print $1}')
    sed -i "s/\"sha256\": \"\"/\"sha256\": \"${file_hash}\"/" "${output_file}"
    log_chain_of_custody "EXPORT" "${output_file}" "${file_hash}"

    if command -v gpg &>/dev/null && [[ -n "${evidence_gpg_key:-}" ]]; then
        gpg --armor --detach-sign --default-key "${evidence_gpg_key}" "${output_file}" 2>/dev/null && \
            log_success "GPG signature created: ${output_file}.asc"
    fi

    log_success "Evidence exported: ${output_file}"
    echo "${output_file}"
    return 0
}

export_evidence_pcap() {
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local output_file="${EXPORT_DIR}/capture_${timestamp}.pcap"
    local interface="${network_bridge_name:-br0}"
    log_info "Exporting PCAP capture from ${interface}"

    if ! command -v tcpdump &>/dev/null; then
        log_error "tcpdump not found - install with: apt-get install tcpdump"
        return 1
    fi

    local duration="${pcap_capture_duration:-60}"
    log_info "Capturing traffic for ${duration} seconds..."
    timeout "${duration}" tcpdump -i "${interface}" -w "${output_file}" 2>/dev/null || {
        log_warn "PCAP capture completed (may have timed out)"
    }

    if [[ -f "${output_file}" ]]; then
        local file_hash
        file_hash=$(sha256sum "${output_file}" | awk '{print $1}')
        log_chain_of_custody "PCAP_EXPORT" "${output_file}" "${file_hash}"
        log_success "PCAP exported: ${output_file}"
        echo "${output_file}"
        return 0
    else
        log_error "PCAP export failed"
        return 1
    fi
}

export_evidence_sqlite() {
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local output_file="${EXPORT_DIR}/evidence_${timestamp}.db"
    log_info "Exporting evidence to SQLite: ${output_file}"

    if ! command -v sqlite3 &>/dev/null; then
        log_error "sqlite3 not found - install with: apt-get install sqlite3"
        return 1
    fi

    sqlite3 "${output_file}" << 'SQL_EOF'
CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT);
CREATE TABLE http_requests (id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp TEXT, method TEXT, url TEXT, host TEXT, port INTEGER, path TEXT, content_length INTEGER);
CREATE TABLE tls_connections (id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp TEXT, sni TEXT, cipher TEXT, tls_version TEXT);
CREATE TABLE classifications (id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp TEXT, remote_address TEXT, protocol TEXT, device_type TEXT, tags TEXT);
CREATE TABLE chain_of_custody (id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp TEXT, action TEXT, file TEXT, hash TEXT, operator TEXT);
SQL_EOF

    sqlite3 "${output_file}" << SQL_EOF
INSERT INTO metadata VALUES ('version', '${MITMROUTER_VERSION}');
INSERT INTO metadata VALUES ('export_timestamp', '$(date -u +%Y-%m-%dT%H:%M:%SZ)');
INSERT INTO metadata VALUES ('profile', '$(cat "${STATE_DIR}/active_profile" 2>/dev/null || echo "unknown")');
INSERT INTO metadata VALUES ('operator', '${SUDO_USER:-${USER}}');
INSERT INTO metadata VALUES ('hostname', '$(hostname)');
SQL_EOF

    if [[ -f "${EVIDENCE_DIR}/requests.jsonl" ]]; then
        log_debug "Importing HTTP requests into SQLite..."
        while read -r line; do
            local ts method url host port path content_len
            ts=$(echo "$line"  | jq -r '.timestamp // "unknown"')
            method=$(echo "$line" | jq -r '.method // "unknown"')
            url=$(echo "$line"    | jq -r '.url // "unknown"')
            host=$(echo "$line"   | jq -r '.host // "unknown"')
            port=$(echo "$line"   | jq -r '.port // 0')
            path=$(echo "$line"   | jq -r '.path // "unknown"')
            content_len=$(echo "$line" | jq -r '.content_length // 0')
            sqlite3 "${output_file}" \
                "INSERT INTO http_requests (timestamp,method,url,host,port,path,content_length) VALUES ('${ts}','${method}','${url}','${host}',${port},'${path}',${content_len});"
        done < "${EVIDENCE_DIR}/requests.jsonl"
    fi

    if [[ -f "${EVIDENCE_DIR}/tls_connections.jsonl" ]]; then
        log_debug "Importing TLS connections into SQLite..."
        while read -r line; do
            local ts sni cipher tls_ver
            ts=$(echo "$line"     | jq -r '.timestamp // "unknown"')
            sni=$(echo "$line"    | jq -r '.sni // "unknown"')
            cipher=$(echo "$line" | jq -r '.cipher // "unknown"')
            tls_ver=$(echo "$line" | jq -r '.tls_version // "unknown"')
            sqlite3 "${output_file}" \
                "INSERT INTO tls_connections (timestamp,sni,cipher,tls_version) VALUES ('${ts}','${sni}','${cipher}','${tls_ver}');"
        done < "${EVIDENCE_DIR}/tls_connections.jsonl"
    fi

    if [[ -f "${CLASSIFIER_STATE_DIR}/flows.log" ]]; then
        log_debug "Importing classifications into SQLite..."
        while IFS='|' read -r ts remote classification; do
            local protocol device tags
            IFS='|' read -r protocol device tags <<< "${classification}"
            sqlite3 "${output_file}" \
                "INSERT INTO classifications (timestamp,remote_address,protocol,device_type,tags) VALUES ('${ts}','${remote}','${protocol}','${device}','${tags}');"
        done < "${CLASSIFIER_STATE_DIR}/flows.log"
    fi

    if [[ -f "${COC_LOG}" ]]; then
        grep -v '^#' "${COC_LOG}" | while IFS='|' read -r ts action file hash operator; do
            [[ -z "${ts}" ]] && continue
            sqlite3 "${output_file}" \
                "INSERT INTO chain_of_custody (timestamp,action,file,hash,operator) VALUES ('${ts}','${action}','${file}','${hash}','${operator}');"
        done
    fi

    local file_hash
    file_hash=$(sha256sum "${output_file}" | awk '{print $1}')
    sqlite3 "${output_file}" "INSERT INTO metadata VALUES ('sha256', '${file_hash}');"
    log_chain_of_custody "SQLITE_EXPORT" "${output_file}" "${file_hash}"
    log_success "SQLite database exported: ${output_file}"
    echo "${output_file}"
    return 0
}

export_evidence_html() {
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local output_file="${EXPORT_DIR}/report_${timestamp}.html"
    log_info "Generating HTML report: ${output_file}"

    cat > "${output_file}" << 'HTML_EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>MITMRouter Evidence Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 20px; box-shadow: 0 2px 5px rgba(0,0,0,0.1); }
        h1 { color: #333; border-bottom: 3px solid #007bff; padding-bottom: 10px; }
        h2 { color: #555; margin-top: 30px; border-bottom: 1px solid #ddd; padding-bottom: 5px; }
        table { width: 100%; border-collapse: collapse; margin: 15px 0; }
        th, td { padding: 10px; text-align: left; border: 1px solid #ddd; }
        th { background: #007bff; color: white; }
        tr:nth-child(even) { background: #f9f9f9; }
        .metadata { background: #e7f3ff; padding: 15px; border-radius: 5px; margin: 15px 0; }
        .hash { font-family: monospace; font-size: 0.9em; color: #666; word-break: break-all; }
        .footer { margin-top: 40px; text-align: center; color: #777; font-size: 0.9em; border-top: 1px solid #ddd; padding-top: 20px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>&#x1F512; MITMRouter Evidence Report</h1>
        <div class="metadata">
            <h2>Report Metadata</h2>
HTML_EOF

    cat >> "${output_file}" << HTML_EOF
            <p><strong>Version:</strong> ${MITMROUTER_VERSION}</p>
            <p><strong>Generated:</strong> $(date -u +%Y-%m-%dT%H:%M:%SZ)</p>
            <p><strong>Profile:</strong> $(cat "${STATE_DIR}/active_profile" 2>/dev/null || echo 'unknown')</p>
            <p><strong>Operator:</strong> ${SUDO_USER:-${USER}}</p>
            <p><strong>Hostname:</strong> $(hostname)</p>
HTML_EOF
    echo '        </div>' >> "${output_file}"

    if [[ -f "${EVIDENCE_DIR}/requests.jsonl" ]]; then
        local request_count
        request_count=$(wc -l < "${EVIDENCE_DIR}/requests.jsonl")
        cat >> "${output_file}" << HTML_EOF
        <h2>HTTP Requests (${request_count} total)</h2>
        <table><tr><th>Timestamp</th><th>Method</th><th>Host</th><th>Path</th><th>Size</th></tr>
HTML_EOF
        head -n 100 "${EVIDENCE_DIR}/requests.jsonl" | while read -r line; do
            local ts method host path size
            ts=$(echo "$line"     | jq -r '.timestamp // "unknown"')
            method=$(echo "$line" | jq -r '.method // "unknown"')
            host=$(echo "$line"   | jq -r '.host // "unknown"')
            path=$(echo "$line"   | jq -r '.path // "unknown"')
            size=$(echo "$line"   | jq -r '.content_length // 0')
            echo "            <tr><td>${ts}</td><td>${method}</td><td>${host}</td><td>${path}</td><td>${size} bytes</td></tr>" >> "${output_file}"
        done
        echo '        </table>' >> "${output_file}"
        if [[ ${request_count} -gt 100 ]]; then
            echo "        <p><em>Showing first 100 of ${request_count} requests</em></p>" >> "${output_file}"
        fi
    fi

    if [[ -f "${CLASSIFIER_STATE_DIR}/flows.log" ]]; then
        local class_count
        class_count=$(wc -l < "${CLASSIFIER_STATE_DIR}/flows.log")
        cat >> "${output_file}" << HTML_EOF
        <h2>Traffic Classifications (${class_count} total)</h2>
        <table><tr><th>Timestamp</th><th>Remote Address</th><th>Protocol</th><th>Device Type</th><th>Tags</th></tr>
HTML_EOF
        head -n 100 "${CLASSIFIER_STATE_DIR}/flows.log" | while IFS='|' read -r ts remote classification; do
            local protocol device tags
            IFS='|' read -r protocol device tags <<< "${classification}"
            echo "            <tr><td>${ts}</td><td>${remote}</td><td>${protocol}</td><td>${device}</td><td>${tags}</td></tr>" >> "${output_file}"
        done
        echo '        </table>' >> "${output_file}"
    fi

    if [[ -f "${COC_LOG}" ]]; then
        cat >> "${output_file}" << HTML_EOF
        <h2>Chain of Custody</h2>
        <table><tr><th>Timestamp</th><th>Action</th><th>File</th><th>Hash (SHA-256)</th></tr>
HTML_EOF
        grep -v '^#' "${COC_LOG}" | while IFS='|' read -r ts action file hash _operator; do
            [[ -z "${ts}" ]] && continue
            echo "            <tr><td>${ts}</td><td>${action}</td><td>${file}</td><td class=\"hash\">${hash}</td></tr>" >> "${output_file}"
        done
        echo '        </table>' >> "${output_file}"
    fi

    cat >> "${output_file}" << HTML_EOF
        <div class="footer">
            <p>Generated by MITMRouter v${MITMROUTER_VERSION}</p>
        </div>
    </div>
</body>
</html>
HTML_EOF

    local file_hash
    file_hash=$(sha256sum "${output_file}" | awk '{print $1}')
    log_chain_of_custody "HTML_EXPORT" "${output_file}" "${file_hash}"
    log_success "HTML report generated: ${output_file}"
    echo "${output_file}"
    return 0
}

log_chain_of_custody() {
    local action="$1"
    local file="$2"
    local hash="$3"
    local operator="${SUDO_USER:-${USER}}"
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    echo "${timestamp}|${action}|${file}|${hash}|${operator}" >> "${COC_LOG}"
    log_debug "Chain-of-custody logged: ${action} - ${file}"
}

verify_evidence_integrity() {
    local evidence_file="$1"
    if [[ ! -f "${evidence_file}" ]]; then
        log_error "Evidence file not found: ${evidence_file}"
        return 1
    fi
    local current_hash
    current_hash=$(sha256sum "${evidence_file}" | awk '{print $1}')
    local recorded_hash
    recorded_hash=$(grep "${evidence_file}" "${COC_LOG}" | tail -n1 | cut -d'|' -f4)
    if [[ "${current_hash}" == "${recorded_hash}" ]]; then
        log_success "Evidence integrity verified: ${evidence_file}"
        return 0
    else
        log_error "Evidence integrity FAILED: ${evidence_file}"
        log_error "Current hash:  ${current_hash}"
        log_error "Recorded hash: ${recorded_hash}"
        return 1
    fi
}

initialize_evidence_export
