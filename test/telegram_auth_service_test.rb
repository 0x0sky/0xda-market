# frozen_string_literal: true

require_relative "test_helper"
require "zero_x_da/market/identity/memory_store"
require "zero_x_da/market/identity/telegram_auth_service"

class TelegramAuthServiceTest < Minitest::Test
  def setup
    @clock = MutableClock.new
    @service = ZeroXDA::Market::Identity::TelegramAuthService.new(
      store: ZeroXDA::Market::Identity::MemoryStore.new,
      clock: @clock,
      id_generator: SequenceIDs.new
    )
  end

  def test_creates_a_client_and_telegram_identity_on_first_authentication
    authentication = @service.authenticate(
      provider_user_id: 77,
      provider_data: { chat_id: "77", username: "zero" }
    )

    assert authentication.created
    assert_equal "id-1", authentication.user.id
    assert_equal "client", authentication.user.role
    assert_equal "active", authentication.user.status
    assert_equal "telegram", authentication.identity.provider
    assert_equal "77", authentication.identity.provider_user_id
    assert_equal "zero", authentication.identity.provider_data.fetch("username")
  end

  def test_reuses_the_user_and_updates_provider_data_on_next_authentication
    first = @service.authenticate(
      provider_user_id: "77",
      provider_data: { chat_id: "77", username: "old" }
    )
    @clock.advance(60)

    second = @service.authenticate(
      provider_user_id: 77,
      provider_data: { chat_id: "770", username: "new", language_code: "uk" }
    )

    refute second.created
    assert_equal first.user.id, second.user.id
    assert_equal first.identity.id, second.identity.id
    assert_equal 1, second.identity.version
    assert_equal "770", second.identity.provider_data.fetch("chat_id")
    assert_equal "new", second.identity.provider_data.fetch("username")
    assert_equal "uk", second.identity.provider_data.fetch("language_code")
    assert_operator second.identity.last_authenticated_at, :>, first.identity.last_authenticated_at
  end

  def test_different_telegram_accounts_create_different_users
    first = @service.authenticate(provider_user_id: 77, provider_data: { chat_id: "77" })
    second = @service.authenticate(provider_user_id: 78, provider_data: { chat_id: "78" })

    refute_equal first.user.id, second.user.id
  end

  def test_trusted_broker_authentication_creates_a_broker
    authentication = @service.authenticate(
      provider_user_id: 77,
      provider_data: { chat_id: "77" },
      role: "broker"
    )

    assert_equal "broker", authentication.user.role
  end

  def test_trusted_broker_authentication_promotes_an_existing_client
    @service.authenticate(provider_user_id: 77, provider_data: { chat_id: "77" })

    authentication = @service.authenticate(
      provider_user_id: 77,
      provider_data: { chat_id: "77" },
      role: "broker"
    )

    assert_equal "broker", authentication.user.role
    assert_equal 1, authentication.user.version
  end

  def test_client_authentication_does_not_downgrade_a_broker
    @service.authenticate(
      provider_user_id: 77,
      provider_data: { chat_id: "77" },
      role: "broker"
    )

    authentication = @service.authenticate(
      provider_user_id: 77,
      provider_data: { chat_id: "77" }
    )

    assert_equal "broker", authentication.user.role
  end

  def test_authentication_cannot_assign_admin_role
    error = assert_raises(ArgumentError) do
      @service.authenticate(
        provider_user_id: 77,
        provider_data: { chat_id: "77" },
        role: "admin"
      )
    end

    assert_includes error.message, "role is invalid"
  end

  def test_rejects_an_invalid_telegram_user_id
    error = assert_raises(ArgumentError) do
      @service.authenticate(provider_user_id: "not-a-number", provider_data: {})
    end

    assert_includes error.message, "positive integer"
  end

  def test_explicit_bootstrap_creates_an_admin
    result = @service.bootstrap_admin(
      provider_user_id: 77,
      provider_data: { chat_id: "77", username: "owner" }
    )

    assert result.created
    assert_equal "admin", result.user.role

    authentication = @service.authenticate(
      provider_user_id: 77,
      provider_data: { chat_id: "77", username: "owner" }
    )
    assert_equal "admin", authentication.user.role
  end

  def test_explicit_bootstrap_promotes_an_existing_user_without_overwriting_identity
    original = @service.authenticate(
      provider_user_id: 77,
      provider_data: { chat_id: "77", username: "owner" }
    )

    result = @service.bootstrap_admin(
      provider_user_id: 77,
      provider_data: { username: "ignored" }
    )

    refute result.created
    assert_equal "admin", result.user.role
    assert_equal original.identity.provider_data, result.identity.provider_data
  end

  def test_explicit_bootstrap_is_idempotent
    first = @service.bootstrap_admin(provider_user_id: 77)
    second = @service.bootstrap_admin(provider_user_id: 77)

    assert first.created
    refute second.created
    assert_equal first.user.id, second.user.id
    assert_equal "admin", second.user.role
  end

  def test_admin_promotes_a_registered_user_by_username
    service = build_service
    service.bootstrap_admin(
      provider_user_id: 77,
      provider_data: { chat_id: "77", username: "owner" }
    )
    service.authenticate(
      provider_user_id: 78,
      provider_data: { chat_id: "780", username: "Target_User" }
    )

    assignment = service.set_admin(
      actor_provider_user_id: 77,
      target: "@target_user"
    )

    assert assignment.changed
    assert_equal "admin", assignment.user.role
    assert_equal "78", assignment.identity.provider_user_id
    assert_equal "780", assignment.identity.provider_data.fetch("chat_id")
  end

  def test_admin_assignment_by_telegram_id_is_idempotent
    service = build_service
    service.bootstrap_admin(provider_user_id: 77)
    service.authenticate(provider_user_id: 78, provider_data: { chat_id: "78" })

    first = service.set_admin(actor_provider_user_id: 77, target: "78")
    second = service.set_admin(actor_provider_user_id: 77, target: "78")

    assert first.changed
    refute second.changed
    assert_equal first.user.id, second.user.id
  end

  def test_client_cannot_promote_another_user
    @service.authenticate(provider_user_id: 77, provider_data: { chat_id: "77" })
    @service.authenticate(provider_user_id: 78, provider_data: { chat_id: "78" })

    error = assert_raises(ZeroXDA::Market::Core::Forbidden) do
      @service.set_admin(actor_provider_user_id: 77, target: "78")
    end

    assert_equal "forbidden", error.code
  end

  private

  def build_service
    ZeroXDA::Market::Identity::TelegramAuthService.new(
      store: ZeroXDA::Market::Identity::MemoryStore.new,
      clock: @clock,
      id_generator: SequenceIDs.new
    )
  end
end
