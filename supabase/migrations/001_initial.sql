-- Run this SQL in your Supabase project's SQL editor (Dashboard → SQL Editor)
-- It creates the necessary tables + Row Level Security policies.

-- 1. Profiles table (public metadata for each user)
CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name TEXT,
  avatar_url TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own profile"
  ON public.profiles FOR SELECT
  USING (auth.uid() = id);

CREATE POLICY "Users can update own profile"
  ON public.profiles FOR UPDATE
  USING (auth.uid() = id);

CREATE POLICY "Users can insert own profile"
  ON public.profiles FOR INSERT
  WITH CHECK (auth.uid() = id);

-- Auto-create profile on signup via trigger
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, display_name)
  VALUES (NEW.id, NEW.raw_user_meta_data->>'display_name');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- 2. Scans sync table
CREATE TABLE IF NOT EXISTS public.scans (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  local_id INTEGER,
  scanned_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  labels JSONB NOT NULL DEFAULT '[]',
  total_calories REAL,
  total_protein_g REAL,
  total_carbs_g REAL,
  total_fat_g REAL,
  raw_payload JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.scans ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can CRUD own scans"
  ON public.scans FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE INDEX idx_scans_user_date ON public.scans(user_id, scanned_at DESC);

-- 3. Account deletion RPC (called from app)
CREATE OR REPLACE FUNCTION public.delete_user()
RETURNS VOID AS $$
BEGIN
  -- Delete profile (cascades from auth.users)
  DELETE FROM auth.users WHERE id = auth.uid();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
