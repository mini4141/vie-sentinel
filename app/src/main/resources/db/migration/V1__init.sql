CREATE TABLE events (
    id              uuid PRIMARY KEY,
    idempotency_key text        NOT NULL UNIQUE,
    user_id         text        NOT NULL,
    device_id       text        NOT NULL,
    ip              text        NOT NULL,
    type            text        NOT NULL,
    amount          numeric,
    play_seconds    int,
    occurred_at     timestamptz NOT NULL,
    decision        text        NOT NULL,
    score           int         NOT NULL,
    reasons         jsonb       NOT NULL DEFAULT '[]'::jsonb,
    created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_events_user_occurred ON events (user_id, occurred_at);
CREATE INDEX idx_events_device ON events (device_id);

CREATE TABLE rules (
    id         text PRIMARY KEY,
    enabled    boolean     NOT NULL DEFAULT true,
    shadow     boolean     NOT NULL DEFAULT false,
    params     jsonb       NOT NULL DEFAULT '{}'::jsonb,
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE cases (
    id          uuid PRIMARY KEY,
    event_id    uuid        NOT NULL REFERENCES events (id),
    status      text        NOT NULL DEFAULT 'OPEN',
    created_at  timestamptz NOT NULL DEFAULT now(),
    resolved_at timestamptz
);
CREATE INDEX idx_cases_status ON cases (status);

CREATE TABLE rule_audit (
    id         bigserial PRIMARY KEY,
    rule_id    text        NOT NULL,
    changed_by text        NOT NULL,
    change     jsonb       NOT NULL,
    at         timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE alerts (
    id         bigserial PRIMARY KEY,
    event_id   uuid        NOT NULL UNIQUE,
    decision   text        NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO rules (id, enabled, shadow, params) VALUES
    ('velocity', true, false, '{"maxEvents": 5, "windowSeconds": 60}'),
    ('device_sharing', true, false, '{"maxUsers": 3}'),
    ('fast_completion', true, false, '{"minSeconds": 10}');
