# frozen_string_literal: true

module ZeroXDA
  module Market
    module Localization
      class Locale
        CODE_PATTERN = /\A[a-z]{2}_[A-Z]{2}\z/
        CURRENCY_PATTERN = /\A[A-Z][A-Z0-9]{2,9}\z/

        attr_reader :code, :currency

        def initialize(code:, currency:)
          raise ArgumentError, "locale code is invalid" unless CODE_PATTERN.match?(code.to_s)
          raise ArgumentError, "currency code is invalid" unless CURRENCY_PATTERN.match?(currency.to_s)

          @code = code.to_s.freeze
          @currency = currency.to_s.freeze
          freeze
        end
      end
    end
  end
end
