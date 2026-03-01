---
layout: post
title: "Log-Based Business Metrics — Product Observability from Your Existing Logs"
description: "How to derive product metrics like feature adoption, conversion funnels, and drop-off analysis from canonical logs enriched with business context — using Grafana and Loki."
date: 2026-03-22
tags: [observability, product-metrics, grafana, loki, logql]
---

Your engineering dashboards are humming. Latency, error rates, throughput — all derived from canonical logs. Your CTO is happy. Then your product manager asks: "How many users completed the checkout flow yesterday? Where are they dropping off?" You open Amplitude. It costs $36,000/year. Your logs already have the answer.

Over the past three articles, we've built a structured logging foundation that most teams never fully exploit. In the [first article]({% post_url 2026-03-01-canonical-logs-foundation-of-observability %}), we introduced canonical log lines — one wide, structured event per request per service, emitted at the end of the request lifecycle. In the [second article]({% post_url 2026-03-08-distributed-logging-trace-propagation-business-context %}), we propagated `trace_id` across service boundaries and enriched every log line with business dimensions: `bounded_context`, `feature`, and `session_feature_id`. In the third article, we turned those logs into engineering metrics — latency percentiles, error rate breakdowns, throughput dashboards — all in Grafana with Loki.

This article takes the final step. We're going to derive *product* metrics from the same log data. Feature adoption. Conversion funnels. Drop-off analysis. Bounded context health. No new pipeline. No new vendor. Just LogQL queries against the logs you already produce.

## The gap between engineering and product observability

Engineering teams live in Grafana. They have dashboards for p99 latency, error rates by service, and throughput by endpoint. These dashboards are powered by canonical logs — structured, queryable, and free.

Product teams live in Amplitude, Mixpanel, or Segment. They have dashboards for feature adoption, conversion funnels, and user retention. These dashboards are powered by a completely separate data pipeline — a tracking SDK in the frontend, an event ingestion API, a data warehouse, and a $30k–$100k/year SaaS contract.

Two teams. Two pipelines. Two data models. Two sources of truth.

But look at what we already have on every canonical log line: `user_id`, `feature`, `bounded_context`, `session_feature_id`, `status`, and a `step` field identifying where the user is in a multi-step flow. These aren't engineering fields. They're *product* fields — placed on the log line specifically because we designed the business dimension propagation in Article 2 to carry product-level context.

The question is whether LogQL is expressive enough to answer basic product questions with these fields. It is.

## Log-based product metrics

### Feature adoption: unique users per feature

The most basic product question is "how many people are using this feature?" With `user_id` and `feature` on every log line, this is a direct query.

Count the unique users who triggered the `guest-checkout` feature in the last 24 hours:

```logql
count(
  count_over_time(
    {service=~".+"} | json | feature="guest-checkout" [24h]
  ) by (user_id)
)
```

This works in two stages. The inner `count_over_time ... by (user_id)` produces one time series per unique `user_id` — counting how many log lines each user generated. The outer `count()` then counts the number of series, giving you the number of distinct users.

To see adoption across *all* features over time, use a Grafana time-series panel with:

```logql
count by (feature) (
  count_over_time(
    {service=~".+"} | json | feature=~".+" [1h]
  ) by (feature, user_id)
)
```

This gives you a line per feature, each showing the count of unique users per hour. You can watch a new feature ramp up from zero after a launch, or spot an existing feature losing traction.

### Conversion funnels: step-by-step completion rates

Feature adoption tells you *who* is starting a flow. Conversion funnels tell you *who finishes it*. This requires a `step` field on your canonical log lines — something like `"start_checkout"`, `"enter_address"`, `"enter_payment"`, or `"confirm_order"`. The service layer sets this when enriching the canonical event, just like it sets `feature` and `bounded_context`.

Count unique sessions that reached each step of the checkout funnel in the last 24 hours:

**Step 1 — Start checkout:**

```logql
count(
  count_over_time(
    {service=~".+"} | json | feature="standard-checkout" | step="start_checkout" [24h]
  ) by (session_feature_id)
)
```

**Step 2 — Enter address:**

```logql
count(
  count_over_time(
    {service=~".+"} | json | feature="standard-checkout" | step="enter_address" [24h]
  ) by (session_feature_id)
)
```

**Step 3 — Enter payment:**

```logql
count(
  count_over_time(
    {service=~".+"} | json | feature="standard-checkout" | step="enter_payment" [24h]
  ) by (session_feature_id)
)
```

**Step 4 — Confirm order:**

```logql
count(
  count_over_time(
    {service=~".+"} | json | feature="standard-checkout" | step="confirm_order" [24h]
  ) by (session_feature_id)
)
```

In Grafana, display these four values as a bar chart. If 1,000 sessions started checkout, 820 entered an address, 780 entered payment, and 710 confirmed — you've got a 71% end-to-end conversion rate and you can see that the biggest drop-off is between start and address entry.

### Drop-off analysis: where users abandon

The funnel tells you *how many* reach each step. Drop-off analysis tells you *where they leave*. The technique is a ratio between consecutive steps.

The drop-off rate between "enter address" and "enter payment" is:

```logql
1 - (
  count(
    count_over_time(
      {service=~".+"} | json | feature="standard-checkout" | step="enter_payment" [24h]
    ) by (session_feature_id)
  )
  /
  count(
    count_over_time(
      {service=~".+"} | json | feature="standard-checkout" | step="enter_address" [24h]
    ) by (session_feature_id)
  )
)
```

A result of `0.05` means 5% of users who entered their address did not proceed to payment. Track this daily and alert if it spikes — a payment provider outage, a broken form validation, or a confusing UI change will show up here before it shows up in revenue.

For the simplest version, compute each step count as a separate Grafana variable and build the ratios in a dashboard table. LogQL arithmetic across instant queries works well for this pattern.

### Bounded context health: error rate per domain

This metric bridges engineering and product. Instead of "what's the error rate of `order-service`?" — which means nothing to a product manager — ask "what's the error rate of the *checkout* domain?"

```logql
sum by (bounded_context) (
  count_over_time(
    {service=~".+"} | json | status >= 500 [1h]
  )
)
/
sum by (bounded_context) (
  count_over_time(
    {service=~".+"} | json [1h]
  )
)
```

This produces a single number per bounded context — `checkout: 0.2%`, `payments: 0.05%`, `catalog: 1.3%`, `identity: 0.01%`. Display it as a Grafana table panel sorted by error rate descending. When the `catalog` domain is at 1.3% errors, everyone — engineers and product managers — immediately knows which *business capability* is degraded, without needing to map service names to business functions.

## Smart sampling for business metrics

The queries above scan your full log stream. At scale — millions of requests per hour — that gets expensive in Loki storage and query time. Smart sampling is how you control cost without losing the metrics that matter.

The principle is simple: not all bounded contexts are equally important for business metrics. A dropped checkout is a lost sale. A dropped catalog browse is a minor inconvenience. Sample accordingly.

- **100% sampling** for `checkout`, `payments`, `subscription`, `identity` — any flow where a lost event means a lost data point on revenue or critical user journeys.
- **5–10% sampling** for `catalog`, `search`, `recommendations`, `browsing` — high-volume, low-stakes flows where statistical accuracy from a sample is sufficient.

Here's a Go function that decides whether to emit a canonical log based on `bounded_context` and `feature`:

```go
package sampling

import "math/rand"

// criticalContexts are bounded contexts that must always be logged at 100%.
var criticalContexts = map[string]bool{
	"checkout":     true,
	"payments":     true,
	"subscription": true,
	"identity":     true,
}

// criticalFeatures are features that must always be logged regardless of context.
var criticalFeatures = map[string]bool{
	"guest-checkout":    true,
	"subscription-upgrade": true,
	"password-reset":    true,
}

// ShouldEmit returns true if this canonical event should be emitted.
// Critical business flows are always emitted. Low-priority flows
// are sampled at the given rate (0.0–1.0).
func ShouldEmit(boundedContext, feature string, lowPriorityRate float64) bool {
	if criticalContexts[boundedContext] {
		return true
	}
	if criticalFeatures[feature] {
		return true
	}
	return rand.Float64() < lowPriorityRate
}
```

Call this in your canonical log middleware, right before emission:

```go
defer func() {
    event.Set("http_status", rec.statusCode)
    event.Set("duration_ms", time.Since(start).Milliseconds())

    bc, _ := event.Get("bounded_context")
    feat, _ := event.Get("feature")
    if !sampling.ShouldEmit(bc, feat, 0.05) {
        return
    }

    logger.LogAttrs(r.Context(), levelFromStatus(rec.statusCode),
        "request_completed", attrsFromFields(event.fields)...)
}()
```

This cuts log volume dramatically for high-traffic browse and search paths while preserving every single checkout and payment event. Your product metrics on critical flows remain exact; metrics on low-priority flows are estimated from the sample — perfectly acceptable for adoption trends and health monitoring.

One important detail: when you sample, add a `sample_rate` field to the emitted log line (e.g., `"sample_rate": 0.05`). This lets you weight your LogQL aggregations correctly by multiplying counts by `1/sample_rate` when needed.

## Building product dashboards in Grafana

With the queries above, building a product dashboard is a matter of assembling panels. Here's a layout that works well as a "Product Health" dashboard.

**Panel 1 — Feature adoption over time** (Time Series). Data source: Loki. Query: the `count by (feature)` unique-users query from above, with a `[$__interval]` range instead of `[1h]`. Each feature gets its own line. Set the legend to `{% raw %}{{feature}}{% endraw %}` and use a 1-hour minimum interval.

**Panel 2 — Checkout funnel** (Bar Chart). Four queries, one per step, each returning an instant scalar count. Label them "Start Checkout," "Enter Address," "Enter Payment," and "Confirm Order." Use a horizontal bar chart so the bars shrink left-to-right, making the funnel shape immediately visible.

**Panel 3 — Bounded context health** (Table). The error-rate-per-bounded-context query from above. Format the value column as a percentage. Add conditional formatting: green below 0.5%, yellow between 0.5% and 2%, red above 2%. Sort descending by error rate.

**Panel 4 — Active session features** (Stat). Count the number of distinct `session_feature_id` values seen in the last 15 minutes — a rough proxy for "how many users are in the middle of a multi-step journey right now":

```logql
count(
  count_over_time(
    {service=~".+"} | json | session_feature_id=~".+" [15m]
  ) by (session_feature_id)
)
```

Display as a single stat panel with sparkline. This is a pulse check — if it drops to zero on a weekday afternoon, something is very wrong.

These four panels give product managers a self-service view of feature health without touching Amplitude, and give engineers a business-context lens on the same data they already use for latency and error debugging.

## When this isn't enough

Log-based product metrics have real limitations, and pretending otherwise would be dishonest.

**No retroactive analysis.** If you didn't log a field, you can't query it historically. Decide to add `subscription_tier` to your checkout flow? You'll only have data from the day you deploy the change forward. Dedicated analytics tools store raw events and let you redefine dimensions retroactively.

**No user segmentation.** Unless you explicitly log user properties — plan tier, geographic region, signup cohort — you can't segment metrics by those dimensions. You only get what's on the log line.

**No A/B testing framework.** You can compare `feature="guest-checkout"` vs. `feature="standard-checkout"`, but you don't get statistical significance calculations, experiment management, or automatic winner detection.

**No behavioral cohort analysis.** Questions like "users who browsed three or more products before purchasing" require joining across multiple sessions, which LogQL doesn't support.

**No client-side interaction tracking.** Canonical logs capture server-side request events. Button clicks, scroll depth, time on page, rage clicks — these never hit your backend and don't appear in your logs.

## The honest disclaimer

Log-based product metrics don't replace dedicated product analytics tools. For complex behavioral analysis, cohort studies, A/B testing, and client-side interaction tracking, you still need tools like Amplitude or Mixpanel. But for core product health metrics — feature adoption, conversion rates, bounded context health — your canonical logs are a powerful, free addition that uses data you already produce. For small companies without analytics budget, this might be all you need to start.

## Wrapping up the series

This is the fourth and final article in the series. Let's recap the journey.

We started with **canonical log lines** — replacing dozens of scattered `log.Info` calls with a single structured event per request, emitted at the boundary, enriched by every layer of the application. One line that tells the full story.

We then took those logs **across service boundaries** — propagating `trace_id`, `bounded_context`, `feature`, and `session_feature_id` through HTTP headers and Kafka message headers, so that a user's journey through five services produces five correlated, business-enriched log lines instead of five isolated islands of context.

From there, we derived **engineering metrics** — latency percentiles, error rate breakdowns, throughput dashboards — all from LogQL queries against the same canonical logs. No separate metrics pipeline. No StatsD. No Prometheus client library. Just logs.

And in this article, we crossed into **product metrics** — feature adoption, conversion funnels, drop-off analysis, and bounded context health. The same structured log data, queried differently, answering questions that normally require a separate $36k/year analytics tool.

Four articles. One data source. Canonical logs, enriched with business context, are the most underutilized asset in most backend systems. They're already there. They already contain the answers. You just have to ask the right questions.

The full thesis behind this approach — why structured logging is the most cost-effective foundation for observability — is available at [loggingrocks.com](https://loggingrocks.com).
