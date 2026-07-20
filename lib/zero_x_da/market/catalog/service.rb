# frozen_string_literal: true

require_relative "../core/contracts"
require_relative "product"

module ZeroXDA
  module Market
    module Catalog
      class Service
        DEFAULT_LOCALE = "en_US"

        def initialize(store:)
          @store = store
        end

        # The sellable catalog: currencies (marketable: false) are excluded.
        def products(locale: DEFAULT_LOCALE)
          @store.list_products(status: "active", locale: locale, marketable: true)
        end

        # Currency products; their current price is the exchange rate.
        def currencies(locale: DEFAULT_LOCALE)
          @store.list_products(status: "active", locale: locale, marketable: false)
        end

        # Resolves any product, marketable or not, so pricing flows
        # (/apply_price uah 41.50) work for currencies too.
        def find_product(sku, locale: DEFAULT_LOCALE)
          @store.find_product(sku.to_s, locale: locale) || raise(Core::NotFound.new("product", sku))
        end
      end
    end
  end
end
