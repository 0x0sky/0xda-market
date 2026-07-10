# frozen_string_literal: true

require_relative "test_helper"

class KernelTest < Minitest::Test
  include KernelFixture

  Core = ZeroXDA::Market::Core

  def setup
    @clock = MutableClock.new
    @provider = TestProvider.new(clock: @clock)
    @kernel, = build_kernel(provider: @provider, clock: @clock)
  end

  def test_completes_an_arbitrary_provider_defined_operation
    payload = {
      kind: "unknown.to.core",
      parameters: { exact: "0.000000001", recipient: ["opaque", 42] }
    }
    intent = @kernel.create_intent(
      capability: "anything.operation",
      payload: payload,
      context: { trace: "trace-1" }
    )
    quote = @kernel.quote_intent(intent.id)
    order = @kernel.accept_quote(quote.id)
    completed = @kernel.execute_order(order.id)

    assert_equal "succeeded", completed.status
    assert_equal payload.fetch(:kind), completed.payload.fetch("kind")
    assert_equal "done", completed.result.dig("data", "status")
    assert_equal "handle-#{intent.id}", @provider.executions.first
      .fetch(:order).private_state.fetch("handle")
  end

  def test_accept_and_successful_execution_are_idempotent
    intent = @kernel.create_intent(capability: "anything.operation", payload: {})
    quote = @kernel.quote_intent(intent.id)
    first_order = @kernel.accept_quote(quote.id)
    same_order = @kernel.accept_quote(quote.id)
    first_result = @kernel.execute_order(first_order.id)
    same_result = @kernel.execute_order(first_order.id)

    assert_equal first_order.id, same_order.id
    assert_equal first_result.id, same_result.id
    assert_equal 1, @provider.executions.length
    assert_equal "orders/#{first_order.id}/execute",
                 @provider.executions.first.fetch(:idempotency_key)
  end

  def test_rejects_an_expired_quote
    provider = TestProvider.new(clock: @clock, quote_ttl: 1)
    kernel, = build_kernel(provider: provider, clock: @clock)
    intent = kernel.create_intent(capability: "anything.operation", payload: {})
    quote = kernel.quote_intent(intent.id)
    @clock.advance(2)

    assert_raises(Core::QuoteExpired) { kernel.accept_quote(quote.id) }
  end

  def test_retries_only_an_explicitly_retryable_failure
    calls = 0
    provider = TestProvider.new(clock: @clock) do |order, _idempotency_key|
      calls += 1
      if calls == 1
        raise Core::ProviderFailure.new(
          "temporarily unavailable",
          code: "temporary",
          retryable: true,
          details: { order_id: order.id }
        )
      end

      Core::Contracts::ExecutionResult.new(reference: "recovered", data: {})
    end
    kernel, = build_kernel(provider: provider, clock: @clock)
    intent = kernel.create_intent(capability: "anything.operation", payload: {})
    quote = kernel.quote_intent(intent.id)
    order = kernel.accept_quote(quote.id)

    assert_raises(Core::ProviderFailure) { kernel.execute_order(order.id) }
    assert kernel.find_order(order.id).failure.fetch("retryable")

    completed = kernel.execute_order(order.id)
    assert_equal "succeeded", completed.status
    assert_equal 2, completed.attempts
  end

  def test_resumes_a_deferred_execution_without_counting_polling_as_an_attempt
    calls = 0
    provider = TestProvider.new(clock: @clock) do |_order, _idempotency_key|
      calls += 1
      if calls == 1
        Core::Contracts::PendingResult.new(
          reference: "task-1",
          data: { status: "awaiting_operator" }
        )
      else
        Core::Contracts::ExecutionResult.new(
          reference: "manual-result-1",
          data: { status: "completed" }
        )
      end
    end
    kernel, = build_kernel(provider: provider, clock: @clock)
    intent = kernel.create_intent(capability: "anything.operation", payload: {})
    quote = kernel.quote_intent(intent.id)
    order = kernel.accept_quote(quote.id)

    pending = kernel.execute_order(order.id)
    assert_equal "pending", pending.status
    assert_equal "task-1", pending.progress.fetch("reference")
    assert_equal 1, pending.attempts

    completed = kernel.execute_order(order.id)
    assert_equal "succeeded", completed.status
    assert_nil completed.progress
    assert_equal "manual-result-1", completed.result.fetch("reference")
    assert_equal 1, completed.attempts
  end

  def test_cancelled_order_cannot_execute
    intent = @kernel.create_intent(capability: "anything.operation", payload: {})
    quote = @kernel.quote_intent(intent.id)
    order = @kernel.accept_quote(quote.id)
    cancelled = @kernel.cancel_order(order.id)

    assert_equal "cancelled", cancelled.status
    assert_raises(Core::InvalidTransition) { @kernel.execute_order(order.id) }
  end

  def test_rejects_an_unknown_capability_before_persisting
    error = assert_raises(Core::UnknownCapability) do
      @kernel.create_intent(capability: "missing.operation", payload: {})
    end

    assert_equal "missing.operation", error.details.fetch("capability")
  end
end
