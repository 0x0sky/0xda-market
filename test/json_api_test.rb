# frozen_string_literal: true

require_relative "test_helper"
require "rack/mock"
require "zero_x_da/market/transport/json_api"

class JSONAPITest < Minitest::Test
  include KernelFixture

  def setup
    clock = MutableClock.new
    @provider = TestProvider.new(clock: clock)
    kernel, = build_kernel(provider: @provider, clock: clock)
    @client = Rack::MockRequest.new(
      ZeroXDA::Market::Transport::JSONAPI.new(kernel: kernel)
    )
  end

  def test_complete_http_lifecycle_hides_private_provider_state
    intent = resource(
      post_json(
        "/v1/intents",
        {
          capability: "anything.operation",
          payload: { arbitrary: { shape: [1, 2, 3] } },
          context: { actor: "opaque-actor" }
        }
      ),
      expected_status: 201
    )
    quote = resource(
      post_json("/v1/intents/#{intent.fetch("id")}/quotes", {}),
      expected_status: 201
    )
    refute quote.fetch("attributes").key?("private_state")

    order = resource(
      post_json("/v1/quotes/#{quote.fetch("id")}/accept", {}),
      expected_status: 201
    )
    result = resource(
      post_json("/v1/orders/#{order.fetch("id")}/execute", {}),
      expected_status: 200
    )

    assert_equal "succeeded", result.dig("attributes", "status")
    refute result.fetch("attributes").key?("private_state")
  end

  def test_health_endpoint
    response = @client.get("/health")

    assert_equal 200, response.status
    assert_equal({ "status" => "ok" }, JSON.parse(response.body))
  end

  def test_reports_invalid_json
    response = @client.post(
      "/v1/intents",
      "CONTENT_TYPE" => "application/json",
      input: "{"
    )

    assert_equal 400, response.status
    assert_equal "invalid_json", JSON.parse(response.body).dig("errors", 0, "code")
  end

  def test_reports_unknown_capability
    response = post_json(
      "/v1/intents",
      { capability: "unknown.operation", payload: {} }
    )

    assert_equal 422, response.status
    assert_equal "unknown_capability", JSON.parse(response.body).dig("errors", 0, "code")
  end

  private

  def post_json(path, body)
    @client.post(
      path,
      "CONTENT_TYPE" => "application/json",
      input: JSON.generate(body)
    )
  end

  def resource(response, expected_status:)
    assert_equal expected_status, response.status, response.body
    JSON.parse(response.body).fetch("data")
  end
end

