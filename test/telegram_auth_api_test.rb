# frozen_string_literal: true

require_relative "test_helper"
require "rack/mock"
require "zero_x_da/market/identity/memory_store"
require "zero_x_da/market/identity/telegram_auth_service"
require "zero_x_da/market/transport/json_api"

class TelegramAuthAPITest < Minitest::Test
  include KernelFixture

  def setup
    clock = MutableClock.new
    provider = TestProvider.new(clock: clock)
    kernel, = build_kernel(provider: provider, clock: clock)
    identity_service = ZeroXDA::Market::Identity::TelegramAuthService.new(
      store: ZeroXDA::Market::Identity::MemoryStore.new,
      clock: clock,
      id_generator: SequenceIDs.new
    )
    @client = Rack::MockRequest.new(
      ZeroXDA::Market::Transport::JSONAPI.new(
        kernel: kernel,
        token: "client-secret",
        identity_service: identity_service
      )
    )
  end

  def test_authenticates_a_telegram_client_and_reuses_its_user_id
    first = post_auth(
      telegram_user_id: 77,
      chat_id: 77,
      username: "zero",
      first_name: "Sasha",
      language_code: "uk"
    )
    assert_equal 201, first.status
    first_user = JSON.parse(first.body).fetch("data")
    assert first_user.dig("meta", "created")
    assert_equal "client", first_user.dig("attributes", "role")
    assert_equal "77", first_user.dig("attributes", "identity", "provider_user_id")

    second = post_auth(
      telegram_user_id: "77",
      chat_id: "770",
      username: "zero_updated"
    )
    assert_equal 200, second.status
    second_user = JSON.parse(second.body).fetch("data")
    assert_equal first_user.fetch("id"), second_user.fetch("id")
    refute second_user.dig("meta", "created")
    assert_equal "770", second_user.dig("attributes", "identity", "provider_data", "chat_id")
  end

  def test_requires_the_bot_bearer_token
    response = @client.post(
      "/v1/auth/telegram",
      "CONTENT_TYPE" => "application/json",
      input: JSON.generate(telegram_user_id: 77, chat_id: 77)
    )

    assert_equal 401, response.status
  end

  def test_requires_chat_id
    response = post_auth(telegram_user_id: 77)

    assert_equal 400, response.status
    assert_equal "chat_id", JSON.parse(response.body).dig("errors", 0, "details", "field")
  end

  private

  def post_auth(body)
    @client.post(
      "/v1/auth/telegram",
      "HTTP_AUTHORIZATION" => "Bearer client-secret",
      "CONTENT_TYPE" => "application/json",
      input: JSON.generate(body)
    )
  end
end
