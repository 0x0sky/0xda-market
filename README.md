# 0xda Market

Provider-agnostic execution core for turning a client intent into a quoted,
accepted and fulfilled order.

The core does not know what is being bought, sold or performed. Capabilities,
payloads, quote terms and provider state remain opaque JSON documents, so a
provider can represent a blockchain operation, a digital product or a human
workflow without changing the lifecycle engine.

## Current status

The repository contains a runnable Rack application with:

- immutable intent, quote and order records;
- provider contracts and normalized provider failures;
- idempotent quote acceptance and order execution;
- synchronous and deferred execution;
- optimistic concurrency and transactional in-memory storage;
- a public JSON API;
- an authenticated operator API for `ManualProvider`;
- a complete in-memory manual fulfillment workflow.

The current store is intentionally ephemeral. Restarting the process removes
all records and manual tasks.

## Lifecycle

```text
intent -> quote -> accepted order -> processing -> succeeded
                                      |
                                      +-> pending -> processing -> succeeded
                                      |
                                      +-> failed (retryable or terminal)
                                      |
                                      +-> cancelled
```

Providers implement three methods:

```ruby
provider.key
provider.quote(intent:)
provider.execute(order:, idempotency_key:)
```

`execute` returns either a final `ExecutionResult` or a `PendingResult`. A
pending order can be executed again to poll or resume provider work. Polling a
pending execution does not increase the attempt counter.

## ManualProvider

`ManualProvider` turns execution into an operator task. This allows an iOS
app, CLI, WhatsApp bot or another operator-facing client to fulfill orders
without coupling that client to the core.

1. A consumer creates an intent with capability `manual.fulfillment`.
2. The consumer creates and accepts a quote.
3. Executing the order creates one idempotent manual task and returns `pending`.
4. An authenticated operator client lists and completes or rejects the task.
5. Executing the pending order again resolves it from the operator decision.

The provider and its operator task queue are in memory. Durable storage and
task claiming are the next infrastructure boundary, not core concerns.

## Run

Ruby `3.3.11` is required.

```sh
bundle install
MANUAL_PROVIDER_TOKEN=replace-me bundle exec rackup
```

Without `MANUAL_PROVIDER_TOKEN`, the application starts in health-only mode
with no registered capability. With the token set, it exposes:

- public API: `http://localhost:9292/v1/...`
- operator API: `http://localhost:9292/operator/v1/...`
- health check: `http://localhost:9292/health`

Do not expose the operator API with a short or shared token.

## Public API example

Create an intent:

```sh
curl -sS http://localhost:9292/v1/intents \
  -H 'content-type: application/json' \
  -d '{
    "capability": "manual.fulfillment",
    "payload": {"action": "deliver", "item": "example"},
    "context": {"customer_id": "customer-1"}
  }'
```

Continue the lifecycle using the returned identifiers:

```sh
curl -sS -X POST http://localhost:9292/v1/intents/INTENT_ID/quotes \
  -H 'content-type: application/json' -d '{}'

curl -sS -X POST http://localhost:9292/v1/quotes/QUOTE_ID/accept \
  -H 'content-type: application/json' -d '{}'

curl -sS -X POST http://localhost:9292/v1/orders/ORDER_ID/execute \
  -H 'content-type: application/json' -d '{}'
```

The first execution returns an order with status `pending` and a manual task
identifier in `data.attributes.progress.reference`.

## Operator API example

```sh
curl -sS http://localhost:9292/operator/v1/tasks?status=pending \
  -H 'authorization: Bearer replace-me'

curl -sS -X POST \
  http://localhost:9292/operator/v1/tasks/TASK_ID/complete \
  -H 'authorization: Bearer replace-me' \
  -H 'content-type: application/json' \
  -d '{
    "reference": "external-result-1",
    "data": {"delivered": true}
  }'
```

An operator can reject a task instead:

```sh
curl -sS -X POST \
  http://localhost:9292/operator/v1/tasks/TASK_ID/reject \
  -H 'authorization: Bearer replace-me' \
  -H 'content-type: application/json' \
  -d '{
    "message": "cannot fulfill",
    "code": "out_of_scope",
    "details": {"category": "unsupported"}
  }'
```

## Test

```sh
bundle exec rake
```

## Architecture

```text
Consumer clients                 Operator clients
iOS / CLI / bot / HTTP           iOS / CLI / WhatsApp bot
        |                                  |
        v                                  v
Public JSON API                     Manual operator API
        |                                  |
        v                                  v
Provider-agnostic core  <----->       ManualProvider
        |
        v
Store adapter
```

Provider-specific behavior lives under `lib/zero_x_da/market/providers`.
The core never imports a provider implementation.

## Next boundaries

- durable SQL-backed store;
- durable manual task repository and task claiming;
- request authentication and consumer ownership;
- capability-specific quote policies;
- deployment packaging and production observability;
- external providers added independently of the core.

## License

MIT
