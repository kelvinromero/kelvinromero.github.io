---
layout: post
title: "Log-Based Engineering Metrics — From Logs to Grafana Dashboards"
description: "How to derive engineering metrics like latency percentiles, error rates, and throughput from your canonical logs using Grafana and Loki — no Prometheus instrumentation needed."
date: 2026-02-15
tags: [observability, grafana, loki, logql, metrics]
---

You've been shipping canonical logs for two weeks. Your Loki instance has millions of structured events. Your manager asks: "What's our p99 latency on the checkout endpoint?" You could instrument Prometheus counters and histograms — define the metric, register the collector, wire it into middleware, deploy, wait for data. Or you could just query the data you already have.

If you've been following the previous articles on canonical log lines and distributed logging, your services already emit structured JSON logs with fields like `duration_ms`, `status_code`, `service`, `path`, and `bounded_context`. Every request that flows through your system produces a log line that captures the same data a Prometheus histogram would — latency, outcome, and identity. The difference is where that data lives and how you query it.

This article shows you how to turn those logs into real engineering dashboards and alert rules using Grafana and Loki, without writing a single line of instrumentation code.

## The Premise: Your Logs Are Already Metrics

Consider a canonical log line emitted at the end of a request:

```json
{
  "timestamp": "2026-03-14T14:32:01.443Z",
  "service": "checkout-api",
  "path": "/api/v1/checkout",
  "method": "POST",
  "status_code": 200,
  "duration_ms": 342,
  "bounded_context": "orders",
  "user_id": "usr_8a3f2c",
  "trace_id": "abc123def456"
}
```

This single event contains everything you need to compute latency percentiles, error rates, and throughput — the three pillars of any engineering health dashboard. Prometheus metrics capture the same dimensions. The difference is that Prometheus pre-aggregates at write time (counters tick up, histogram buckets fill), while Loki stores raw events and aggregates at query time.

Why does this matter? Two reasons:

1. **Zero additional instrumentation.** You don't need to define, register, or maintain Prometheus metrics alongside your logs. The data is already there.
2. **Zero additional cost.** You're already paying to store these logs in Loki. Querying them for aggregations doesn't increase your storage bill.

The trade-off is query-time compute, which we'll address honestly later. For now, let's build something useful.

## Log-Derived Engineering Metrics

Every query below assumes your logs are shipped to Loki with at least a `service` label. The JSON fields — `duration_ms`, `status_code`, `path` — are extracted at query time using LogQL's built-in JSON parser.

### Endpoint Latency (p50, p95, p99)

Latency percentiles are the bread and butter of service health monitoring. With canonical logs that include `duration_ms`, you can compute them directly:

```logql
quantile_over_time(0.99,
  {service="checkout-api"}
    | json
    | unwrap duration_ms [5m]
) by (path)
```

This query streams all log lines from `checkout-api`, parses the JSON body, unwraps `duration_ms` as a numeric value, and computes the 99th percentile over a 5-minute window, grouped by `path`.

To get all three percentiles on a single panel, you run three variants:

```logql
# p50
quantile_over_time(0.50,
  {service="checkout-api"}
    | json
    | unwrap duration_ms [5m]
) by (path)

# p95
quantile_over_time(0.95,
  {service="checkout-api"}
    | json
    | unwrap duration_ms [5m]
) by (path)

# p99
quantile_over_time(0.99,
  {service="checkout-api"}
    | json
    | unwrap duration_ms [5m]
) by (path)
```

Each becomes a separate query (A, B, C) in a single Grafana time series panel. The result is a live latency chart, per endpoint, computed entirely from your existing logs.

### Error Rate by Service and Endpoint

Error rate is the ratio of 5xx responses to total responses. LogQL handles this with two `count_over_time` expressions and a division:

```logql
sum(
  count_over_time(
    {service="checkout-api"}
      | json
      | status_code >= 500 [5m]
  )
) by (path)
/
sum(
  count_over_time(
    {service="checkout-api"}
      | json [5m]
  )
) by (path)
```

The numerator counts log lines where `status_code` is 500 or above. The denominator counts all log lines. Both are grouped by `path` and evaluated over a 5-minute window. The result is a value between 0 and 1 — multiply by 100 in Grafana's field override settings to display as a percentage.

A subtle note: the `status_code >= 500` filter uses LogQL's label filter expressions after JSON parsing. This works because `json` extracts `status_code` as a label, and LogQL supports numeric comparison on extracted labels.

### Request Throughput

Throughput is the simplest metric — how many requests per unit of time:

```logql
sum(
  count_over_time(
    {service="checkout-api"}
      | json [1m]
  )
) by (path)
```

This gives you requests per minute, grouped by endpoint. Use a 1-minute range for granular views or a 5-minute range for smoother trends. In Grafana, this works well as both a time series (throughput over time) and a bar gauge (current throughput by endpoint).

### Slow Query Detection

Sometimes you don't need aggregations — you need the actual slow requests. LogQL's filter expressions give you a live feed:

```logql
{service="checkout-api"}
  | json
  | duration_ms > 2000
```

This returns every request that took longer than 2 seconds, with all its structured fields intact — `path`, `user_id`, `trace_id`, `status_code`. You can click through to the trace directly from the log line. This is the kind of workflow that makes the canonical log approach powerful: a single data source serves both aggregate metrics and detailed investigation.

You can tighten the filter further:

```logql
{service="checkout-api"}
  | json
  | duration_ms > 2000
  | path = "/api/v1/checkout"
  | status_code >= 200
  | line_format "{% raw %}{{.timestamp}} [{{.duration_ms}}ms] {{.path}} → {{.status_code}} user={{.user_id}} trace={{.trace_id}}{% endraw %}"
```

The `line_format` stage reformats the output for readability when browsing in Grafana's Explore view.

## Building a Grafana Dashboard Step by Step

With the queries defined, let's assemble them into a dashboard. Open Grafana, create a new dashboard, and add four panels.

### Panel 1: Latency Over Time

**Visualization:** Time series

**Data source:** Loki

Add three queries to this panel:

- **Query A** (Legend: `p50 {% raw %}{{path}}{% endraw %}`):
  ```logql
  quantile_over_time(0.50,
    {service="checkout-api"} | json | unwrap duration_ms [5m]
  ) by (path)
  ```
- **Query B** (Legend: `p95 {% raw %}{{path}}{% endraw %}`):
  ```logql
  quantile_over_time(0.95,
    {service="checkout-api"} | json | unwrap duration_ms [5m]
  ) by (path)
  ```
- **Query C** (Legend: `p99 {% raw %}{{path}}{% endraw %}`):
  ```logql
  quantile_over_time(0.99,
    {service="checkout-api"} | json | unwrap duration_ms [5m]
  ) by (path)
  ```

Under **Panel options**, set the title to "Endpoint Latency." Under **Standard options**, set the unit to `milliseconds (ms)`. Under **Thresholds**, add a red threshold at 2000ms to visually flag when latency crosses your SLO boundary.

Consider using **Query type: Range** in each query's options — this tells Grafana to evaluate the metric query across the entire time range, producing the time series you expect.

### Panel 2: Error Rate

**Visualization:** Time series

**Data source:** Loki

**Query A** (Legend: `error rate {% raw %}{{path}}{% endraw %}`):

```logql
sum(count_over_time({service="checkout-api"} | json | status_code >= 500 [5m])) by (path)
/
sum(count_over_time({service="checkout-api"} | json [5m])) by (path)
```

Under **Standard options**, set the unit to `Percent (0.0-1.0)`. Under **Thresholds**, add a dashed red line at 0.01 (1%). This gives you an immediate visual indicator when error rate crosses the acceptable boundary.

Enable **Fill opacity** at around 10–20% to make spikes easier to spot against the threshold line. Under **Graph styles**, set the line interpolation to **Step after** — error rates are discrete ratios, and step interpolation represents them more honestly than smooth curves.

### Panel 3: Throughput by Endpoint

**Visualization:** Bar gauge

**Data source:** Loki

**Query A**:

```logql
sum(count_over_time({service="checkout-api"} | json [1m])) by (path)
```

Set **Query type** to **Instant** so the bar gauge shows the current value rather than a time series. Under **Standard options**, set the unit to `requests/min`. Set **Display mode** to **Gradient** and orient the bars horizontally. This panel gives your team a glanceable view of which endpoints are hot right now.

For a time-based view instead, duplicate this panel, switch the visualization to **Time series**, change the query type back to **Range**, and set the range vector to `[5m]` for smoother lines. Both views are useful — the bar gauge for current state, the time series for trends.

### Panel 4: Recent Errors Table

**Visualization:** Logs

**Data source:** Loki

**Query A**:

```logql
{service="checkout-api"}
  | json
  | status_code >= 500
```

Under **Panel options**, set the title to "Recent 5xx Errors." Enable **Time**, **Unique labels**, and **Common labels** in the logs panel settings. The panel will display a scrollable list of recent error log lines with their full structured fields. Since these are canonical log lines, each entry includes `trace_id`, `user_id`, `path`, `duration_ms`, and everything else you need to start investigating without switching tools.

To make the panel more informative, you can configure **Data links** — add a link template that opens Grafana Tempo or Jaeger with the `trace_id` from the log line. This closes the loop between metric observation and trace-level investigation in a single click.

### Dashboard Variables

To make the dashboard reusable across services, add a **template variable**:

1. Go to **Dashboard settings → Variables → New variable**.
2. Name: `service`, Type: **Query**, Data source: **Loki**.
3. Query: `label_values(service)`.
4. Enable **Multi-value** and **Include All option**.

Then replace `{service="checkout-api"}` with `{service=~"$service"}` in every query. Now the dashboard works for any service that ships canonical logs — no per-service dashboard maintenance required.

## Alert Rules from Logs

Dashboards are passive — someone has to look at them. Alerts make the system active. Grafana's unified alerting system supports Loki as a data source, which means you can alert directly on LogQL metric queries.

### Alert: Error Rate > 5% for 5 Minutes

In Grafana, navigate to **Alerting → Alert rules → New alert rule**.

**Rule configuration:**

- **Rule name:** `High Error Rate — checkout-api`
- **Data source:** Loki
- **Query (A):**
  ```logql
  sum(count_over_time({service="checkout-api"} | json | status_code >= 500 [5m])) by (path)
  /
  sum(count_over_time({service="checkout-api"} | json [5m])) by (path)
  ```
- **Condition (B):** Expression type `Threshold`, input `A`, IS ABOVE `0.05`.
- **Evaluate every:** `1m`, **For:** `5m`.

The `For` duration means the condition must be continuously true for 5 minutes before the alert fires. This prevents transient spikes from waking someone up at 3 AM.

### Alert: p99 Latency > 2 Seconds for 5 Minutes

**Rule configuration:**

- **Rule name:** `High p99 Latency — checkout-api`
- **Data source:** Loki
- **Query (A):**
  ```logql
  quantile_over_time(0.99,
    {service="checkout-api"} | json | unwrap duration_ms [5m]
  ) by (path)
  ```
- **Condition (B):** Expression type `Threshold`, input `A`, IS ABOVE `2000`.
- **Evaluate every:** `1m`, **For:** `5m`.

### Provisioning Alerts as Code

If you manage Grafana configuration through provisioning, here's the equivalent alert rule definition in YAML:

```yaml
apiVersion: 1
groups:
  - orgId: 1
    name: checkout-api-alerts
    folder: Engineering Metrics
    interval: 1m
    rules:
      - uid: checkout-error-rate
        title: "High Error Rate — checkout-api"
        condition: B
        data:
          - refId: A
            relativeTimeRange:
              from: 300
              to: 0
            datasourceUid: loki
            model:
              expr: |
                sum(count_over_time({service="checkout-api"} | json | status_code >= 500 [5m])) by (path)
                /
                sum(count_over_time({service="checkout-api"} | json [5m])) by (path)
              queryType: range
          - refId: B
            datasourceUid: "-100"
            model:
              type: threshold
              expression: A
              conditions:
                - evaluator:
                    type: gt
                    params: [0.05]
        for: 5m
        annotations:
          summary: "Error rate on checkout-api exceeded 5%"
        labels:
          severity: critical

      - uid: checkout-p99-latency
        title: "High p99 Latency — checkout-api"
        condition: B
        data:
          - refId: A
            relativeTimeRange:
              from: 300
              to: 0
            datasourceUid: loki
            model:
              expr: |
                quantile_over_time(0.99,
                  {service="checkout-api"} | json | unwrap duration_ms [5m]
                ) by (path)
              queryType: range
          - refId: B
            datasourceUid: "-100"
            model:
              type: threshold
              expression: A
              conditions:
                - evaluator:
                    type: gt
                    params: [2000]
        for: 5m
        annotations:
          summary: "p99 latency on checkout-api exceeded 2 seconds"
        labels:
          severity: warning
```

Drop this file into your Grafana provisioning directory and the alert rules are version-controlled, reviewable, and reproducible. No clicking through UIs.

## The Cost Perspective

Take a step back and consider what you've built. You have a dashboard with latency percentiles, error rates, throughput charts, and a live error log — plus alerting rules that page your on-call when things go wrong.

You're already storing these logs in Loki. The dashboard is free. The alerts are free. You didn't need to add a single line of Prometheus instrumentation. No new client libraries, no new exporters, no new scrape targets, no new metric naming conventions to debate in code review. The data was already flowing. You just learned how to ask the right questions.

For a team that's just getting started with observability, this is an enormous win. You get 80% of the value of a full metrics stack by leveraging what you already have.

## Limitations — Be Honest About the Trade-offs

Log-derived metrics have real limitations. For high-frequency, low-latency metrics at massive scale (millions of events per second), Prometheus with proper histogram instrumentation is more efficient and precise. LogQL aggregations have higher query latency than pre-computed Prometheus metrics. Recording rules can help but add complexity. For 90% of teams, though, log-derived metrics are a powerful and cost-effective starting point that requires no additional instrumentation.

A few specifics worth noting:

- **Query performance degrades with cardinality.** If you have hundreds of unique `path` values, `quantile_over_time ... by (path)` gets expensive. Consider adding a `path` label at log ingestion time for high-cardinality fields, or use LogQL's `label_format` to normalize paths.
- **Loki's quantile calculation is approximate.** It operates over the raw values in the selected window, not pre-bucketed data. For most operational purposes this is fine, but don't cite these numbers in an SLA dispute.
- **Dashboard load time scales with log volume.** A dashboard querying 24 hours of data across 50 services will be slower than a Prometheus dashboard doing the same. Keep time ranges reasonable, or invest in Loki's [recording rules](https://grafana.com/docs/loki/latest/alert/#recording-rules) to pre-compute frequently-used aggregations.

None of these are blockers for getting started. They're reasons to eventually complement log-derived metrics with proper instrumentation as your scale demands it — not reasons to avoid the approach entirely.

## What's Next

Your logs now power engineering dashboards and alerts. Service owners can see latency, error rates, and throughput at a glance. On-call engineers get paged when things break. And you built all of it on top of the canonical log lines you were already shipping.

But engineering metrics only tell half the story. They answer "is the system healthy?" — they don't answer "are users succeeding?" In the next article, we'll use the same canonical logs — enriched with `bounded_context`, `feature`, and `session_feature_id` — to build product observability dashboards. Same data source, different questions, a whole new category of insight.
