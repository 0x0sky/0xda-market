# frozen_string_literal: true

require "bigdecimal"
require_relative "locale"

module ZeroXDA
  module Market
    module Localization
      # Currencies are catalog products with marketable: false. A currency's
      # exchange rate is its price: current_price_usdt is the real buy-side
      # rate — how many USDT we pay for one unit of the currency when
      # acquiring the product quantity. Rates are applied through the same
      # pricing flow as any product price.
      class Service
        BASE_CURRENCY = "USDT"
        DEFAULT_LOCALE = "en_US"
        LANGUAGE_LOCALES = {
          "en" => "en_US",
          "uk" => "uk_UA"
        }.freeze
        DISPLAY_SCALE = 2

        def initialize(catalog:)
          @catalog = catalog
        end

        # Unsupported languages fall back to the default instead of failing:
        # the language code comes from Telegram clients and must never break
        # a flow.
        def resolve(language_code: nil, currency: nil)
          locale = locale_for(language_code)
          requested = currency.to_s.strip
          Locale.new(
            code: locale,
            currency: requested.empty? ? currency_for(locale) : requested.upcase
          )
        end

        def locale_for(language_code)
          base = language_code.to_s.downcase[/\A[a-z]{2}/]
          LANGUAGE_LOCALES.fetch(base, DEFAULT_LOCALE)
        end

        # The default currency for a locale, driven by currency product
        # metadata: {"locales": ["uk_UA", "uk_RU"]}.
        def currency_for(locale)
          normalized = locale.to_s
          product = currencies.find do |currency|
            Array(currency.metadata["locales"]).include?(normalized)
          end
          product&.currency_code || BASE_CURRENCY
        end

        def convert(amount_usdt:, currency:)
          normalized = normalize_currency(currency)
          amount = amount_usdt.is_a?(BigDecimal) ? amount_usdt : BigDecimal(amount_usdt.to_s)
          return amount if normalized == BASE_CURRENCY

          rate = rate_for(normalized)
          raise ArgumentError, "currency is not supported: #{normalized}" unless rate

          (amount / rate).round(DISPLAY_SCALE)
        end

        def supported_currency?(currency)
          normalized = normalize_currency(currency)
          normalized == BASE_CURRENCY || !rate_for(normalized).nil?
        end

        def currencies
          @catalog.currencies
        end

        private

        # A currency becomes usable once it has an applied price (= rate).
        def rate_for(code)
          currencies.find do |currency|
            currency.currency_code == code && currency.current_price_usdt
          end&.current_price_usdt
        end

        def normalize_currency(currency)
          value = currency.to_s.strip.upcase
          value.empty? ? BASE_CURRENCY : value
        end
      end
    end
  end
end
