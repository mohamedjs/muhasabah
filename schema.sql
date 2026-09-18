-- ====================================================================
-- مُحاسبة (Muhasabah) - Database Schema
-- Supabase / PostgreSQL DDL with Row Level Security (RLS)
-- ====================================================================

-- 1. ENUMS & EXTENSIONS
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

DO $$ BEGIN
  CREATE TYPE prayer_type AS ENUM ('fajr', 'dhuhr', 'asr', 'maghrib', 'isha', 'duha', 'qiyam');
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
  CREATE TYPE prayer_calculation_method AS ENUM (
    'egyptian', 'makkah', 'karachi', 'isna', 'mwl', 'dubai', 'qatar'
  );
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

-- 2. USER PROFILES
CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name TEXT,
  avatar_url TEXT,
  timezone TEXT NOT NULL DEFAULT 'Asia/Riyadh',
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  calculation_method prayer_calculation_method NOT NULL DEFAULT 'makkah',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 3. DAILY LOGS (Master record for each day: Musharatah & Day Stats)
CREATE TABLE IF NOT EXISTS public.daily_logs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  log_date DATE NOT NULL,
  
  -- Musharatah (المشارطة الصباحية)
  morning_intention TEXT,
  avoid_slip TEXT,
  is_musharatah_completed BOOLEAN NOT NULL DEFAULT FALSE,
  
  -- Nightly Muhasabah (المحاسبة المسائية وتخلية القلب)
  audit_tongue_purity BOOLEAN DEFAULT NULL,     -- حفظ اللسان (الغيبة/اللغو)
  audit_gaze_senses BOOLEAN DEFAULT NULL,       -- غض البصر وحفظ الجوارح
  audit_duty_integrity BOOLEAN DEFAULT NULL,    -- أداء الأمانة والإتقان
  audit_heart_forgiveness BOOLEAN DEFAULT NULL, -- سلامة الصدر والعفو
  audit_notes TEXT,
  is_istighfar_completed BOOLEAN NOT NULL DEFAULT FALSE,
  is_muhasabah_completed BOOLEAN NOT NULL DEFAULT FALSE,
  
  -- Metadata & Score
  completion_score SMALLINT NOT NULL DEFAULT 0 CHECK (completion_score BETWEEN 0 AND 100),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  CONSTRAINT unique_user_daily_log UNIQUE (user_id, log_date)
);

-- 4. PRAYER LOGS (الأوراد والصلوات الخمس والسنن)
CREATE TABLE IF NOT EXISTS public.prayer_logs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  daily_log_id UUID NOT NULL REFERENCES public.daily_logs(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  prayer_name prayer_type NOT NULL,
  is_prayed BOOLEAN NOT NULL DEFAULT FALSE,
  is_on_time BOOLEAN NOT NULL DEFAULT FALSE,
  is_in_congregation BOOLEAN NOT NULL DEFAULT FALSE,
  has_sunnah_rawatib BOOLEAN NOT NULL DEFAULT FALSE,
  has_adhkar BOOLEAN NOT NULL DEFAULT FALSE,
  logged_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT unique_daily_prayer UNIQUE (daily_log_id, prayer_name)
);

-- 5. QURAN & REFLECTIONS (القرآن والتدبر)
CREATE TABLE IF NOT EXISTS public.quran_reflections (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  daily_log_id UUID NOT NULL REFERENCES public.daily_logs(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  pages_read SMALLINT NOT NULL DEFAULT 0 CHECK (pages_read >= 0),
  juz_number SMALLINT CHECK (juz_number BETWEEN 1 AND 30),
  verse_key TEXT,
  reflection_note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 6. ADHKAR SESSIONS (أذكار الصباح/المساء/النوم مع السبحة)
CREATE TABLE IF NOT EXISTS public.adhkar_logs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  daily_log_id UUID NOT NULL REFERENCES public.daily_logs(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  dhikr_type TEXT NOT NULL CHECK (dhikr_type IN ('morning', 'evening', 'sleep', 'free')),
  total_counter INT NOT NULL DEFAULT 0,
  is_completed BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 7. NOTIFICATION SETTINGS (إعدادات التنبيهات الموقوتة)
CREATE TABLE IF NOT EXISTS public.notification_settings (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID UNIQUE NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  fajr_offset_minutes SMALLINT NOT NULL DEFAULT 15,
  duha_time TIME NOT NULL DEFAULT '08:30:00',
  evening_adhkar_offset_minutes SMALLINT NOT NULL DEFAULT -30,
  bedtime TIME NOT NULL DEFAULT '22:30:00',
  push_token TEXT,
  is_local_notifications_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 8. INDEXES & PERFORMANCE
CREATE INDEX IF NOT EXISTS idx_daily_logs_user_date ON public.daily_logs (user_id, log_date DESC);
CREATE INDEX IF NOT EXISTS idx_prayer_logs_daily_log ON public.prayer_logs (daily_log_id);
CREATE INDEX IF NOT EXISTS idx_reflections_daily_log ON public.quran_reflections (daily_log_id);

-- 9. ROW LEVEL SECURITY (RLS)
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.daily_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prayer_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quran_reflections ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.adhkar_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_settings ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE
  tbl TEXT;
BEGIN
  FOR tbl IN SELECT tablename FROM pg_tables WHERE schemaname = 'public'
  LOOP
    EXECUTE format('
      DROP POLICY IF EXISTS user_isolation_policy ON public.%I;
      CREATE POLICY user_isolation_policy ON public.%I
      FOR ALL USING (auth.uid() = user_id OR auth.uid() = id);
    ', tbl, tbl);
  END LOOP;
END $$;
