---
layout: post
title: "Distributed Logging — Trace Propagation and Business Context"
description: "How to correlate logs across services with trace_id propagation and enrich them with bounded context, feature, and session feature dimensions."
date: 2026-02-08
tags: [observability, distributed-systems, logging, go]
---

Your canonical logs are working great — in a single service. But when a user clicks "Place Order," their request touches the API gateway, auth service, payment service, inventory service, and notification service. Five services, five canonical logs. Zero correlation.

In the [previous article]({% post_url 2026-02-01-canonical-logs-foundation-of-observability %}), we built structured canonical logs that emit one rich log line per request. That pattern gives you everything you need to debug issues within a single service. But modern systems aren't single services. A single user action fans out across a mesh of synchronous HTTP calls and asynchronous Kafka messages, and when something breaks, you're left staring at five independent log streams trying to reconstruct what happened by guessing at timestamps.

This article fixes that. We'll propagate a `trace_id` across every service boundary, enrich logs with business dimensions that make them queryable by domain concepts, and show how log-based correlation complements — but doesn't replace — distributed tracing.

## The Problem: Islands of Context

Imagine a user starts a checkout. The API gateway authenticates the request, the order service validates the cart, the payment service charges the card, the inventory service reserves stock, and the notification service sends a confirmation email. Each service dutifully emits a canonical log line with latency, status, and local context.

Now the user reports they were charged but never got a confirmation. You open your log dashboard and search for their `user_id`. You find five log lines across five services, but you can't tell which lines belong to *this* checkout versus the user's browsing session from ten minutes earlier. You can't tell the order in which services processed the request. You can't tell whether the notification service ever received the event at all.

The missing piece is a shared identifier — a thread that stitches these islands of context into one coherent story.

## Trace ID Propagation

The solution is straightforward: generate a unique `trace_id` at the edge, and propagate it through every service boundary.

### Generating at the Edge

The first service to receive a request — typically the API gateway — generates a `trace_id` if one doesn't already exist. If you're adopting W3C Trace Context, this lives in the `traceparent` header. For simpler setups, a custom `X-Trace-Id` header works fine. The key property is that it's globally unique (a UUID v4 works) and opaque — services don't parse it, they just pass it along.

```go
package middleware

import (
	"context"
	"net/http"

	"github.com/google/uuid"
)

type ctxKey string

const traceIDKey ctxKey = "trace_id"

// TraceIDMiddleware extracts or generates a trace_id and injects it into
// the request context. Every downstream handler gets correlation for free.
func TraceIDMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		traceID := r.Header.Get("X-Trace-Id")
		if traceID == "" {
			traceID = uuid.NewString()
		}

		ctx := context.WithValue(r.Context(), traceIDKey, traceID)
		w.Header().Set("X-Trace-Id", traceID)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

func TraceIDFromContext(ctx context.Context) string {
	if v, ok := ctx.Value(traceIDKey).(string); ok {
		return v
	}
	return ""
}
```

### Propagating via HTTP

When service A calls service B, the `trace_id` must travel with the request. Wrap your HTTP client to inject it automatically:

```go
func NewTracedRequest(ctx context.Context, method, url string, body io.Reader) (*http.Request, error) {
	req, err := http.NewRequestWithContext(ctx, method, url, body)
	if err != nil {
		return nil, err
	}
	if traceID := TraceIDFromContext(ctx); traceID != "" {
		req.Header.Set("X-Trace-Id", traceID)
	}
	return req, nil
}
```

This is the discipline that makes the pattern work. Every outbound call must carry the `trace_id`. Miss one, and you create a gap in the correlation chain.

### Propagating via Kafka

Asynchronous flows are where correlation usually breaks down. When a service publishes a Kafka message, the `trace_id` must travel in the message headers — not the payload.

```go
import "github.com/IBM/sarama"

func ProduceWithTrace(ctx context.Context, producer sarama.SyncProducer, topic string, payload []byte) error {
	msg := &sarama.ProducerMessage{
		Topic: topic,
		Value: sarama.ByteEncoder(payload),
		Headers: []sarama.RecordHeader{
			{
				Key:   []byte("trace_id"),
				Value: []byte(TraceIDFromContext(ctx)),
			},
		},
	}
	_, _, err := producer.SendMessage(msg)
	return err
}

func TraceIDFromKafkaHeaders(headers []*sarama.RecordHeader) string {
	for _, h := range headers {
		if string(h.Key) == "trace_id" {
			return string(h.Value)
		}
	}
	return ""
}
```

On the consumer side, extract the `trace_id` from the message headers and inject it into the context before processing:

```go
func HandleMessage(msg *sarama.ConsumerMessage) {
	traceID := TraceIDFromKafkaHeaders(msg.Headers)

	ctx := context.WithValue(context.Background(), traceIDKey, traceID)

	// Process the message with trace context available
	processOrder(ctx, msg.Value)
}
```

The canonical log emitted by the consumer now shares the same `trace_id` as the producer, closing the async gap. This is critical — Kafka is where most teams lose correlation, because the boundary between synchronous and asynchronous processing feels like a natural place to "start fresh." Resist that instinct.

## Beyond trace_id — Business Dimensions

A `trace_id` tells you *which logs belong together*. It doesn't tell you *what the user was doing*. When you're investigating a production incident, you rarely start with a trace ID. You start with questions like "are checkout errors spiking?" or "is the new guest-checkout feature broken?" or "what did this user's checkout journey look like end to end?"

To answer these questions, you need business dimensions on every log line. We propagate three alongside the `trace_id`.

### Bounded Context

The `bounded_context` field identifies which domain owns this request. Values are coarse-grained and stable: `"checkout"`, `"payments"`, `"shipping"`, `"catalog"`, `"identity"`.

This lets you slice your entire log stream by domain. A query like `bounded_context="checkout" AND status>=500` instantly narrows millions of log lines to the few hundred that matter, without needing to know which services are involved in checkout.

### Feature

The `feature` field identifies which product feature is being exercised. Values map to things a product manager would recognize: `"add-to-cart"`, `"apply-coupon"`, `"guest-checkout"`, `"reorder-previous"`.

This is where observability meets product development. When you ship the `guest-checkout` feature behind a flag, you can query `feature="guest-checkout" AND status>=500` and compare error rates against `feature="standard-checkout"`. You're measuring feature reliability, not just service reliability.

### Session Feature ID

The `session_feature_id` is a unique identifier that groups the sequence of requests a user makes to complete one feature journey. Consider a checkout flow: the user enters their address, selects a shipping method, enters payment details, and confirms the order. That's four or five HTTP requests, possibly across multiple services, all part of one logical journey.

The frontend generates a `session_feature_id` when the user starts a feature flow and sends it with every subsequent request. This lets you query "show me every request in this user's checkout journey, in order" — a capability that `trace_id` alone can't provide, because each HTTP request gets its own `trace_id`.

Think of it this way: `trace_id` correlates logs within a single request fan-out, while `session_feature_id` correlates logs across the multiple requests that compose a user journey. You need both. The `trace_id` tells you what happened when the payment was processed; the `session_feature_id` tells you that the user had already failed address validation twice before they got to payment — context that changes how you interpret the payment failure entirely.

### Propagating Business Dimensions

These fields propagate exactly like `trace_id` — via HTTP headers and Kafka message headers. Extend the middleware:

```go
type RequestContext struct {
	TraceID          string
	BoundedContext   string
	Feature          string
	SessionFeatureID string
}

const (
	headerTraceID          = "X-Trace-Id"
	headerBoundedContext   = "X-Bounded-Context"
	headerFeature          = "X-Feature"
	headerSessionFeatureID = "X-Session-Feature-Id"
)

func ContextMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		rc := RequestContext{
			TraceID:          r.Header.Get(headerTraceID),
			BoundedContext:   r.Header.Get(headerBoundedContext),
			Feature:          r.Header.Get(headerFeature),
			SessionFeatureID: r.Header.Get(headerSessionFeatureID),
		}
		if rc.TraceID == "" {
			rc.TraceID = uuid.NewString()
		}

		ctx := context.WithValue(r.Context(), requestContextKey, rc)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}
```

When making outbound calls — HTTP or Kafka — the calling service injects all four fields. Downstream services extract them and include them in their canonical log line. The cost is a handful of headers; the payoff is a fully correlated, business-enriched log stream.

## Practical Example: A Checkout Journey

Let's trace a checkout through three services. The user confirms their order, and the request flows through the order service (HTTP), payment service (HTTP), and notification service (Kafka).

**Order Service** — canonical log:

```json
{
  "timestamp": "2026-03-08T14:23:01.482Z",
  "severity": "info",
  "service": "order-service",
  "trace_id": "abc-123-def",
  "bounded_context": "checkout",
  "feature": "standard-checkout",
  "session_feature_id": "sf-7891011",
  "user_id": "user-42",
  "method": "POST",
  "path": "/api/orders",
  "status": 201,
  "duration_ms": 312,
  "order_id": "order-99",
  "items_count": 3,
  "total_amount_cents": 8499
}
```

**Payment Service** — canonical log:

```json
{
  "timestamp": "2026-03-08T14:23:01.610Z",
  "severity": "info",
  "service": "payment-service",
  "trace_id": "abc-123-def",
  "bounded_context": "checkout",
  "feature": "standard-checkout",
  "session_feature_id": "sf-7891011",
  "user_id": "user-42",
  "method": "POST",
  "path": "/api/charges",
  "status": 200,
  "duration_ms": 187,
  "charge_id": "ch-5678",
  "provider": "stripe",
  "amount_cents": 8499
}
```

**Notification Service** (consumed from Kafka) — canonical log:

```json
{
  "timestamp": "2026-03-08T14:23:02.003Z",
  "severity": "info",
  "service": "notification-service",
  "trace_id": "abc-123-def",
  "bounded_context": "checkout",
  "feature": "standard-checkout",
  "session_feature_id": "sf-7891011",
  "user_id": "user-42",
  "kafka_topic": "order.confirmed",
  "kafka_partition": 2,
  "duration_ms": 45,
  "notification_type": "email",
  "template": "order-confirmation",
  "recipient": "user42@example.com"
}
```

Three services, three canonical logs, one shared `trace_id`. Each log carries the same `bounded_context`, `feature`, and `session_feature_id`, plus its own domain-specific fields.

### Querying the Journey

In Grafana with Loki, reconstructing the full journey is a single LogQL query:

{% raw %}
```logql
{service=~".+"} | json | session_feature_id="sf-7891011" | line_format "{{.timestamp}} [{{.service}}] {{.status}} {{.path}}{{.kafka_topic}} ({{.duration_ms}}ms)"
```
{% endraw %}

Want to see all checkout errors in the last hour?

```logql
{service=~".+"} | json | bounded_context="checkout" | status >= 500
```

Want to compare error rates between the new guest-checkout feature and standard checkout?

```logql
sum by (feature) (
  count_over_time(
    {service=~".+"} | json | bounded_context="checkout" | status >= 500 [1h]
  )
)
```

These queries work because the business dimensions are first-class fields on every log line, not something you have to join or look up from a separate system.

## How This Relates to (but Doesn't Replace) Distributed Tracing

If you're already using Jaeger, Tempo, or another distributed tracing system, you might wonder why you'd bother with log-based correlation.

Traces and correlated logs answer different questions.

**Distributed traces** (Jaeger, Tempo) give you a call graph. You see parent-child span relationships, precise timing waterfalls, and where latency accumulated across service boundaries. Traces answer: "which service call was slow, and why?" They're purpose-built for performance debugging and dependency analysis. When a checkout takes 3 seconds instead of 300 milliseconds, the trace waterfall shows you that 2.7 seconds were spent waiting for the payment provider's API.

**Log-based correlation** gives you a business narrative. You see what happened in a user's checkout journey, queryable by bounded context, feature, and session. Correlated logs answer: "what happened in the checkout flow for user X?" They're built for incident investigation and feature-level observability. When a user reports they were charged but didn't get a confirmation, log correlation shows you that the order service returned 201 and the payment service returned 200, but the notification service never received the Kafka message — pointing you to a broker or serialization issue.

They're complementary. In practice, you'll often start with a log query — "show me failed checkouts in the last hour" — find a suspicious `trace_id`, then jump to Tempo to see the timing waterfall for that specific request. The logs get you to the right needle; the trace shows you why it's bent.

## The Honest Tradeoffs

Log-based correlation doesn't replace distributed tracing. You lose span parent-child relationships, precise timing waterfalls, and async gap detection. But for many teams, `trace_id` correlation across canonical logs is a powerful first step that requires no new infrastructure — just disciplined propagation.

The hard part isn't the code. The middleware shown above is trivial to implement. The hard part is the discipline: every service, every outbound call, every Kafka producer must propagate the headers. One missing link breaks the chain for that request. Code reviews, shared libraries, and integration tests that assert header presence are how you maintain that discipline at scale.

The business dimensions require a different kind of discipline — alignment between engineering and product on what the bounded contexts, features, and session boundaries are. This is a conversation worth having. When your logging vocabulary matches your product vocabulary, your observability stops being an engineering tool and becomes an organizational one.

## What's Next

Now your logs are structured, correlated, and enriched with business context. In the next article, we'll turn this data into engineering metrics and Grafana dashboards — all derived from the logs you're already producing.
