-- =====================================================================
--  HomeDenti · 방문치과 통합관리 플랫폼 — Supabase 스키마
--  실행 방법: Supabase 대시보드 → SQL Editor → 이 파일 전체 붙여넣기 → Run
--  (한 번만 실행하면 됩니다. 재실행해도 안전하도록 IF NOT EXISTS 처리)
-- =====================================================================

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------
-- 1. 권한 (로그인 계정)
-- ---------------------------------------------------------------------
create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  name        text not null default '이름 미설정',
  app_role    text not null default 'viewer'
              check (app_role in ('admin','staff','viewer')),
  staff_id    uuid,
  created_at  timestamptz not null default now()
);
comment on column public.profiles.app_role is
  'admin=전체 관리(원장) / staff=입력·수정 가능(협력의·위생사·코디네이터) / viewer=조회만';

-- 회원가입 시 profiles 행 자동 생성
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, name)
  values (new.id, coalesce(new.raw_user_meta_data->>'name', split_part(new.email,'@',1)))
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- 현재 로그인 사용자의 권한을 반환 (RLS에서 사용)
create or replace function public.my_role()
returns text language sql stable security definer set search_path = public as $$
  select coalesce((select app_role from public.profiles where id = auth.uid()), 'none')
$$;

-- ---------------------------------------------------------------------
-- 2. 참여 의료진 (로그인 계정과 별개 — 로그인하지 않는 인력도 등록)
-- ---------------------------------------------------------------------
create table if not exists public.staff (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  clinic     text default '태양치과',
  role       text not null default '협력의'
             check (role in ('원장','협력의','치과위생사','치과기공사','코디네이터')),
  regions    text[] not null default '{}',
  slots      text,
  tel        text,
  license_no text,
  unit_fee   integer default 180000,   -- 건당 정산 단가
  active     boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 3. 접수 · 상담 (인바운드)
-- ---------------------------------------------------------------------
create table if not exists public.intakes (
  id          uuid primary key default gen_random_uuid(),
  received_at timestamptz not null default now(),
  channel     text not null default '전화'
              check (channel in ('전화','이메일','기관의뢰','홈페이지')),
  from_name   text,
  from_rel    text,
  from_tel    text,
  subject     text,
  region      text,
  note        text,
  meds_flags  text[] not null default '{}',  -- 항응고제/BP제제 등 1차 스크리닝
  status      text not null default '신규'
              check (status in ('신규','상담중','대상자 확정','보류','종결')),
  patient_id  uuid,
  ref_code    text,                          -- 보호자 조회용 접수번호 A-YYYYMMDD-NN
  created_by  uuid references auth.users(id),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 4. 환자
-- ---------------------------------------------------------------------
create table if not exists public.patients (
  id              uuid primary key default gen_random_uuid(),
  code            text unique,
  name            text not null,
  birth_year      integer,
  sex             text check (sex in ('남','여')),
  tel             text,
  guardian_name   text,
  guardian_rel    text,
  guardian_tel    text,
  region          text,
  address         text,
  place           text default '재가' check (place in ('재가','시설','요양병원')),
  ltc_grade       text,
  mobility        text,
  source          text,
  status          text not null default '상담중'
                  check (status in ('상담중','대상자 확정','진행중','보류','종료')),
  doctor_id       uuid references public.staff(id) on delete set null,
  diseases        text[] not null default '{}',
  meds            text[] not null default '{}',
  risks           text[] not null default '{}',
  ohat            integer check (ohat between 0 and 16),
  consent_care    boolean not null default false,
  consent_content boolean not null default false,
  memo            text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
alter table public.intakes
  drop constraint if exists intakes_patient_id_fkey,
  add constraint intakes_patient_id_fkey
  foreign key (patient_id) references public.patients(id) on delete set null;

-- 환자 코드 자동 부여 (P001, P002 …)
create or replace function public.set_patient_code()
returns trigger language plpgsql as $$
declare n integer;
begin
  if new.code is null then
    select coalesce(max(nullif(regexp_replace(code,'\D','','g'),'')::int),0)+1
      into n from public.patients;
    new.code := 'P' || lpad(n::text, 3, '0');
  end if;
  return new;
end $$;
drop trigger if exists patients_set_code on public.patients;
create trigger patients_set_code before insert on public.patients
  for each row execute function public.set_patient_code();

-- ---------------------------------------------------------------------
-- 5. 방문 (일정 + 치료 히스토리 통합 — 예약이 완료되면 그대로 진료기록이 됨)
-- ---------------------------------------------------------------------
create table if not exists public.visits (
  id            uuid primary key default gen_random_uuid(),
  patient_id    uuid not null references public.patients(id) on delete cascade,
  visit_date    date not null,
  visit_time    time,
  type          text not null default '치료'
                check (type in ('초진평가','치료','구강관리','리콜')),
  status        text not null default '예약'
                check (status in ('미배정','예약','완료','취소','부재')),
  doctor_id     uuid references public.staff(id) on delete set null,
  assistant_id  uuid references public.staff(id) on delete set null,
  region        text,
  title         text,
  fee_code      text,                          -- V-DENT-1 / V-DENT-2
  oral_care     boolean not null default false, -- 방문구강관리료 동시 산정
  addon_rate    numeric not null default 0,     -- 동반 인력 가산율
  act_codes     text[] not null default '{}',
  equipment_ids uuid[] not null default '{}',
  safety_checks jsonb not null default '{}'::jsonb,
  ohat          integer,
  billed_amount integer,
  note          text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists visits_date_idx    on public.visits(visit_date);
create index if not exists visits_patient_idx on public.visits(patient_id);

-- ---------------------------------------------------------------------
-- 6. 보유 장비
-- ---------------------------------------------------------------------
create table if not exists public.equipment (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  category   text,
  serial     text unique,
  status     text not null default '가용'
             check (status in ('가용','출동중','점검중','수리','폐기')),
  holder_id  uuid references public.staff(id) on delete set null,
  last_check date,
  next_check date,
  cycles     integer not null default 0,
  cycle_max  integer not null default 200,
  memo       text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 7. 제도 · 규정
-- ---------------------------------------------------------------------
create table if not exists public.rules (
  id         uuid primary key default gen_random_uuid(),
  category   text not null default '법령'
             check (category in ('법령','수가','시범사업','안전','개인정보')),
  title      text not null,
  effective  text,
  status     text not null default '적용중'
             check (status in ('적용중','가이드라인','참고','폐지')),
  body       text,
  todo       text,
  source_url text,
  sort       integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 8. 수가 마스터 (확정 고시 시 이 테이블만 갱신하면 전체 반영)
-- ---------------------------------------------------------------------
create table if not exists public.fee_master (
  code       text primary key,
  name       text not null,
  points     numeric,
  amount     integer not null,
  kind       text not null default '방문수가' check (kind in ('방문수가','행위수가')),
  note       text,
  active     boolean not null default true,
  sort       integer not null default 0,
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 9. 콘텐츠 소재
-- ---------------------------------------------------------------------
create table if not exists public.contents (
  id         uuid primary key default gen_random_uuid(),
  title      text not null,
  channel    text default '유튜브' check (channel in ('유튜브','인스타그램','블로그','기타')),
  status     text default '기획' check (status in ('기획','촬영','편집중','게시완료','보류')),
  patient_id uuid references public.patients(id) on delete set null,
  consent    boolean not null default false,
  url        text,
  note       text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 10. updated_at 자동 갱신
-- ---------------------------------------------------------------------
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

do $$
declare t text;
begin
  foreach t in array array['staff','intakes','patients','visits','equipment','rules','contents']
  loop
    execute format('drop trigger if exists touch_%1$s on public.%1$s', t);
    execute format('create trigger touch_%1$s before update on public.%1$s
                    for each row execute function public.touch_updated_at()', t);
  end loop;
end $$;

-- =====================================================================
--  RLS — 로그인하지 않으면 환자 정보에 접근할 수 없습니다. 반드시 켜두세요.
-- =====================================================================
do $$
declare t text;
begin
  foreach t in array array['profiles','staff','intakes','patients','visits',
                           'equipment','rules','fee_master','contents']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists p_read  on public.%I', t);
    execute format('drop policy if exists p_write on public.%I', t);
    execute format('drop policy if exists p_edit  on public.%I', t);
    execute format('drop policy if exists p_del   on public.%I', t);

    -- 조회: 로그인한 모든 직원
    execute format($f$create policy p_read on public.%I
      for select to authenticated using (public.my_role() in ('admin','staff','viewer'))$f$, t);
    -- 등록/수정: admin 또는 staff
    execute format($f$create policy p_write on public.%I
      for insert to authenticated with check (public.my_role() in ('admin','staff'))$f$, t);
    execute format($f$create policy p_edit on public.%I
      for update to authenticated using (public.my_role() in ('admin','staff'))$f$, t);
    -- 삭제: admin 만
    execute format($f$create policy p_del on public.%I
      for delete to authenticated using (public.my_role() = 'admin')$f$, t);
  end loop;
end $$;

-- 본인 프로필은 항상 조회 가능해야 로그인 직후 권한 판정이 됩니다
drop policy if exists p_self on public.profiles;
create policy p_self on public.profiles
  for select to authenticated using (id = auth.uid());

-- =====================================================================
--  Realtime — 치과 PC에서 입력하면 현장 휴대폰에 즉시 반영
-- =====================================================================
do $$
declare t text;
begin
  foreach t in array array['intakes','patients','visits','equipment','staff','contents','rules']
  loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then null;
    end;
  end loop;
end $$;

-- =====================================================================
--  기본 데이터 — 수가 마스터 (2026년 치과 환산지수 101.1원 기준)
--  ※ 방문치과진료 수가는 2026-06 공개된 1차 가이드라인이며 확정 고시가 아닙니다.
--     확정 고시가 나오면 이 표의 points / amount 만 UPDATE 하세요.
-- =====================================================================
insert into public.fee_master (code,name,points,amount,kind,note,sort) values
  ('V-DENT-1','방문치과진료료 1',1231.93,124548,'방문수가','진찰·검사·교육·처방 포함 포괄수가. 행위수가 별도 청구 불가.',1),
  ('V-DENT-2','방문치과진료료 2',1408.72,142421,'방문수가','장비 이송·관리료 포함. 건강보험 행위수가 별도 100% 청구 가능.',2),
  ('V-EQUIP','장비 이송 및 관리료',559.86,56601,'방문수가','방문치과진료료 2에 포함된 항목.',3),
  ('V-ORAL','방문구강관리료',797.83,80660,'방문수가','구강기능 평가·중재·교육 포괄수가. 진료료 2와 동시 산정 가능.',4),
  ('U2233','치석제거(1/3악)',null,22400,'행위수가',null,11),
  ('U0111','단순 발치(전치)',null,31200,'행위수가',null,12),
  ('U4413','광중합형 복합레진 충전',null,64500,'행위수가',null,13),
  ('U2411','치수절단(당일발수근충)',null,58900,'행위수가',null,14),
  ('U1051','의치 조정·수리',null,38200,'행위수가',null,15),
  ('U0221','치주낭 측정검사',null,9800,'행위수가',null,16)
on conflict (code) do nothing;

-- 기본 데이터 — 제도 · 규정
insert into public.rules (category,title,effective,status,body,todo,sort) values
  ('법령','의료·요양 등 지역 돌봄의 통합지원에 관한 법률','2026-03 시행','적용중',
   '시·군·구가 노쇠·장애 등으로 일상생활에 어려움이 있는 주민에게 의료·요양·돌봄을 통합 지원. 치과의사가 가정·사회복지시설을 방문해 진료를 제공하는 근거가 마련되었고, 방문구강관리가 지원 항목에 포함됨.',
   '관할 시·군·구 통합지원회의 참여기관 등록, 대상자 의뢰 경로 확보',1),
  ('수가','방문치과진료 수가 1차 가이드라인','2026-06 공개','가이드라인',
   '방문치과진료료 1(1,231.93점)·2(1,408.72점), 장비 이송 및 관리료(559.86점), 방문구강관리료(797.83점) 체계 제시. 진료료 2 선택 시 행위수가 별도 100% 청구 가능. 치과위생사·치과기공사 동반 시 가산 논의 중.',
   '확정 고시 전까지 청구 시뮬레이션만 운용, 고시 확정 시 fee_master 갱신',2),
  ('수가','2026년 치과 환산지수 101.1원 (전년 대비 +2%)','2026-01 적용','적용중',
   '요양급여비용 점수당 단가 101.1원. 급여 임플란트(의원) 135만 1,040원 등 다빈도 항목 조정.',
   '수가 마스터 단가 반영 완료',3),
  ('시범사업','일차의료 방문진료 수가 시범사업(의과·한의)','2026 상반기 공모','참고',
   '의과·한의 방문진료 시범사업이 선행 운영 중. 대상자 정의·산정 횟수 제한·참여기관 요건 등 운영 틀이 치과 방문진료 제도 설계의 준거가 됨.',
   '치과 시범사업 공모 공고 모니터링',4),
  ('안전','방문진료 감염관리 및 응급대응 내부 기준','내부 규정','적용중',
   '가정·시설 방문 시 멸균기구 팩 단위 관리, 흡인 위험 환자 체어 각도 관리, 응급 키트(에피네프린·산소) 상시 동반, 시술 전 보호자 입회 원칙.',
   '분기 1회 모의훈련 및 체크리스트 개정',5),
  ('개인정보','환자 촬영·콘텐츠 활용 동의 관리','내부 규정','적용중',
   '유튜브·인스타그램 콘텐츠 제작 시 별도 서면 동의 필수. 얼굴 노출 여부·음성 사용 여부·게시 채널·철회 방법을 분리 동의로 받고, 철회 시 7일 내 비공개 전환.',
   '전자동의서 서식 v2 배포',6)
on conflict do nothing;

-- =====================================================================
--  ★ 마지막 단계 ★  본인 계정을 관리자(admin)로 승격
--  1) 앱에서 회원가입 → 2) 아래 이메일을 본인 것으로 바꿔 실행
-- =====================================================================
-- update public.profiles set app_role = 'admin', name = '정상욱'
--   where id = (select id from auth.users where email = 'your@email.com');

-- =====================================================================
--  보호자 프론트(비로그인) 전용 정책
--  · 방문 신청은 누구나 "등록만" 가능 (조회·수정 불가)
--  · 진행 상황은 접수번호 + 연락처 뒷 4자리가 모두 일치할 때만 최소 정보 반환
-- =====================================================================
drop policy if exists p_public_apply on public.intakes;
create policy p_public_apply on public.intakes
  for insert to anon with check (channel = '홈페이지');

create or replace function public.guardian_status(p_ref text, p_tel text)
returns table (
  ref_code     text,
  person_name  text,
  status       text,
  next_date    date,
  next_time    time,
  doctor_name  text,
  next_title   text
)
language sql stable security definer set search_path = public as $$
  select i.ref_code,
         coalesce(p.name, i.from_name),
         i.status,
         v.visit_date,
         v.visit_time,
         s.name,
         v.title
  from public.intakes i
  left join public.patients p on p.id = i.patient_id
  left join lateral (
    select v2.* from public.visits v2
     where v2.patient_id = p.id and v2.status = '예약'
     order by v2.visit_date, v2.visit_time limit 1
  ) v on true
  left join public.staff s on s.id = v.doctor_id
  where i.ref_code = p_ref
    and length(regexp_replace(coalesce(i.from_tel,''), '\D', '', 'g')) >= 4
    and right(regexp_replace(coalesce(i.from_tel,''), '\D', '', 'g'), 4)
      = right(regexp_replace(coalesce(p_tel,''),     '\D', '', 'g'), 4)
  limit 1
$$;
revoke all on function public.guardian_status(text,text) from public;
grant execute on function public.guardian_status(text,text) to anon, authenticated;

-- 접수번호 자동 생성 (A-YYYYMMDD-NN)
create or replace function public.set_intake_ref()
returns trigger language plpgsql security definer set search_path = public as $$
declare d text; n int;
begin
  if new.ref_code is null then
    d := to_char(coalesce(new.received_at, now()) at time zone 'Asia/Seoul', 'YYYYMMDD');
    select count(*)+1 into n from public.intakes
      where ref_code like 'A-'||d||'-%';
    new.ref_code := 'A-'||d||'-'||lpad(n::text,2,'0');
  end if;
  return new;
end $$;
drop trigger if exists intakes_set_ref on public.intakes;
create trigger intakes_set_ref before insert on public.intakes
  for each row execute function public.set_intake_ref();
