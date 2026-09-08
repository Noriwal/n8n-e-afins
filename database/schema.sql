-- APOD Instagram Automation V2
-- PostgreSQL 15+
-- Fundação revisada: callback curto, transições atômicas, auditoria e tentativas de publicação.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$ BEGIN
    CREATE TYPE apod_draft_status AS ENUM (
        'COLLECTED',
        'PROCESSING',
        'READY_FOR_APPROVAL',
        'APPROVED',
        'PUBLISHING',
        'PUBLISHED',
        'REJECTED',
        'EXPIRED',
        'UNSUPPORTED',
        'ERROR',
        'PUBLISH_ERROR'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    CREATE TYPE apod_validation_status AS ENUM (
        'PENDING',
        'VALID',
        'NOT_SUPPORTED',
        'ERROR'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS apod_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    apod_date DATE NOT NULL UNIQUE,
    title TEXT NOT NULL,
    description_original TEXT,
    copyright TEXT,
    nasa_media_type TEXT NOT NULL,
    media_url TEXT,
    hd_url TEXT,
    thumbnail_url TEXT,
    source_url TEXT,
    external_id TEXT,
    raw_payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS drafts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    apod_item_id UUID NOT NULL UNIQUE REFERENCES apod_items(id) ON DELETE RESTRICT,

    approval_key TEXT NOT NULL UNIQUE,
    status apod_draft_status NOT NULL DEFAULT 'COLLECTED',

    title TEXT NOT NULL,
    description_pt TEXT,
    caption TEXT,

    media_type TEXT NOT NULL,
    media_url TEXT,
    preview_url TEXT,
    source_url TEXT,

    validation_status apod_validation_status NOT NULL DEFAULT 'PENDING',
    validation_message TEXT,

    telegram_chat_id BIGINT,
    telegram_message_id BIGINT,
    telegram_preview_message_id BIGINT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ,

    approved_at TIMESTAMPTZ,
    approved_by_telegram_user_id BIGINT,

    rejected_at TIMESTAMPTZ,
    rejected_by_telegram_user_id BIGINT,

    published_at TIMESTAMPTZ,
    instagram_media_id TEXT,

    last_error_code TEXT,
    last_error_message TEXT,

    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_drafts_instagram_media_id
    ON drafts(instagram_media_id)
    WHERE instagram_media_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_drafts_status ON drafts(status);
CREATE INDEX IF NOT EXISTS idx_drafts_expires_at
    ON drafts(expires_at)
    WHERE status = 'READY_FOR_APPROVAL';

CREATE TABLE IF NOT EXISTS workflow_events (
    id BIGSERIAL PRIMARY KEY,
    draft_id UUID REFERENCES drafts(id) ON DELETE CASCADE,
    event_type TEXT NOT NULL,
    event_data JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_workflow_events_draft
    ON workflow_events(draft_id, created_at DESC);

CREATE TABLE IF NOT EXISTS publication_attempts (
    id BIGSERIAL PRIMARY KEY,
    draft_id UUID NOT NULL REFERENCES drafts(id) ON DELETE CASCADE,
    attempt_number INTEGER NOT NULL,
    status TEXT NOT NULL,
    instagram_container_id TEXT,
    instagram_media_id TEXT,
    request_payload JSONB,
    response_payload JSONB,
    http_status INTEGER,
    error_code TEXT,
    error_message TEXT,
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    finished_at TIMESTAMPTZ,
    UNIQUE (draft_id, attempt_number)
);

CREATE INDEX IF NOT EXISTS idx_publication_attempts_draft
    ON publication_attempts(draft_id, attempt_number DESC);

CREATE TABLE IF NOT EXISTS app_settings (
    key TEXT PRIMARY KEY,
    value_json JSONB NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_apod_items_updated_at ON apod_items;
CREATE TRIGGER trg_apod_items_updated_at
BEFORE UPDATE ON apod_items
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_drafts_updated_at ON drafts;
CREATE TRIGGER trg_drafts_updated_at
BEFORE UPDATE ON drafts
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE OR REPLACE FUNCTION generate_approval_key()
RETURNS TEXT
LANGUAGE sql
AS $$
    SELECT encode(gen_random_bytes(12), 'hex');
$$;

CREATE OR REPLACE FUNCTION ingest_apod_draft(p JSONB)
RETURNS TABLE (
    draft_id UUID,
    approval_key TEXT,
    status apod_draft_status,
    caption TEXT,
    media_type TEXT,
    media_url TEXT,
    preview_url TEXT,
    expires_at TIMESTAMPTZ,
    is_new_draft BOOLEAN
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_apod_id UUID;
    v_existing UUID;
    v_draft_id UUID;
    v_key TEXT;
    v_status apod_draft_status;
    v_is_new BOOLEAN := FALSE;
BEGIN
    INSERT INTO apod_items (
        apod_date, title, description_original, copyright,
        nasa_media_type, media_url, hd_url, thumbnail_url,
        source_url, external_id, raw_payload
    )
    VALUES (
        (p->>'apod_date')::date,
        COALESCE(p->>'title', ''),
        p->>'description_original',
        p->>'copyright',
        COALESCE(p->>'nasa_media_type', 'other'),
        NULLIF(p->>'media_url',''),
        NULLIF(p->>'hd_url',''),
        NULLIF(p->>'thumbnail_url',''),
        NULLIF(p->>'source_url',''),
        NULLIF(p->>'external_id',''),
        COALESCE(p->'raw_payload', '{}'::jsonb)
    )
    ON CONFLICT (apod_date) DO UPDATE SET
        title = EXCLUDED.title,
        description_original = EXCLUDED.description_original,
        copyright = EXCLUDED.copyright,
        nasa_media_type = EXCLUDED.nasa_media_type,
        media_url = EXCLUDED.media_url,
        hd_url = EXCLUDED.hd_url,
        thumbnail_url = EXCLUDED.thumbnail_url,
        source_url = EXCLUDED.source_url,
        external_id = EXCLUDED.external_id,
        raw_payload = EXCLUDED.raw_payload
    RETURNING id INTO v_apod_id;

    SELECT d.id INTO v_existing
    FROM drafts d
    WHERE d.apod_item_id = v_apod_id;

    IF v_existing IS NULL THEN
        v_key := generate_approval_key();
        v_status := CASE
            WHEN COALESCE(p->>'validation_status','ERROR') = 'VALID'
                THEN 'READY_FOR_APPROVAL'::apod_draft_status
            WHEN COALESCE(p->>'validation_status','ERROR') = 'NOT_SUPPORTED'
                THEN 'UNSUPPORTED'::apod_draft_status
            ELSE 'ERROR'::apod_draft_status
        END;

        INSERT INTO drafts (
            apod_item_id, approval_key, status, title, description_pt,
            caption, media_type, media_url, preview_url, source_url,
            validation_status, validation_message, expires_at
        )
        VALUES (
            v_apod_id, v_key, v_status, COALESCE(p->>'title',''),
            p->>'description_pt', p->>'caption',
            COALESCE(p->>'media_type','blocked'),
            NULLIF(p->>'media_url',''),
            NULLIF(p->>'preview_url',''),
            NULLIF(p->>'source_url',''),
            COALESCE(p->>'validation_status','ERROR')::apod_validation_status,
            p->>'validation_message',
            CASE WHEN v_status = 'READY_FOR_APPROVAL'
                THEN now() + make_interval(hours => COALESCE((p->>'approval_ttl_hours')::int, 6))
                ELSE NULL
            END
        )
        RETURNING id INTO v_draft_id;

        v_is_new := TRUE;

        INSERT INTO workflow_events (draft_id, event_type, event_data)
        VALUES (v_draft_id, 'DRAFT_CREATED', jsonb_build_object('status', v_status, 'apod_date', p->>'apod_date'));
    ELSE
        v_draft_id := v_existing;
    END IF;

    RETURN QUERY
    SELECT d.id, d.approval_key, d.status, d.caption, d.media_type,
           d.media_url, d.preview_url, d.expires_at, v_is_new
    FROM drafts d
    WHERE d.id = v_draft_id;
END;
$$;

CREATE OR REPLACE FUNCTION register_telegram_message(p JSONB)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE drafts
    SET telegram_chat_id = (p->>'chat_id')::bigint,
        telegram_message_id = NULLIF(p->>'message_id','')::bigint,
        telegram_preview_message_id = NULLIF(p->>'preview_message_id','')::bigint
    WHERE id = (p->>'draft_id')::uuid;

    INSERT INTO workflow_events (draft_id, event_type, event_data)
    VALUES (
        (p->>'draft_id')::uuid,
        'TELEGRAM_SENT',
        jsonb_build_object('chat_id', p->>'chat_id', 'message_id', p->>'message_id', 'preview_message_id', p->>'preview_message_id')
    );
END;
$$;

CREATE OR REPLACE FUNCTION expire_old_drafts()
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_count INTEGER;
BEGIN
    WITH expired AS (
        UPDATE drafts
        SET status = 'EXPIRED',
            last_error_code = 'APPROVAL_EXPIRED',
            last_error_message = 'Prazo de aprovação expirado'
        WHERE status = 'READY_FOR_APPROVAL'
          AND expires_at IS NOT NULL
          AND expires_at < now()
        RETURNING id, expires_at
    ),
    logged AS (
        INSERT INTO workflow_events (draft_id, event_type, event_data)
        SELECT id, 'DRAFT_EXPIRED', jsonb_build_object('expires_at', expires_at)
        FROM expired
        RETURNING 1
    )
    SELECT count(*) INTO v_count FROM logged;
    RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION process_approval_callback(p JSONB)
RETURNS TABLE (
    ok BOOLEAN,
    result_code TEXT,
    draft_id UUID,
    new_status apod_draft_status,
    media_type TEXT,
    media_url TEXT,
    caption TEXT,
    telegram_chat_id BIGINT,
    telegram_message_id BIGINT
)
LANGUAGE plpgsql
AS $$
DECLARE
    d drafts%ROWTYPE;
    v_action TEXT := p->>'action';
    v_key TEXT := p->>'approval_key';
    v_user BIGINT := (p->>'telegram_user_id')::bigint;
    v_chat BIGINT := (p->>'telegram_chat_id')::bigint;
    v_message BIGINT := NULLIF(p->>'telegram_message_id','')::bigint;
BEGIN
    SELECT * INTO d FROM drafts WHERE approval_key = v_key FOR UPDATE;

    IF NOT FOUND THEN
        RETURN QUERY SELECT FALSE, 'DRAFT_NOT_FOUND', NULL::uuid, NULL::apod_draft_status,
            NULL::text, NULL::text, NULL::text, NULL::bigint, NULL::bigint;
        RETURN;
    END IF;

    IF d.telegram_chat_id IS NOT NULL AND d.telegram_chat_id <> v_chat THEN
        RETURN QUERY SELECT FALSE, 'CHAT_MISMATCH', d.id, d.status,
            d.media_type, d.media_url, d.caption, d.telegram_chat_id, d.telegram_message_id;
        RETURN;
    END IF;

    IF d.telegram_message_id IS NOT NULL AND v_message IS NOT NULL AND d.telegram_message_id <> v_message THEN
        RETURN QUERY SELECT FALSE, 'MESSAGE_MISMATCH', d.id, d.status,
            d.media_type, d.media_url, d.caption, d.telegram_chat_id, d.telegram_message_id;
        RETURN;
    END IF;

    IF d.status = 'READY_FOR_APPROVAL' AND d.expires_at IS NOT NULL AND d.expires_at < now() THEN
        UPDATE drafts
        SET status = 'EXPIRED', last_error_code = 'APPROVAL_EXPIRED',
            last_error_message = 'Prazo de aprovação expirado'
        WHERE id = d.id;

        INSERT INTO workflow_events (draft_id, event_type, event_data)
        VALUES (d.id, 'DRAFT_EXPIRED', jsonb_build_object('expires_at', d.expires_at));

        RETURN QUERY SELECT FALSE, 'EXPIRED', d.id, 'EXPIRED'::apod_draft_status,
            d.media_type, d.media_url, d.caption, d.telegram_chat_id, d.telegram_message_id;
        RETURN;
    END IF;

    IF d.status <> 'READY_FOR_APPROVAL' THEN
        RETURN QUERY SELECT FALSE, 'ALREADY_PROCESSED', d.id, d.status,
            d.media_type, d.media_url, d.caption, d.telegram_chat_id, d.telegram_message_id;
        RETURN;
    END IF;

    IF v_action = 'approve' THEN
        UPDATE drafts
        SET status = 'APPROVED', approved_at = now(), approved_by_telegram_user_id = v_user
        WHERE id = d.id;

        INSERT INTO workflow_events (draft_id, event_type, event_data)
        VALUES (d.id, 'APPROVAL_RECEIVED', jsonb_build_object('telegram_user_id', v_user));

        RETURN QUERY SELECT TRUE, 'APPROVED', d.id, 'APPROVED'::apod_draft_status,
            d.media_type, d.media_url, d.caption, d.telegram_chat_id, d.telegram_message_id;
        RETURN;

    ELSIF v_action = 'reject' THEN
        UPDATE drafts
        SET status = 'REJECTED', rejected_at = now(), rejected_by_telegram_user_id = v_user
        WHERE id = d.id;

        INSERT INTO workflow_events (draft_id, event_type, event_data)
        VALUES (d.id, 'APPROVAL_REJECTED', jsonb_build_object('telegram_user_id', v_user));

        RETURN QUERY SELECT TRUE, 'REJECTED', d.id, 'REJECTED'::apod_draft_status,
            d.media_type, d.media_url, d.caption, d.telegram_chat_id, d.telegram_message_id;
        RETURN;
    END IF;

    RETURN QUERY SELECT FALSE, 'INVALID_ACTION', d.id, d.status,
        d.media_type, d.media_url, d.caption, d.telegram_chat_id, d.telegram_message_id;
END;
$$;

CREATE OR REPLACE FUNCTION reserve_publication(p_draft_id UUID)
RETURNS TABLE (
    ok BOOLEAN,
    result_code TEXT,
    draft_id UUID,
    attempt_number INTEGER,
    media_type TEXT,
    media_url TEXT,
    caption TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    d drafts%ROWTYPE;
    v_attempt INTEGER;
BEGIN
    SELECT * INTO d FROM drafts WHERE id = p_draft_id FOR UPDATE;

    IF NOT FOUND THEN
        RETURN QUERY SELECT FALSE, 'DRAFT_NOT_FOUND', NULL::uuid, NULL::int, NULL::text, NULL::text, NULL::text;
        RETURN;
    END IF;

    IF d.status = 'PUBLISHED' THEN
        RETURN QUERY SELECT FALSE, 'ALREADY_PUBLISHED', d.id, NULL::int, d.media_type, d.media_url, d.caption;
        RETURN;
    END IF;

    IF d.status <> 'APPROVED' AND d.status <> 'PUBLISH_ERROR' THEN
        RETURN QUERY SELECT FALSE, 'INVALID_STATE', d.id, NULL::int, d.media_type, d.media_url, d.caption;
        RETURN;
    END IF;

    SELECT COALESCE(MAX(attempt_number), 0) + 1 INTO v_attempt
    FROM publication_attempts WHERE draft_id = d.id;

    UPDATE drafts
    SET status = 'PUBLISHING', last_error_code = NULL, last_error_message = NULL
    WHERE id = d.id;

    INSERT INTO publication_attempts (draft_id, attempt_number, status)
    VALUES (d.id, v_attempt, 'STARTED');

    INSERT INTO workflow_events (draft_id, event_type, event_data)
    VALUES (d.id, 'PUBLISH_STARTED', jsonb_build_object('attempt_number', v_attempt));

    RETURN QUERY SELECT TRUE, 'RESERVED', d.id, v_attempt, d.media_type, d.media_url, d.caption;
END;
$$;
