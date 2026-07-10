# frozen_string_literal: true

require_relative "test_helper"

class ContractsTest < Minitest::Test
  Core = ZeroXDA::Market::Core

  def test_quote_result_separates_public_terms_from_private_state
    result = Core::Contracts::QuoteResult.new(
      terms: { summary: "public" },
      private_state: { handle: "private" },
      expires_at: Time.utc(2026, 7, 10, 12, 1, 0)
    )

    assert_equal "public", result.terms.fetch("summary")
    assert_equal "private", result.private_state.fetch("handle")
    assert result.frozen?
    assert result.private_state.frozen?
  end

  def test_execution_result_is_an_immutable_public_document
    result = Core::Contracts::ExecutionResult.new(
      reference: "external-1",
      data: { status: "done" }
    )

    assert_equal "external-1", result.reference
    assert_equal "done", result.data.fetch("status")
    assert result.data.frozen?
  end

  def test_pending_result_carries_pollable_provider_progress
    result = Core::Contracts::PendingResult.new(
      reference: "task-1",
      data: { status: "awaiting_operator" }
    )

    assert_equal "task-1", result.reference
    assert_equal "awaiting_operator", result.data.fetch("status")
    assert result.frozen?
    assert result.data.frozen?
  end

  def test_provider_contract_reports_missing_methods
    error = assert_raises(Core::ProviderContractError) do
      Core::Contracts.validate_provider!(Object.new)
    end

    assert_equal %w[key quote execute], error.details.fetch("missing_methods")
  end

  def test_provider_failure_carries_retry_policy
    error = Core::ProviderFailure.new(
      "temporarily unavailable",
      code: "temporary",
      retryable: true,
      details: { upstream: "provider" }
    )

    assert error.retryable
    assert_equal "temporary", error.code
    assert_equal "provider", error.details.fetch("upstream")
  end
end
