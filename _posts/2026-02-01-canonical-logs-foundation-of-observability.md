---
layout: post
title: "Canonical Logs — The Foundation of Effective Observability"
description: "How one structured log event per request can replace dozens of scattered log lines and become the foundation of your observability stack."
date: 2026-02-01
tags: [observability, logging, architecture, go]
---

You've inherited a codebase. Something is broken in production. A customer reports they can't complete checkout. You open the logs and find... 47 scattered log lines across 6 files for a single HTTP request. None of them have the user ID. Half of them say `"processing request"`. One says `"error occurred"` with no further context. Good luck.

This is the state of logging in most backend services. Not because people don't care, but because no one decided *how* logging should work. Everyone just sprinkled `log.Info` wherever it felt right.

There's a better way.

## The problem with scattered logging

Here's what typical Go handler code looks like in the wild:

```go
func (h *Handler) Checkout(w http.ResponseWriter, r *http.Request) {
    log.Info("checkout handler called")

    userID := r.Header.Get("X-User-ID")
    log.Info("got user", "id", userID)

    cart, err := h.cartService.Get(r.Context(), userID)
    if err != nil {
        log.Error("failed to get cart", "error", err)
        http.Error(w, "internal error", http.StatusInternalServerError)
        return
    }
    log.Info("cart retrieved", "items", len(cart.Items))

    order, err := h.orderService.Create(r.Context(), cart)
    if err != nil {
        log.Error("order creation failed", "error", err)
        http.Error(w, "internal error", http.StatusInternalServerError)
        return
    }
    log.Info("order created", "order_id", order.ID)

    log.Info("checkout complete")
    json.NewEncoder(w).Encode(order)
}
```

Six log lines for one request. And this is a *simple* handler. In the real world, the cart service logs too. So does the order service. So does the database layer. You end up with dozens of lines per request, and they all share the same problems:

- **No correlation.** Which lines belong to the same request? You have to squint at timestamps and hope.
- **No consistent context.** Some lines have the user ID, most don't. None have the subscription tier, the cart value, or the feature flag state.
- **Different formats.** The handler logs strings. The service layer logs structured fields. The database layer uses `fmt.Printf`.
- **Impossible to query.** "Show me all failed checkout requests for premium users in the last hour" is a question you simply cannot answer.

The root cause isn't laziness. It's the absence of a *pattern*. When there's no agreed-upon approach to logging, people default to narrating their code — logging what they're *doing* instead of what *happened*.

## What is a canonical log line?

A canonical log line — sometimes called a *wide event* — is a single structured log event emitted once per request per service, at the end of the request lifecycle. It contains everything you need to know about that request in one place.

The idea was popularized by Stripe in their [blog post on canonical log lines](https://stripe.com/blog/canonical-log-lines). The concept is simple but transformative:

> Instead of scattering context across many log lines, you accumulate context throughout the request lifecycle and emit it all at once.

A canonical log line might contain 20, 30, even 50 fields: HTTP method, path, status code, duration, user ID, subscription tier, feature flags evaluated, database queries executed, cache hits, error codes, and anything else that matters for debugging and analysis.

The key properties:

1. **One per request per service.** Not one per function. Not one per error. One.
2. **Emitted at the end.** Because only at the end do you know the full story — the status code, the total duration, whether it succeeded or failed.
3. **Wide, not deep.** It's a flat structure with many fields, not a nested object. This makes it trivially queryable.
4. **Accumulated, not assembled.** Different layers of your application *enrich* the event as the request flows through them. No single layer knows everything.

## The middleware pattern

The canonical log line needs an owner — something that sees the beginning and the end of every request. In Go HTTP services, that's middleware.

```go
package middleware

import (
    "context"
    "log/slog"
    "net/http"
    "time"

    "github.com/google/uuid"
)

type canonicalKey struct{}

// CanonicalEvent holds all fields that will be emitted as one log line.
type CanonicalEvent struct {
    fields []any
}

func (e *CanonicalEvent) Set(key string, value any) {
    e.fields = append(e.fields, key, value)
}

// EventFromContext retrieves the canonical event from the request context.
func EventFromContext(ctx context.Context) *CanonicalEvent {
    e, _ := ctx.Value(canonicalKey{}).(*CanonicalEvent)
    return e
}

func CanonicalLog(logger *slog.Logger) func(http.Handler) http.Handler {
    return func(next http.Handler) http.Handler {
        return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
            start := time.Now()
            requestID := uuid.New().String()

            event := &CanonicalEvent{}
            event.Set("http_method", r.Method)
            event.Set("http_path", r.URL.Path)
            event.Set("request_id", requestID)

            ctx := context.WithValue(r.Context(), canonicalKey{}, event)
            r = r.WithContext(ctx)

            rec := &statusRecorder{ResponseWriter: w, statusCode: http.StatusOK}

            defer func() {
                event.Set("http_status", rec.statusCode)
                event.Set("duration_ms", time.Since(start).Milliseconds())
                logger.LogAttrs(
                    r.Context(),
                    levelFromStatus(rec.statusCode),
                    "request_completed",
                    attrsFromFields(event.fields)...,
                )
            }()

            next.ServeHTTP(rec, r)
        })
    }
}

type statusRecorder struct {
    http.ResponseWriter
    statusCode int
}

func (r *statusRecorder) WriteHeader(code int) {
    r.statusCode = code
    r.ResponseWriter.WriteHeader(code)
}

func levelFromStatus(code int) slog.Level {
    if code >= 500 {
        return slog.LevelError
    }
    if code >= 400 {
        return slog.LevelWarn
    }
    return slog.LevelInfo
}

func attrsFromFields(fields []any) []slog.Attr {
    attrs := make([]slog.Attr, 0, len(fields)/2)
    for i := 0; i < len(fields)-1; i += 2 {
        key, _ := fields[i].(string)
        attrs = append(attrs, slog.Any(key, fields[i+1]))
    }
    return attrs
}
```

The middleware does three things:

1. **Creates** the canonical event and injects it into the request context.
2. **Seeds** the event with infrastructure context — method, path, request ID, start time.
3. **Defers** the emission of the single log line until the request is complete, capturing the final status code and duration.

Nothing else in your application emits request-scoped log lines. Everything else *enriches*.

## The layer responsibility model

This is where the pattern either succeeds or falls apart. Every layer in your application has a clear, distinct role with respect to the canonical event.

### Middleware: owns the lifecycle

The middleware creates the event, captures infrastructure context, and emits it. We covered this above. It owns `http_method`, `http_path`, `http_status`, `duration_ms`, and `request_id`. No business logic lives here.

### Service layer: enriches with business context

The service layer is where your application logic lives. It knows *what* is happening in business terms. Its job is to enrich the canonical event with business context — but never to emit its own log lines.

```go
package service

import (
    "context"
    "fmt"

    "yourapp/middleware"
    "yourapp/repository"
)

type CheckoutService struct {
    carts  repository.CartRepository
    orders repository.OrderRepository
    users  repository.UserRepository
}

func (s *CheckoutService) Checkout(ctx context.Context, userID string) (*Order, error) {
    event := middleware.EventFromContext(ctx)
    event.Set("user_id", userID)

    user, err := s.users.Get(ctx, userID)
    if err != nil {
        event.Set("error_code", "user_not_found")
        return nil, fmt.Errorf("get user: %w", err)
    }
    event.Set("subscription_tier", user.Tier)

    cart, err := s.carts.Get(ctx, userID)
    if err != nil {
        event.Set("error_code", "cart_fetch_failed")
        return nil, fmt.Errorf("get cart: %w", err)
    }
    event.Set("cart_item_count", len(cart.Items))
    event.Set("cart_value_cents", cart.TotalCents)

    order, err := s.orders.Create(ctx, cart)
    if err != nil {
        event.Set("error_code", "order_creation_failed")
        return nil, fmt.Errorf("create order: %w", err)
    }
    event.Set("order_id", order.ID)
    event.Set("feature_name", "checkout")

    return order, nil
}
```

Notice what this code does *not* do: it doesn't call `slog.Info`. It doesn't emit anything. It enriches the canonical event and moves on. When the request completes — whether successfully or with an error — the middleware emits one line containing all of this context.

Also notice the error handling: instead of logging the error and returning, the service sets an `error_code` field on the canonical event and returns the error up the chain. The handler (or middleware) decides the HTTP status code. The canonical event captures everything.

### Repository layer: returns data, doesn't log

The repository layer is the most counterintuitive part. It should not log, and it should not touch the canonical event directly. If it has data worth capturing — like query duration — it returns that data to the service layer.

```go
package repository

import (
    "context"
    "database/sql"
    "time"
)

type QueryStats struct {
    Duration time.Duration
    RowCount int
}

type CartRepository struct {
    db *sql.DB
}

func (r *CartRepository) Get(ctx context.Context, userID string) (*Cart, *QueryStats, error) {
    start := time.Now()

    rows, err := r.db.QueryContext(ctx,
        `SELECT id, product_id, quantity, price_cents FROM cart_items WHERE user_id = $1`,
        userID,
    )
    if err != nil {
        return nil, nil, err
    }
    defer rows.Close()

    var items []CartItem
    for rows.Next() {
        var item CartItem
        if err := rows.Scan(&item.ID, &item.ProductID, &item.Quantity, &item.PriceCents); err != nil {
            return nil, nil, err
        }
        items = append(items, item)
    }

    stats := &QueryStats{
        Duration: time.Since(start),
        RowCount: len(items),
    }
    return &Cart{Items: items}, stats, nil
}
```

The service layer then uses these stats to enrich the canonical event:

```go
cart, cartStats, err := s.carts.Get(ctx, userID)
if err != nil {
    event.Set("error_code", "cart_fetch_failed")
    return nil, fmt.Errorf("get cart: %w", err)
}
event.Set("cart_query_ms", cartStats.Duration.Milliseconds())
event.Set("cart_item_count", cartStats.RowCount)
event.Set("cart_value_cents", cart.TotalCents)
```

Why this indirection? Because the repository shouldn't know or care about observability concerns. It's a data access layer. Returning performance data as part of its contract keeps it testable, keeps the canonical event assembly in one place (the service layer), and prevents the kind of log-line sprawl we started with.

## The result

After all of this, here is what your logs look like. One line per request:

```json
{
  "time": "2026-02-28T14:32:01.482Z",
  "level": "INFO",
  "msg": "request_completed",
  "http_method": "POST",
  "http_path": "/api/v1/checkout",
  "request_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "http_status": 200,
  "duration_ms": 247,
  "user_id": "usr_8xk2m",
  "subscription_tier": "premium",
  "cart_item_count": 3,
  "cart_value_cents": 14990,
  "cart_query_ms": 12,
  "order_id": "ord_9f3n2p",
  "feature_name": "checkout"
}
```

And when things fail:

```json
{
  "time": "2026-02-28T14:32:05.119Z",
  "level": "ERROR",
  "msg": "request_completed",
  "http_method": "POST",
  "http_path": "/api/v1/checkout",
  "request_id": "f7e6d5c4-b3a2-1098-fedc-ba9876543210",
  "http_status": 500,
  "duration_ms": 1834,
  "user_id": "usr_3jp7q",
  "subscription_tier": "premium",
  "cart_item_count": 7,
  "cart_value_cents": 52300,
  "cart_query_ms": 1502,
  "error_code": "order_creation_failed",
  "feature_name": "checkout"
}
```

That second event tells you a complete story without opening a single file of source code. The checkout failed. It was a premium user. The cart query took 1.5 seconds (probably the root cause). The order creation failed downstream. You have the request ID if you need to correlate with traces. You have the user ID if you need to reach out.

Now you can answer real questions against your log storage:

```
http_path="/api/v1/checkout" AND http_status>=500 AND subscription_tier="premium" AND @timestamp>now()-1h
```

*"Find all failed checkout requests for premium users in the last hour."* One query. Instant answers.

You can also build dashboards, set up alerts on `error_code` distributions, track p99 `cart_query_ms` over time, and compute checkout conversion rates by subscription tier — all from the same log line.

## What canonical logs don't replace

Canonical logs don't replace metrics, traces, or dedicated user tracking. Metrics are better for aggregated time-series at high frequency — you want a counter for requests per second, not a log query. Traces are better for cross-service request flow visualization — when a checkout spans five services, you need a flame graph, not a log line. And dedicated user tracking systems are better for product analytics that need to survive schema changes and retroactive analysis.

But for many teams — especially those starting out or looking to reduce observability costs — structured canonical logs are the most accessible starting point and a powerful foundation that gets you surprisingly far. They require no additional infrastructure beyond what you're already running for logs. They don't need a vendor. They work with `grep` in a pinch. And they force a level of discipline in your codebase that pays dividends well beyond observability.

## Practical considerations

**What about debug logging?** Keep it. Canonical logs are your structured, queryable, always-on observability layer. Debug logs behind a log level are still useful for local development and for investigating specific issues when you need more detail. The point isn't to eliminate all other log lines — it's to ensure that the *canonical* line is always there, always complete, and always queryable.

**What about high-cardinality fields?** Be intentional. User IDs, request IDs, and order IDs are fine — they're the whole point. But don't add unbounded fields like full request bodies or stack traces. Those belong in supplementary log lines or error tracking systems.

**Thread safety?** The `CanonicalEvent` shown above uses a slice, which isn't safe for concurrent writes. In production, protect it with a `sync.Mutex` or use a purpose-built concurrent map. In most HTTP services this isn't an issue because handlers run on a single goroutine per request, but if you fan out to concurrent goroutines, you'll need synchronization.

**What about gRPC or event-driven services?** The pattern adapts cleanly. For gRPC, use a unary interceptor instead of HTTP middleware. For event consumers, wrap your message handler. The principle is identical: one structured event per unit of work, emitted at the boundary.

## What's next

This is the foundation. One service, one log line per request, everything you need to debug and analyze in one place. But production systems don't live in isolation. Requests flow across services, and the question becomes: how do you follow a single user action through your entire system?

In the next article, we'll take this pattern across service boundaries with distributed logging and `trace_id` propagation — connecting canonical log lines from different services into a coherent story, without reaching for a full distributed tracing system on day one.
