CREATE TABLE IF NOT EXISTS market.users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  role text NOT NULL DEFAULT 'client'
    CHECK (role IN ('client', 'broker', 'admin')),
  status text NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'blocked')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 0 CHECK (version >= 0)
);

CREATE TABLE IF NOT EXISTS market.user_identities (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES market.users(id) ON DELETE CASCADE,
  provider text NOT NULL,
  provider_user_id text NOT NULL,
  provider_data jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  last_authenticated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 0 CHECK (version >= 0),
  CONSTRAINT user_identities_provider_identity_unique
    UNIQUE (provider, provider_user_id),
  CONSTRAINT user_identities_user_provider_unique
    UNIQUE (user_id, provider)
);

ALTER TABLE market.user_identities
  ADD COLUMN IF NOT EXISTS version bigint NOT NULL DEFAULT 0
  CHECK (version >= 0);

CREATE INDEX IF NOT EXISTS user_identities_user_id_index
  ON market.user_identities(user_id);

CREATE INDEX IF NOT EXISTS users_role_status_index
  ON market.users(role, status);
