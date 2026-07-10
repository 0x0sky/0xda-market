# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/zero_x_da/market/core/records"

class RecordsTest < Minitest::Test
  Core = ZeroXDA::Market::Core

  def setup
    @now = Time.utc(2026, 7, 10, 12, 0, 0)
  end

  def test_intent_keeps_an_immutable_provider_defined_document
    payload = {
      kind: "unknown.to.core",
      parameters: ["exact-value", 42, true, nil]
    }

    intent = Core::Intent.new(
      id: "intent-1",
      capability: "provider.operation",
      payload: payload,
      created_at: @now
    )
    payload[:parameters] << "later mutation"

    assert_equal "unknown.to.core", intent.payload.fetch("kind")
    assert_equal ["exact-value", 42, true, nil], intent.payload.fetch("parameters")
    assert intent.frozen?
    assert intent.payload.frozen?
    assert intent.payload.fetch("parameters").frozen?
  end

  def test_quote_expiry_uses_server_time
    quote = Core::Quote.new(
      id: "quote-1",
      intent_id: "intent-1",
      provider_key: "provider-1",
      terms: { summary: "opaque public terms" },
      private_state: { handle: "provider-only" },
      expires_at: @now + 60,
      created_at: @now
    )

    refute quote.expired?(at: @now + 59)
    assert quote.expired?(at: @now + 60)
    assert_equal "provider-only", quote.private_state.fetch("handle")
  end

  def test_order_is_an_accepted_immutable_snapshot
    order = Core::Order.new(
      id: "order-1",
      intent_id: "intent-1",
      quote_id: "quote-1",
      capability: "provider.operation",
      provider_key: "provider-1",
      payload: { request: "opaque" },
      terms: { response: "opaque" },
      created_at: @now
    )

    assert_equal "accepted", order.status
    assert_equal 0, order.attempts
    assert_equal 0, order.version
    assert order.frozen?
  end

  def test_rejects_values_that_cannot_cross_the_json_boundary
    assert_raises(ArgumentError) do
      Core::Intent.new(
        id: "intent-1",
        capability: "provider.operation",
        payload: { unsafe: Object.new },
        created_at: @now
      )
    end
  end
end

