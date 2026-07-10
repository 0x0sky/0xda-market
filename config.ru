# frozen_string_literal: true

require "bundler/setup"
require "securerandom"
require_relative "lib/zero_x_da/market/core/kernel"
require_relative "lib/zero_x_da/market/adapters/memory_store"
require_relative "lib/zero_x_da/market/providers/manual_provider"
require_relative "lib/zero_x_da/market/transport/json_api"
require_relative "lib/zero_x_da/market/transport/manual_api"

clock = -> { Time.now.utc }
operator_token = ENV["MANUAL_PROVIDER_TOKEN"]
manual_provider = if operator_token && !operator_token.empty?
                    ZeroXDA::Market::Providers::ManualProvider.new(
                      key: "manual.default",
                      clock: clock
                    )
                  end
providers = manual_provider ? { "manual.fulfillment" => manual_provider } : {}

kernel = ZeroXDA::Market::Core::Kernel.new(
  providers: providers,
  store: ZeroXDA::Market::Adapters::MemoryStore.new,
  clock: clock,
  id_generator: SecureRandom.method(:uuid)
)

public_api = ZeroXDA::Market::Transport::JSONAPI.new(kernel: kernel)

if manual_provider
  operator_api = ZeroXDA::Market::Transport::ManualAPI.new(
    provider: manual_provider,
    token: operator_token
  )
  run Rack::URLMap.new("/operator" => operator_api, "/" => public_api)
else
  run public_api
end
