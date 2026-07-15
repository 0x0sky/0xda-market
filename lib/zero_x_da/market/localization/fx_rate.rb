# frozen_string_literal: true

require "bigdecimal"
require_relative "../core/records"

module ZeroXDA
  module Market
    module Localization
      # Buy-side exchange rate: how many USDT we pay for one unit of the
      # currency when acquiring the product quantity on the real market.
      class FxRate
        CURRENCY_PATTERN = /\A[A-Z][A-Z0-9]{2,9}\z/

        attr_reader :currency, :usdt_per_unit, :updated_at

        def initialize(currency:, usdt_per_unit:, updated_at:)
          normalized = currency.to_s
          unless CURRENCY_PATTERN.match?(normalized)
            raise ArgumentError, "currency code is invalid"
          end

          @currency = normalized.freeze
          @usdt_per_unit = decimal(usdt_per_unit)
          @updated_at = Core::RecordSupport.time(updated_at, field: "updated_at")
          freeze
        end

        private

        def decimal(value)
          amount = value.is_a?(BigDecimal) ? value : BigDecimal(value.to_s)
          unless amount.finite? && amount.positive?
            raise ArgumentError, "usdt_per_unit must be positive"
          end

          amount
        rescue ArgumentError
          raise ArgumentError, "usdt_per_unit must be a number"
        end
      end
    end
  end
end
