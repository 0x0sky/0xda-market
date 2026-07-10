# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "minitest/autorun"
require "zero_x_da/market/core/kernel"
require "zero_x_da/market/adapters/memory_store"

class MutableClock
  attr_reader :now

  def initialize(now = Time.utc(2026, 7, 10, 12, 0, 0))
    @now = now
  end

  def call
    now
  end

  def advance(seconds)
    @now += seconds
  end
end

class SequenceIDs
  def initialize
    @value = 0
  end

  def call
    @value += 1
    "id-#{@value}"
  end
end

class TestProvider
  attr_reader :key, :quoted_intents, :executions

  def initialize(key: "provider.test", clock:, quote_ttl: 60, &execution)
    @key = key
    @clock = clock
    @quote_ttl = quote_ttl
    @execution = execution
    @quoted_intents = []
    @executions = []
  end

  def quote(intent:)
    @quoted_intents << intent
    ZeroXDA::Market::Core::Contracts::QuoteResult.new(
      terms: {
        accepted_payload: intent.payload,
        provider_note: "opaque to the kernel"
      },
      private_state: { handle: "handle-#{intent.id}" },
      expires_at: @clock.call + @quote_ttl
    )
  end

  def execute(order:, idempotency_key:)
    @executions << { order: order, idempotency_key: idempotency_key }
    return @execution.call(order, idempotency_key) if @execution

    ZeroXDA::Market::Core::Contracts::ExecutionResult.new(
      reference: "external-#{order.id}",
      data: { status: "done" }
    )
  end
end

module KernelFixture
  def build_kernel(provider:, clock:, capability: "anything.operation")
    store = ZeroXDA::Market::Adapters::MemoryStore.new
    kernel = ZeroXDA::Market::Core::Kernel.new(
      providers: { capability => provider },
      store: store,
      clock: clock,
      id_generator: SequenceIDs.new
    )

    [kernel, store]
  end
end

