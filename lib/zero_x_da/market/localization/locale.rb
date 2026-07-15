# frozen_string_literal: true

require_relative "fx_rate"

module ZeroXDA
  module Market
    module Localization
      class Locale
        # Only English is supported for now; the list is here so that adding
        # a language is a data change, not a structural one.
        LANGUAGES = %w[en].freeze

        attr_reader :language, :currency

        def initialize(language:, currency:)
          unless LANGUAGES.include?(language)
            raise ArgumentError, "language is not supported"
          end
          unless FxRate::CURRENCY_PATTERN.match?(currency.to_s)
            raise ArgumentError, "currency code is invalid"
          end

          @language = language.dup.freeze
          @currency = currency.to_s.freeze
          freeze
        end
      end
    end
  end
end
