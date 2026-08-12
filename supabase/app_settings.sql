-- =====================================================================
--  돌봄(dolbom) — 앱 설정 (브라우저에서 읽어야 하는 값)
--  api_keys 와 구분: 여기 값은 로그인한 직원의 브라우저로 내려갑니다.
--  구글맵 JS 키처럼 원래 클라이언트에 노출되는 키만 넣으세요.
--  (구글맵 키는 Google Cloud에서 'HTTP 리퍼러 제한'을 걸어 보호합니다)
-- =====================================================================
create table if not exists public.app_settings (
  key        text primary key,
  value      text,
  note       text,
  updated_at timestamptz not null default now()
);
alter table public.app_settings enable row level security;

drop policy if exists as_read on public.app_settings;
drop policy if exists as_edit on public.app_settings;
create policy as_read on public.app_settings for select to authenticated
  using (public.my_role() in ('admin','staff','viewer'));
create policy as_edit on public.app_settings for all to authenticated
  using (public.my_role() = 'admin') with check (public.my_role() = 'admin');

insert into public.app_settings (key, value, note) values
  ('google_maps_key', null,
   'Google Cloud → Maps JavaScript API + Geocoding API 사용 설정 후 발급. 반드시 HTTP 리퍼러를 https://dolbomsun.github.io/* 로 제한할 것')
on conflict (key) do nothing;

do $$ begin
  alter publication supabase_realtime add table public.app_settings;
exception when duplicate_object then null;
end $$;
