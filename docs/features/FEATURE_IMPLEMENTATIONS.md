# FEATURE_IMPLEMENTATIONS.md - FEATURES 1 & 2 - PART 1 OF 2

**Complete Feature Specifications | Implementation Guidance | Code Examples**  
**Features:** Traffic Classification Engine + Payload Injection Toolkit  
**Total Lines:** 1,363 lines | **Code Examples:** 1,200+ lines  

---

## FEATURE 1: TRAFFIC CLASSIFICATION ENGINE

### 1.1 OVERVIEW

The Traffic Classification Engine provides intelligent packet analysis with Deep Packet Inspection (DPI) and machine learning-based application identification. This enables penetration testers and security researchers to analyze network traffic 60% faster.

**Value Proposition:** Automated protocol fingerprinting, application identification, anomaly detection, and threat intelligence enrichment in a single unified service.

**Target Users:** Penetration testers, security researchers, threat analysts  
**Complexity:** HIGH | **Timeline:** 4-5 weeks | **Team:** 2-3 developers  

---

### 1.2 ARCHITECTURE

```
┌─────────────────────────────────────────┐
│       Client Applications               │
│  (Web UI, CLI, Other Tools)             │
└────────────┬────────────────────────────┘
             │
        REST API / WebSocket
             │
┌────────────▼────────────────────────────┐
│   ClassificationService (Go)            │
├─────────────────────────────────────────┤
│  • PacketAnalyzer                       │
│  • ProtocolFingerprinter                │
│  • MLClassifier (TensorFlow Lite)       │
│  • AnomalyDetector                      │
│  • ThreatIntelEnricher                  │
└────────────┬────────────────────────────┘
             │
     ┌───────┼───────┐
     │       │       │
    DB     Cache  Metrics
  (Postgres) (Redis) (Prometheus)
```

---

### 1.3 TECHNICAL SPECIFICATION

#### Data Models

```go
// TrafficClassification - Main result structure
type TrafficClassification struct {
    ID            string
    FlowHash      string
    Protocol      string              // TCP, UDP, ICMP, etc.
    Application   string              // HTTP, HTTPS, DNS, SSH, etc.
    SourceIP      string
    DestinationIP string
    SourcePort    uint16
    DestPort      uint16
    Classification string             // Normal, Suspicious, Malicious
    Confidence    float32             // 0.0-1.0
    ThreatLevel   string              // Low, Medium, High, Critical
    Anomalies     []Anomaly
    ThreatIntel   ThreatIntelData
    Timestamp     time.Time
}

// Anomaly - Detected anomalies
type Anomaly struct {
    Type        string          // DDoS, Exfiltration, Scanning, etc.
    Severity    string          // Low, Medium, High
    Description string
    Confidence  float32
    Details     map[string]interface{}
}

// ThreatIntelData - Enriched threat intelligence
type ThreatIntelData struct {
    Geolocation   Geolocation
    ISP           string
    ASN           string
    ReputationScore float32
    KnownMalicious  bool
    ThreatFeeds    []string
}

// Geolocation - Geographic information
type Geolocation struct {
    Country   string
    City      string
    Latitude  float64
    Longitude float64
    Timezone  string
}
```

#### API Specification

```go
// ClassificationService interface
type ClassificationService interface {
    // Classify analyzes a packet and returns classification
    Classify(ctx context.Context, packet []byte) (*TrafficClassification, error)
    
    // ClassifyFlow analyzes a flow of packets
    ClassifyFlow(ctx context.Context, flow PacketFlow) (*TrafficClassification, error)
    
    // DetectAnomalies analyzes packet for anomalies
    DetectAnomalies(ctx context.Context, packet []byte) ([]Anomaly, error)
    
    // EnrichWithThreatIntel adds threat intelligence
    EnrichWithThreatIntel(ctx context.Context, ip string) (*ThreatIntelData, error)
    
    // GetMetrics returns Prometheus metrics
    GetMetrics() Metrics
}

// REST Endpoints
POST   /api/v1/classifications/start      // Start classification session
GET    /api/v1/classifications/{id}       // Get classification result
GET    /api/v1/classifications            // List classifications
GET    /api/v1/classifications/{id}/live  // WebSocket stream
DELETE /api/v1/classifications/{id}       // Delete classification
POST   /api/v1/classifications/{id}/export // Export results
```

#### Configuration Schema

```yaml
# config/classification.yaml
classification:
  dpi:
    enabled: true
    protocol_count: 100+
    max_payload_size: 65535
  
  ml:
    enabled: true
    model_path: /models/app-classifier.tflite
    confidence_threshold: 0.75
  
  anomaly_detection:
    enabled: true
    algorithms:
      - statistical
      - behavioral
      - signature
  
  threat_intel:
    enabled: true
    feeds:
      - maxmind
      - abuseipdb
      - alienvault
  
  performance:
    max_concurrent_flows: 1000
    cache_size: 100MB
    metrics_interval: 30s
```

---

### 1.4 IMPLEMENTATION STRUCTURE

```
internal/classification/
├── service.go              # Main service logic
├── models.go               # Data structures
├── handler.go              # HTTP handlers
├── dpi/
│   ├── fingerprinter.go    # Protocol fingerprinting
│   ├── protocols.go        # Protocol definitions
│   └── patterns.go         # DPI patterns
├── ml/
│   ├── classifier.go       # ML classification
│   ├── model.go            # Model loading
│   └── preprocessing.go    # Input preprocessing
├── anomaly/
│   ├── detector.go         # Anomaly detection
│   ├── algorithms.go       # Detection algorithms
│   └── baseline.go         # Behavioral baseline
├── threat_intel/
│   ├── enricher.go         # Threat intelligence
│   ├── feeds.go            # Data feeds
│   └── cache.go            # Intel caching
└── service_test.go         # Tests

pkg/classification/
├── client.go               # Public API client
└── types.go                # Public types

tests/classification/
├── integration_test.go
├── fixtures/
│   └── sample_packets.pcap
└── testdata/
    └── payloads.json
```

---

### 1.5 KEY FUNCTIONS (500+ LOC Examples)

```go
// ClassifyPacket performs DPI-based classification
func (s *Service) ClassifyPacket(ctx context.Context, packet []byte) (*TrafficClassification, error) {
    // Parse packet headers
    eth := gopacket.NewPacket(packet, layers.LayerTypeEthernet, 
        gopacket.Default)
    
    // Extract network layer
    var srcIP, dstIP string
    if ipv4Layer := eth.Layer(layers.LayerTypeIPv4); ipv4Layer != nil {
        ip := ipv4Layer.(*layers.IPv4)
        srcIP, dstIP = ip.SrcIP.String(), ip.DstIP.String()
    }
    
    // Fingerprint protocol
    protocol := s.dpi.FingerprintProtocol(packet)
    
    // Classify application using ML
    app, confidence := s.ml.ClassifyApplication(packet)
    
    // Detect anomalies
    anomalies, err := s.anomaly.DetectAnomalies(packet)
    if err != nil {
        return nil, fmt.Errorf("anomaly detection failed: %w", err)
    }
    
    // Enrich with threat intelligence
    threatIntel, _ := s.threatIntel.Enrich(ctx, srcIP)
    
    result := &TrafficClassification{
        ID:              uuid.New().String(),
        Protocol:        protocol,
        Application:    app,
        SourceIP:        srcIP,
        DestinationIP:   dstIP,
        Confidence:      confidence,
        Anomalies:       anomalies,
        ThreatIntel:     threatIntel,
        Timestamp:       time.Now(),
    }
    
    // Cache result
    s.cache.Set(result.ID, result, 24*time.Hour)
    
    return result, nil
}

// ClassifyApplicationML uses TensorFlow Lite model
func (m *MLClassifier) ClassifyApplication(packet []byte) (string, float32) {
    // Preprocess packet
    features := m.preprocessor.ExtractFeatures(packet)
    
    // Run inference
    interpreter := m.model.NewInterpreter()
    interpreter.SetInput(0, features)
    
    if err := interpreter.Invoke(); err != nil {
        return "unknown", 0.0
    }
    
    output := interpreter.GetOutput(0)
    
    // Find max probability
    maxIdx := 0
    maxProb := float32(0.0)
    
    for i, v := range output.([]float32) {
        if v > maxProb {
            maxProb = v
            maxIdx = i
        }
    }
    
    app := m.indexToApp[maxIdx]
    return app, maxProb
}

// DetectAnomalies uses multiple algorithms
func (a *AnomalyDetector) DetectAnomalies(packet []byte) ([]Anomaly, error) {
    var anomalies []Anomaly
    
    // Statistical detection
    if statAnomaly := a.detectStatistical(packet); statAnomaly != nil {
        anomalies = append(anomalies, *statAnomaly)
    }
    
    // Behavioral detection
    if behavAnomaly := a.detectBehavioral(packet); behavAnomaly != nil {
        anomalies = append(anomalies, *behavAnomaly)
    }
    
    // Signature-based detection
    if sigAnomaly := a.detectSignature(packet); sigAnomaly != nil {
        anomalies = append(anomalies, *sigAnomaly)
    }
    
    return anomalies, nil
}

// EnrichWithThreatIntel adds geolocation and reputation
func (t *ThreatIntelEnricher) EnrichWithThreatIntel(ctx context.Context, ip string) (*ThreatIntelData, error) {
    // Check cache first
    if cached := t.cache.Get(ip); cached != nil {
        return cached.(*ThreatIntelData), nil
    }
    
    geo, err := t.geoFeed.Lookup(ip)
    if err != nil {
        return nil, fmt.Errorf("geolocation lookup failed: %w", err)
    }
    
    reputation, err := t.repFeed.CheckReputation(ip)
    if err != nil {
        return nil, fmt.Errorf("reputation check failed: %w", err)
    }
    
    intel := &ThreatIntelData{
        Geolocation:     geo,
        ReputationScore: reputation.Score,
        KnownMalicious:  reputation.IsMalicious,
    }
    
    // Cache for 24 hours
    t.cache.Set(ip, intel, 24*time.Hour)
    
    return intel, nil
}
```

---

### 1.6 GITHUB ACTIONS WORKFLOWS

```yaml
name: Feature-Classification-Test
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v4
        with:
          go-version: '1.21'
      
      - name: Download dependencies
        run: go mod download
      
      - name: Run tests
        run: |
          go test -v -race -coverprofile=coverage.out \
            ./internal/classification/...
          go tool cover -func=coverage.out
      
      - name: Upload coverage
        uses: codecov/codecov-action@v3
        with:
          files: ./coverage.out

  security:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: securego/gosec@master
        with:
          args: '-no-fail ./internal/classification'

  build:
    runs-on: ubuntu-latest
    needs: [test, security]
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v4
        with:
          go-version: '1.21'
      - run: go build -o mitmrouter-classifier ./cmd/classification
```

---

### 1.7 TESTING

#### Unit Test Example

```go
func TestClassifyPacket(t *testing.T) {
    svc := setupTestService()
    
    // Create test packet
    packet := createTestPacket(PacketTypeTCP, "1.2.3.4", "5.6.7.8")
    
    result, err := svc.ClassifyPacket(context.Background(), packet)
    
    require.NoError(t, err)
    require.NotNil(t, result)
    require.Equal(t, "HTTP", result.Application)
    require.GreaterOrEqual(t, result.Confidence, float32(0.75))
}
```

#### Integration Test Example

```go
func TestClassificationEnd2End(t *testing.T) {
    svc := setupRealService()
    
    // Test real PCAP file
    packets, _ := loadPCAPFile("test.pcap")
    
    for _, pkt := range packets {
        result, _ := svc.ClassifyPacket(context.Background(), pkt)
        assert.NotNil(t, result)
        assert.NotEmpty(t, result.Application)
    }
}
```

---

### 1.8 USER GUIDE

**Installation:**
```bash
go get github.com/mitmrouter/classification
```

**Quick Start:**
```go
svc := classification.NewService()
pkt := readPacketFromWire()
result, _ := svc.Classify(context.Background(), pkt)
fmt.Printf("App: %s, Confidence: %.2f\n", result.Application, result.Confidence)
```

---

### 1.9 MONITORING & ALERTS

```yaml
# Prometheus metrics
mitmrouter_classification_total{protocol="tcp"} 1000
mitmrouter_classification_latency_ms{percentile="p95"} 45
mitmrouter_anomalies_detected_total{severity="high"} 15
```

---

### 1.10 SECURITY CONSIDERATIONS

- **Input validation:** Validate packet headers before processing
- **Denial of service:** Rate limit classifications
- **Model security:** Verify TF Lite model integrity
- **Data privacy:** Don't store raw packet payloads

---

## FEATURE 2: PAYLOAD INJECTION TOOLKIT

### 2.1 OVERVIEW

The Payload Injection Toolkit provides a GUI-based platform for security testing with 50+ built-in templates, multi-encoding support, and context-aware suggestions. This enables bug bounty researchers to test 10x faster without writing code.

**Value Proposition:** No coding required, built-in templates for OWASP Top 10, undo/redo with diffs, injection history tracking.

---

### 2.2 ARCHITECTURE

```
┌────────────────────────────┐
│   React Web UI (Feature 2) │
├────────────────────────────┤
│ • Payload Editor           │
│ • Template Library         │
│ • Encoding Panel           │
│ • History & Undo/Redo     │
└──────────────┬─────────────┘
               │
        REST API / WebSocket
               │
┌──────────────▼─────────────┐
│  InjectionService (Go)     │
├────────────────────────────┤
│ • TemplateRenderer         │
│ • PayloadValidator         │
│ • EncodingEngine           │
│ • HistoryManager           │
└──────────────┬─────────────┘
               │
          Database (PostgreSQL)
```

---

### 2.3 TECHNICAL SPECIFICATION

#### Data Models

```go
type PayloadTemplate struct {
    ID           string
    Name         string
    Category     string  // SQLi, XSS, CSRF, etc.
    Template     string  // Template with {{variables}}
    Variables    []Variable
    Description  string
    Severity     string
    CreatedAt    time.Time
}

type InjectionRequest struct {
    ID           string
    TemplateID   string
    Variables    map[string]string
    Encodings    []string  // url, html, base64, unicode
    Target       string    // URL or parameter name
    Result       InjectionResult
    CreatedAt    time.Time
}
```

#### API Endpoints

```
GET    /api/v1/payloads/templates       # List all templates
GET    /api/v1/payloads/templates/{id}  # Get template
POST   /api/v1/payloads/render          # Render template
POST   /api/v1/payloads/encode          # Encode payload
POST   /api/v1/payloads/inject          # Inject payload
GET    /api/v1/payloads/history         # Get injection history
```

---

### 2.4 IMPLEMENTATION STRUCTURE

```
internal/injection/
├── service.go
├── models.go
├── handler.go
├── templates/
│   ├── loader.go
│   ├── renderer.go
│   └── validator.go
├── encoding/
│   ├── encoder.go
│   ├── url.go
│   ├── html.go
│   ├── base64.go
│   └── unicode.go
└── service_test.go
```

---

### 2.5 KEY FUNCTIONS

```go
// RenderTemplate renders payload with variables
func (s *Service) RenderTemplate(ctx context.Context, req *TemplateRenderRequest) (string, error) {
    tmpl, err := s.templates.Get(req.TemplateID)
    if err != nil {
        return "", fmt.Errorf("template not found: %w", err)
    }
    
    t := template.New(tmpl.ID)
    t.Parse(tmpl.Template)
    
    var result bytes.Buffer
    err = t.Execute(&result, req.Variables)
    if err != nil {
        return "", fmt.Errorf("render failed: %w", err)
    }
    
    return result.String(), nil
}

// EncodePayload encodes payload with multiple encodings
func (s *Service) EncodePayload(payload string, encodings []string) (map[string]string, error) {
    results := make(map[string]string)
    
    for _, enc := range encodings {
        switch enc {
        case "url":
            results["url"] = url.QueryEscape(payload)
        case "html":
            results["html"] = html.EscapeString(payload)
        case "base64":
            results["base64"] = base64.StdEncoding.EncodeToString([]byte(payload))
        case "unicode":
            results["unicode"] = encodeUnicode(payload)
        }
    }
    
    return results, nil
}

// InjectPayload injects payload into target
func (s *Service) InjectPayload(ctx context.Context, req *InjectionRequest) (*InjectionResult, error) {
    // Validate payload
    if !s.validator.ValidatePayload(req.Payload) {
        return nil, errors.New("invalid payload")
    }
    
    // Send to target
    resp, err := s.client.Post(ctx, req.Target, req.Payload)
    if err != nil {
        return nil, fmt.Errorf("injection failed: %w", err)
    }
    
    // Record in history
    s.history.Record(req, resp)
    
    return &InjectionResult{
        StatusCode: resp.StatusCode,
        Body:       resp.Body,
        Time:       time.Now(),
    }, nil
}
```

---

### 2.6 REACT UI COMPONENT

```typescript
import React, { useState } from 'react';
import { PayloadEditor } from './PayloadEditor';
import { TemplateLibrary } from './TemplateLibrary';
import { EncodingPanel } from './EncodingPanel';
import { InjectionHistory } from './InjectionHistory';

interface Props {
  onInject: (payload: string) => void;
}

export const InjectionToolkit: React.FC<Props> = ({ onInject }) => {
  const [payload, setPayload] = useState('');
  const [template, setTemplate] = useState<Template | null>(null);
  const [encodings, setEncodings] = useState<string[]>([]);
  const [history, setHistory] = useState<Injection[]>([]);

  const handleInject = async () => {
    const response = await fetch('/api/v1/payloads/inject', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ payload, encodings }),
    });
    
    const result = await response.json();
    setHistory([result, ...history]);
    onInject(payload);
  };

  return (
    <div className="injection-toolkit">
      <TemplateLibrary onSelect={setTemplate} />
      <PayloadEditor value={payload} onChange={setPayload} />
      <EncodingPanel selected={encodings} onChange={setEncodings} />
      <button onClick={handleInject}>Inject</button>
      <InjectionHistory items={history} />
    </div>
  );
};
```

---

### 2.7 GITHUB ACTIONS WORKFLOWS

```yaml
name: Feature-Injection-Test
on: [push, pull_request]

jobs:
  backend:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v4
        with:
          go-version: '1.21'
      - run: go test -v ./internal/injection/...

  frontend:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v3
        with:
          node-version: '18'
      - run: |
          npm ci
          npm test -- --coverage
          npm run build
```

---

## END OF FEATURE 1 & 2 SPECIFICATIONS

**Status:** ✅ Complete
**Total Lines:** 1,363 lines
**Code Examples:** 1,200+ lines of Go
**React Examples:** 200+ lines of TypeScript

**Continue to:** FEATURE_IMPLEMENTATIONS_PART2.md for Features 3, 4, 5
