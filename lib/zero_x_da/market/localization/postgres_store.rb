# frozen_string_literal: true

require "bigdecimal"
require "sequel"
require_relative "fx_rate"

module ZeroXDA
  module Market
    module Localization
      class PostgresStore
        def initialize(database:)
          @rates = database.connection[Sequel.qualify(:market, :fx_rates)]
        end

        def upsert_fx_rate(rate)
          @rates
            .insert_conflict(
              target: :currency,
              update: {
                usdt_per_unit: Sequel[:excluded][:usdt_per_unit],
                updated_at: Sequel[:excluded][:updated_at]
              }
            )
            .insert(
              currency: rate.currency,
              usdt_per_unit: rate.usdt_per_unit,
              updated_at: rate.updated_at
            )
          rate
        end

        def fx_rate(currency)
          row = @rates.where(currency: currency.to_s).first
          row && deserialize(row)
        end

        def fx_rates
          @rates.order(:currency).all.map { |row| deserialize(row) }
        end

        private

        def deserialize(row)
          FxRate.new(
            currency: row.fetch(:currency),
            usdt_per_unit: BigDecimal(row.fetch(:usdt_per_unit).to_s),
            updated_at: row.fetch(:updated_at)
          )
        end
      end
    end
  end
end
