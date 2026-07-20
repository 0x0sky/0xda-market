-- Currencies become catalog products with marketable = false.
-- A currency's exchange rate is its price in product_prices: amount_usdt
-- is the buy-side rate (how many USDT we pay for one unit of the currency
-- when acquiring the product quantity). The fx_rates table is superseded.

ALTER TABLE market.products
  ADD COLUMN marketable boolean NOT NULL DEFAULT true;

INSERT INTO market.products (sku, short_name, metadata, status, position, marketable)
VALUES
  ('usdt', 'USDT', '{"family": "currency", "code": "USDT", "symbol": "₮", "scale": 2, "base": true}'::jsonb, 'active', 100, false),
  ('usd', 'USD', '{"family": "currency", "code": "USD", "symbol": "$", "scale": 2, "locales": ["en_US"]}'::jsonb, 'active', 101, false),
  ('uah', 'UAH', '{"family": "currency", "code": "UAH", "symbol": "₴", "scale": 2, "locales": ["uk_UA", "uk_RU"]}'::jsonb, 'active', 102, false),
  ('rub', 'RUB', '{"family": "currency", "code": "RUB", "symbol": "₽", "scale": 2, "locales": ["ru_RU", "ru_UA"]}'::jsonb, 'active', 103, false);

INSERT INTO market.product_localizations (product_sku, locale, full_name, button_label, created_at, updated_at, version)
VALUES
  ('usdt', 'en_US', 'Tether USD', 'USDT', now(), now(), 0),
  ('usdt', 'uk_UA', 'Tether USD', 'USDT', now(), now(), 0),
  ('usd', 'en_US', 'US Dollar', 'USD', now(), now(), 0),
  ('usd', 'uk_UA', 'Долар США', 'USD', now(), now(), 0),
  ('uah', 'en_US', 'Ukrainian Hryvnia', 'UAH', now(), now(), 0),
  ('uah', 'uk_UA', 'Українська гривня', 'UAH', now(), now(), 0),
  ('rub', 'en_US', 'Russian Ruble', 'RUB', now(), now(), 0),
  ('rub', 'uk_UA', 'Російський рубль', 'RUB', now(), now(), 0);

-- The base currency's rate is fixed at 1 USDT per unit. The insert trigger
-- (product_prices_sync_current_price, added in 007) denormalizes it onto
-- the product row automatically — no manual UPDATE needed here.
INSERT INTO market.product_prices (sku, amount_usdt, source)
VALUES ('usdt', 1, 'core');

DROP TABLE market.fx_rates;
