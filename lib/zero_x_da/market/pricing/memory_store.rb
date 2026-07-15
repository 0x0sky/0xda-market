# frozen_string_literal: true

require_relative "price"

module ZeroXDA
  module Market
    module Pricing
      class MemoryStore
        def initialize
          @prices = []
          @mutex = Mutex.new
        end

        def append_price(price)
          @mutex.synchronize { @prices << price }
          price
        end

        def latest_price(sku, before: nil)
          latest_prices(before: before)[sku.to_s]
        end

        # Latest price per sku. Insertion order breaks created_at ties,
        # matching the (created_at DESC, id DESC) ordering in Postgres.
        def latest_prices(before: nil)
          @mutex.synchronize do
            @prices.each_with_object({}) do |price, selected|
              next if before && price.created_at >= before

              selected[price.sku] = price
            end
          end
        end
      end
    end
  end
end
