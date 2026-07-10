# frozen_string_literal: true

require_relative "test_helper"
require "rack/mock"

class RuntimeTest < Minitest::Test
  def test_starts_in_health_only_mode_without_an_operator_token
    with_operator_token(nil) do
      app = Rack::Builder.parse_file(File.expand_path("../config.ru", __dir__))

      health = Rack::MockRequest.new(app).get("/health")
      assert_equal 200, health.status

      intent = post_json(
        app,
        "/v1/intents",
        capability: "manual.fulfillment",
        payload: {}
      )
      assert_equal 422, intent.status
    end
  end

  def test_mounts_manual_provider_when_an_operator_token_is_configured
    with_operator_token("runtime-secret") do
      app = Rack::Builder.parse_file(File.expand_path("../config.ru", __dir__))

      intent = post_json(
        app,
        "/v1/intents",
        capability: "manual.fulfillment",
        payload: { action: "deliver" }
      )
      assert_equal 201, intent.status

      unauthorized = Rack::MockRequest.new(app).get("/operator/v1/tasks")
      assert_equal 401, unauthorized.status
    end
  end

  private

  def with_operator_token(value)
    previous = ENV["MANUAL_PROVIDER_TOKEN"]
    if value
      ENV["MANUAL_PROVIDER_TOKEN"] = value
    else
      ENV.delete("MANUAL_PROVIDER_TOKEN")
    end
    yield
  ensure
    if previous
      ENV["MANUAL_PROVIDER_TOKEN"] = previous
    else
      ENV.delete("MANUAL_PROVIDER_TOKEN")
    end
  end

  def post_json(app, path, body)
    Rack::MockRequest.new(app).post(
      path,
      "CONTENT_TYPE" => "application/json",
      input: JSON.generate(body)
    )
  end
end
