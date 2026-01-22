# Security Audit Logging

This document describes the security audit logging implementation for the BNG and Nexus services.

## Overview

Security audit logging is essential for:
- Incident investigation and forensics
- Compliance requirements (GDPR, PCI-DSS, SOC2, etc.)
- Threat detection and security monitoring
- Legal requirements (data retention laws)

## Event Types

### BNG Events

| Event Type | Category | Description | Severity |
|------------|----------|-------------|----------|
| DEVICE_REGISTRATION_ATTEMPT | device | Device attempting to register | INFO |
| DEVICE_REGISTRATION_SUCCESS | device | Device successfully registered | INFO |
| DEVICE_REGISTRATION_FAILURE | device | Device registration failed | WARNING |
| DEVICE_DEREGISTRATION | device | Device deregistered | NOTICE |
| API_AUTH_ATTEMPT | api | API authentication attempt | INFO |
| API_AUTH_SUCCESS | api | Successful API authentication | INFO |
| API_AUTH_FAILURE | api | Failed API authentication | WARNING |
| API_ACCESS_DENIED | api | Access denied to API resource | WARNING |
| API_RATE_LIMITED | api | Request rate limited | WARNING |
| SUSPICIOUS_ACTIVITY | security | Suspicious behavior detected | WARNING |
| BRUTE_FORCE_DETECTED | security | Brute force attack detected | ALERT |
| UNAUTHORIZED_ACCESS | security | Unauthorized access attempt | ALERT |
| MAC_SPOOF_DETECTED | security | MAC address spoofing detected | CRITICAL |
| IP_SPOOF_DETECTED | security | IP address spoofing detected | CRITICAL |
| DHCP_STARVATION_ATTEMPT | security | DHCP starvation attack | ALERT |
| RESOURCE_ALLOCATED | resource | Resource successfully allocated | INFO |
| RESOURCE_DEALLOCATED | resource | Resource deallocated | INFO |
| RESOURCE_EXHAUSTED | resource | Resource pool exhausted | WARNING |

### Nexus Events

| Event Type | Category | Description | Severity |
|------------|----------|-------------|----------|
| POOL_CREATED | resource | IP pool created | INFO |
| POOL_DELETED | resource | IP pool deleted | INFO |
| POOL_MODIFIED | resource | IP pool modified | INFO |
| ALLOCATION_CREATED | resource | IP allocation created | INFO |
| ALLOCATION_DELETED | resource | IP allocation deleted | INFO |
| ALLOCATION_CONFLICT | resource | IP allocation conflict | WARNING |
| NODE_JOINED | node | Node joined cluster | NOTICE |
| NODE_LEFT | node | Node left cluster | NOTICE |
| NODE_EXPIRED | node | Node heartbeat expired | NOTICE |
| CONFIG_CHANGE | admin | Configuration changed | NOTICE |
| ADMIN_ACTION | admin | Administrative action taken | NOTICE |

## Structured Log Format (JSON)

All audit events are logged in JSON format for easy parsing and SIEM integration:

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "type": "API_AUTH_FAILURE",
  "timestamp": "2024-01-15T10:30:00.000Z",
  "device_id": "bng-edge-01",
  "actor_id": "user@example.com",
  "actor_type": "user",
  "source_ip": "192.168.1.100",
  "user_agent": "curl/7.68.0",
  "api_endpoint": "/api/v1/pools",
  "http_method": "POST",
  "http_status": 401,
  "success": false,
  "error_code": "INVALID_TOKEN",
  "error_message": "Authentication token expired",
  "request_id": "req-12345",
  "resource_type": "pool",
  "threat_type": "",
  "threat_score": 0,
  "failure_count": 0,
  "metadata": {
    "client_version": "1.0.0"
  },
  "retention_days": 365,
  "expires_at": "2025-01-15T10:30:00.000Z"
}
```

## Retention Policy

Retention periods are configured based on category and legal requirements:

| Category | Default Retention | Notes |
|----------|-------------------|-------|
| session | 365 days | Subscriber session logs |
| nat | 365 days | NAT translation logs (legal requirement) |
| auth | 365 days | Authentication events |
| dhcp | 30 days | DHCP protocol events |
| admin | 730 days | Administrative actions |
| device | 365 days | Device registration events |
| api | 365 days | API access logs |
| security | 730 days | Security events (compliance) |
| resource | 365 days | Resource allocation |
| system | 30 days | System events |

### Legal Requirements by Jurisdiction

| Jurisdiction | Session | NAT | Auth | Reference |
|--------------|---------|-----|------|-----------|
| UK | 365 days | 365 days | 365 days | IPA 2016 |
| EU | 365 days* | 365 days* | 365 days* | Varies by member state |
| US | 180 days | 180 days | 180 days | No federal mandate |
| Australia | 730 days | 730 days | 730 days | Metadata Retention Scheme |

*EU requirements vary post-Digital Rights Ireland ruling.

## Log Rotation

Log rotation is configured using standard `logrotate` configuration files.

### Installation

```bash
# BNG
sudo cp configs/logrotate/bng-audit.conf /etc/logrotate.d/

# Nexus
sudo cp configs/logrotate/nexus-audit.conf /etc/logrotate.d/
```

### Configuration

Default rotation settings:
- Daily rotation
- Compression enabled (with delayed compression)
- Date-based filename extension
- Service HUP signal for log reopening

## SIEM Integration

The structured JSON log format enables easy integration with SIEM systems.

### Splunk

```spl
# Example Splunk query
index=security sourcetype=bng_audit
| where type="BRUTE_FORCE_DETECTED" OR type="UNAUTHORIZED_ACCESS"
| stats count by source_ip, actor_id
| where count > 5
```

### Elasticsearch

```json
{
  "query": {
    "bool": {
      "must": [
        { "match": { "type": "API_AUTH_FAILURE" } },
        { "range": { "timestamp": { "gte": "now-1h" } } }
      ]
    }
  },
  "aggs": {
    "by_source_ip": {
      "terms": { "field": "source_ip" }
    }
  }
}
```

### Filebeat Configuration

```yaml
filebeat.inputs:
  - type: log
    enabled: true
    paths:
      - /var/log/bng/audit.log
      - /var/log/nexus/audit.log
    json.keys_under_root: true
    json.add_error_key: true
    fields:
      service: bng-audit
    fields_under_root: true

output.elasticsearch:
  hosts: ["elasticsearch:9200"]
  index: "security-audit-%{+yyyy.MM.dd}"
```

## Alerting Examples

### High-Severity Events

Alert on events with severity >= ALERT:
- BRUTE_FORCE_DETECTED
- UNAUTHORIZED_ACCESS
- MAC_SPOOF_DETECTED
- IP_SPOOF_DETECTED
- DHCP_STARVATION_ATTEMPT

### Anomaly Detection

- Multiple auth failures from same source IP (>5 in 5 minutes)
- Registration attempts from unknown devices
- Unusual API access patterns
- Resource exhaustion events

## Configuration

### BNG Audit Logger

```go
import "github.com/codelaboratoryltd/bng/pkg/audit"

config := audit.DefaultConfig()
config.DeviceID = "bng-edge-01"
config.RetentionByCategory["security"] = 730 // 2 years

storage := audit.NewMemoryStorage() // Or use persistent storage
logger := audit.NewLogger(config, storage, zapLogger)

// Add exporters for SIEM integration
syslogExporter, _ := audit.NewSyslogExporter(audit.SyslogConfig{
    Network: "tcp",
    Address: "syslog.example.com:514",
    Tag:     "bng-audit",
}, zapLogger)
logger.AddExporter(syslogExporter)

logger.Start()
defer logger.Stop()
```

### Nexus Audit Logger

```go
import "github.com/codelaboratoryltd/nexus/internal/audit"

config := audit.DefaultConfig()
config.ServerID = "nexus-01"
config.JSONFormat = true

logger := audit.NewLogger(config)
logger.Start()
defer logger.Stop()

// Use middleware for automatic API logging
middleware := audit.NewMiddleware(logger)
router.Use(middleware.Handler)
```

## Best Practices

1. **Always log security events synchronously** for critical events to ensure they're captured even if the system crashes.

2. **Include request IDs** for correlation across distributed systems.

3. **Mask sensitive data** - never log passwords, API keys, or PII directly.

4. **Monitor log volume** - set up alerts for unusual spikes in log volume.

5. **Test log rotation** - ensure rotation works correctly before production.

6. **Backup audit logs** - maintain offsite backups for compliance.

7. **Encrypt logs at rest** - protect sensitive audit data.

8. **Implement log integrity** - consider tamper-evident logging for high-security environments.

## Compliance Checklist

- [ ] All security events are logged
- [ ] Logs are structured and parseable (JSON)
- [ ] Log rotation is configured
- [ ] Retention policies match legal requirements
- [ ] SIEM integration is configured
- [ ] Alerting is set up for high-severity events
- [ ] Logs are backed up offsite
- [ ] Access to logs is restricted and audited
- [ ] Log integrity is verified (optional)
