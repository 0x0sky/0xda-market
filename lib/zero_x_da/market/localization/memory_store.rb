# frozen_string_literal: true

require_relative "fx_rate"

module ZeroXDA
  module Market
    module Localization
      class MemoryStore
        def initialize(clock: -> { Time.now.utc })
          @rates = {}
          @mutex = Mutex.new
          upsert_fx_rate(
            FxRate.new(currency: "USDT", usdt_per_unit: 1, updated_at: clock.call)
          )
        end

        def upsert_fx_rate(rate)
          @mutex.synchronize { @rates[rate.currency] = rate }
          rate
        end

        def fx_rate(currency)
          @mutex.synchronize { @rates[currency.to_s] }
        end

        def fx_rates
          @mutex.synchronize { @rates.values.sort_by(&:currency) }
        end
      end
    end
  end
end
