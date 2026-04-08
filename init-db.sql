-- ========================================
--  ИНИЦИАЛИЗАЦИЯ БАЗЫ ДАННЫХ (БЕЗ VECTOR)
-- ========================================

-- Создаём схему core
CREATE SCHEMA IF NOT EXISTS core;
SET search_path = core, public;

-- Устанавливаем только доступные расширения
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS btree_gin;

-- ========================================
--  DOMAINS (ПОЛЬЗОВАТЕЛЬСКИЕ ТИПЫ ДАННЫХ)
-- ========================================

CREATE DOMAIN email_type AS text 
    CHECK (VALUE ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$');

CREATE DOMAIN bin_kz AS varchar(12) 
    CHECK (VALUE ~ '^\d{12}$');

-- ========================================
--  ENUM ТИПЫ
-- ========================================

CREATE TYPE lot_status_enum AS ENUM ('open', 'closed');
CREATE TYPE lot_processing_status_enum AS ENUM ('pending', 'processing', 'completed', 'failed');
CREATE TYPE user_role_enum AS ENUM ('admin', 'manager', 'worker');
CREATE TYPE subscription_status_enum AS ENUM ('active', 'inactive', 'past_due', 'canceled', 'trial');
CREATE TYPE session_type_enum AS ENUM ('web', 'admin', 'api');

-- ========================================
--  СПРАВОЧНИКИ
-- ========================================

CREATE TABLE ref_lot_types (
    id          smallserial PRIMARY KEY,
    code        text NOT NULL UNIQUE,
    name        text NOT NULL
);

CREATE TABLE ref_platforms (
    id          smallserial PRIMARY KEY,
    code        text NOT NULL UNIQUE,
    name        text NOT NULL
);

CREATE TABLE ref_processing_methods (
    id          smallserial PRIMARY KEY,
    code        text NOT NULL UNIQUE,
    name        text NOT NULL
);

-- ========================================
--  ЗАПОЛНЯЕМ СПРАВОЧНИКИ ДАННЫМИ
-- ========================================

-- Заполняем типы лотов
INSERT INTO ref_lot_types (id, code, name) VALUES 
(5, 'service', 'Услуга'),
(6, 'goods', 'Товар'),
(7, 'works', 'Работы')
ON CONFLICT (id) DO UPDATE SET 
    code = EXCLUDED.code,
    name = EXCLUDED.name;

-- Заполняем платформы
INSERT INTO ref_platforms (id, code, name) VALUES 
(1, 'goszakup', 'ГосЗакуп'),
(2, 'sk-zakup', 'SK-Zakup'),
(3, 'mitwork', 'MitWork'),
(4, 'tn1zakup', 'TN1Zakup'),
(5, 'oeskzakup', 'OESKZakup'),
(6, 'stteczakup', 'STTecZakup'),
(7, 'erg', 'ERG')
ON CONFLICT (id) DO UPDATE SET 
    code = EXCLUDED.code,
    name = EXCLUDED.name;

-- Заполняем методы обработки
INSERT INTO ref_processing_methods (code, name) VALUES 
('legacy', 'Устаревший импорт'),
('ml_v2_labse_denoised', 'Извлечение сигнала + гибридный поиск'),
('genius_pipeline', 'Genius Pipeline: Гиперграф + оптимальный транспорт')
ON CONFLICT (code) DO NOTHING;

-- ========================================
--  ФУНКЦИИ
-- ========================================

CREATE OR REPLACE FUNCTION core.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ========================================
--  КОМПАНИИ
-- ========================================

CREATE TABLE companies (
    id                  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    bin                 bin_kz,
    name                text NOT NULL,
    email               email_type,
    phone               text,
    address             text,
    description         text,
    goszakup_number     varchar(64),
    history_prompt      text,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now()
);

CREATE TRIGGER tr_companies_set_updated_at
    BEFORE UPDATE ON companies
    FOR EACH ROW EXECUTE FUNCTION core.set_updated_at();

-- ========================================
--  ПОЛЬЗОВАТЕЛИ
-- ========================================

CREATE TABLE users (
    id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    company_id      bigint REFERENCES companies(id) ON DELETE SET NULL,
    username        text NOT NULL UNIQUE,
    email           email_type UNIQUE,
    password_hash   text NOT NULL,
    role            user_role_enum NOT NULL,
    is_active       boolean NOT NULL DEFAULT true,
    login_count     int NOT NULL DEFAULT 0,
    last_login_at   timestamptz,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_users_company_id ON users(company_id);

-- ========================================
--  ЛОТЫ (TENDERS) - ОСНОВНАЯ ТАБЛИЦА
-- ========================================

CREATE TABLE lots (
    id                  BIGSERIAL PRIMARY KEY,
    external_advert_id  text,
    name                text,
    url                 text,
    lot_number          text,
    
    status              lot_status_enum,
    lot_type            smallint REFERENCES ref_lot_types(id),
    platform_id         smallint REFERENCES ref_platforms(id),
    
    organizer_name      text,
    
    publish_date        timestamptz,
    start_date          timestamptz,
    end_date            timestamptz,
    
    price               numeric(18,2),
    currency_code       char(3) DEFAULT 'KZT',
    tech_description_parsed boolean NOT NULL DEFAULT false,
    is_ml_processed     boolean NOT NULL DEFAULT false,
    address             text,
    download_url        text,
    created_at          timestamptz NOT NULL DEFAULT now(),
    source_row_num      bigint
);

-- Индексы для поиска
CREATE INDEX idx_lots_publish_date ON lots (publish_date DESC);
CREATE INDEX idx_lots_platform_id ON lots (platform_id);
CREATE INDEX idx_lots_lot_type ON lots (lot_type);

-- ========================================
--  ТЕХНИЧЕСКИЕ ОПИСАНИЯ ЛОТОВ (БЕЗ VECTOR)
-- ========================================

CREATE TABLE lot_tech_descriptions (
    id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    lot_id          bigint NOT NULL REFERENCES lots(id) ON DELETE CASCADE UNIQUE,
    
    raw_content     text,
    tables_content  text,
    processed_text  text,
    lemmatized_text text,
    
    -- Полнотекстовый поиск
    tsv_processed tsvector,
    tsv_lemmatized tsvector,
    
    -- Genius Pipeline
    semantic_atoms JSONB,
    semantic_graph JSONB
);

-- GIN индекс для полнотекстового поиска
CREATE INDEX idx_lot_tsv_gin ON lot_tech_descriptions USING GIN (tsv_processed);

-- ========================================
--  СООТВЕТСТВИЯ КОМПАНИЙ И ЛОТОВ
-- ========================================

CREATE TABLE company_relevant_lots (
    id                  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    company_id          bigint NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    lot_id              bigint NOT NULL REFERENCES lots(id) ON DELETE CASCADE,
    
    processing_method_id smallint REFERENCES ref_processing_methods(id),
    
    score               float not null,
    feedback            boolean DEFAULT NULL,
    is_synthetic        boolean DEFAULT false,
    
    confidence_level    FLOAT DEFAULT 0.5,
    match_explanation   TEXT,

    created_at          timestamptz NOT NULL DEFAULT now(),

    UNIQUE(company_id, lot_id)
);

-- Индекс для быстрого поиска соответствий компании
CREATE INDEX idx_relevant_lots_company_created 
ON company_relevant_lots (company_id, created_at DESC);

-- ========================================
--  КАНБАН
-- ========================================

CREATE TABLE kanban_columns (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    company_id  bigint NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    name        text NOT NULL,
    color       text NOT NULL DEFAULT '#cccccc',
    position    int NOT NULL DEFAULT 0,
    is_system   boolean NOT NULL DEFAULT false,
    created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE kanban_cards (
    id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    company_id      bigint NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    lot_id          bigint NOT NULL REFERENCES lots(id) ON DELETE CASCADE,
    column_id       bigint NOT NULL REFERENCES kanban_columns(id) ON DELETE CASCADE,
    assigned_user_id bigint REFERENCES users(id) ON DELETE SET NULL,
    position        int NOT NULL DEFAULT 0,
    note            text NOT NULL DEFAULT '',
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    UNIQUE(company_id, lot_id)
);

CREATE TRIGGER tr_kanban_cards_set_updated_at
    BEFORE UPDATE ON kanban_cards
    FOR EACH ROW EXECUTE FUNCTION core.set_updated_at();

-- ========================================
--  ЗАВЕРШЕНИЕ И ПРОВЕРКА
-- ========================================

-- Проверяем что справочники созданы
SELECT 'Справочник типов лотов:' as info;
SELECT id, code, name FROM core.ref_lot_types ORDER BY id;

SELECT 'Справочник платформ:' as info;
SELECT id, code, name FROM core.ref_platforms ORDER BY id;

SELECT 'Справочник методов обработки:' as info;
SELECT id, code, name FROM core.ref_processing_methods ORDER BY id;

-- Проверяем структуру таблицы lots
SELECT 'Колонки таблицы lots:' as info;
SELECT 
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns 
WHERE table_schema = 'core' 
  AND table_name = 'lots'
ORDER BY ordinal_position;

SELECT 'База данных успешно инициализирована!' as message;