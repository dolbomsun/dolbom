-- =====================================================================
--  돌봄(dolbom) — 공공데이터 게이트웨이
--  별도 서버 없이 Postgres에서 직접 외부 API를 호출합니다.
--  실행: Supabase → SQL Editor → 전체 붙여넣기 → Run  (schema.sql 실행 후)
--
--  구조
--   · api_keys       인증키 보관 (아무도 읽을 수 없음. admin만 저장 가능)
--   · gov_endpoints  API 주소 표 — 주소가 바뀌면 이 표만 UPDATE (코드 수정 불필요)
--   · gov_cache      응답 캐시 (같은 약을 매번 조회하지 않도록)
--   · gov_call()     앱이 부르는 단일 창구
-- =====================================================================

create extension if not exists http with schema extensions;

-- ---------------------------------------------------------------------
-- 1. 인증키 — 저장은 admin만, 조회는 아무도 못 함 (서버 함수만 접근)
-- ---------------------------------------------------------------------
create table if not exists public.api_keys (
  name       text primary key,
  value      text not null,
  updated_at timestamptz not null default now()
);
alter table public.api_keys enable row level security;
-- SELECT 정책을 일부러 만들지 않습니다 → 브라우저에서는 키를 읽을 수 없습니다.
drop policy if exists ak_write  on public.api_keys;
drop policy if exists ak_update on public.api_keys;
create policy ak_write  on public.api_keys for insert to authenticated
  with check (public.my_role() = 'admin');
create policy ak_update on public.api_keys for update to authenticated
  using (public.my_role() = 'admin');

-- 키 저장 (앱의 설정 화면에서 호출)
create or replace function public.set_api_key(p_name text, p_value text)
returns text language plpgsql security definer set search_path = public as $$
begin
  if public.my_role() <> 'admin' then raise exception '권한이 없습니다 (admin 전용)'; end if;
  insert into public.api_keys(name, value) values (p_name, btrim(p_value))
    on conflict (name) do update set value = excluded.value, updated_at = now();
  return 'saved';
end $$;

-- 어떤 키가 설정되어 있는지만 알려줌 (키 값 자체는 절대 반환하지 않음)
create or replace function public.api_key_status()
returns table (name text, is_set boolean, updated_at timestamptz)
language sql security definer set search_path = public as $$
  select k.name, true, k.updated_at from public.api_keys k
   where public.my_role() in ('admin','staff','viewer')
$$;

-- ---------------------------------------------------------------------
-- 2. API 주소 표 — 공공 API는 버전이 자주 바뀝니다.
--    호출이 실패하면 이 표의 base_url 만 고치면 됩니다.
-- ---------------------------------------------------------------------
create table if not exists public.gov_endpoints (
  api          text primary key,
  label        text not null,
  base_url     text not null,
  key_name     text not null default 'data_go_kr',
  key_param    text not null default 'serviceKey',
  fixed_params jsonb not null default '{}'::jsonb,
  cache_hours  integer not null default 168,   -- 기본 7일
  enabled      boolean not null default true,
  note         text,
  updated_at   timestamptz not null default now()
);
alter table public.gov_endpoints enable row level security;
drop policy if exists ge_read on public.gov_endpoints;
drop policy if exists ge_edit on public.gov_endpoints;
create policy ge_read on public.gov_endpoints for select to authenticated
  using (public.my_role() in ('admin','staff','viewer'));
create policy ge_edit on public.gov_endpoints for all to authenticated
  using (public.my_role() = 'admin') with check (public.my_role() = 'admin');

insert into public.gov_endpoints (api, label, base_url, key_name, fixed_params, cache_hours, note) values
  ('dur_elderly','의약품 DUR — 노인주의',
   'https://apis.data.go.kr/1471000/DURPrdlstInfoService03/getOdsnAtentTabooInfoList03',
   'data_go_kr', '{"type":"json","numOfRows":"20","pageNo":"1"}', 720,
   '식약처. 파라미터 itemName(제품명) 또는 ingrCode. 65세 이상 주의 성분 확인'),
  ('dur_interact','의약품 DUR — 병용금기',
   'https://apis.data.go.kr/1471000/DURPrdlstInfoService03/getUsjntTabooInfoList03',
   'data_go_kr', '{"type":"json","numOfRows":"30","pageNo":"1"}', 720,
   '식약처. 파라미터 itemName. 함께 먹으면 안 되는 약 확인'),
  ('drug_info','의약품 개요정보 (e약은요)',
   'https://apis.data.go.kr/1471000/DrbEasyDrugInfoService/getDrbEasyDrugList',
   'data_go_kr', '{"type":"json","numOfRows":"5","pageNo":"1"}', 720,
   '식약처. 파라미터 itemName. 효능·주의사항을 쉬운 말로'),
  ('juso','도로명주소 검색',
   'https://business.juso.go.kr/addrlink/addrLinkApi.do',
   'juso', '{"resultType":"json","currentPage":"1","countPerPage":"10"}', 24,
   '행안부. 파라미터 keyword. 인증키는 juso.go.kr에서 별도 발급'),
  ('ltc','장기요양기관 검색',
   'https://apis.data.go.kr/B550928/searchLtcInsttService01/getLtcInsttSearchList01',
   'data_go_kr', '{"_type":"json","numOfRows":"20","pageNo":"1"}', 168,
   '건강보험공단. 파라미터 siDoCd/siGunGuCd 또는 adminNm'),
  ('er','응급의료기관 위치 검색',
   'https://apis.data.go.kr/B552657/ErmctInfoInqireService/getEgytLcinfoInqire',
   'data_go_kr', '{"_type":"json","numOfRows":"10","pageNo":"1"}', 168,
   '중앙응급의료센터. 파라미터 WGS84_LON/WGS84_LAT/pageNo')
on conflict (api) do nothing;

-- juso는 파라미터 이름이 confmKey 입니다
update public.gov_endpoints set key_param = 'confmKey' where api = 'juso';

-- ---------------------------------------------------------------------
-- 3. 응답 캐시
-- ---------------------------------------------------------------------
create table if not exists public.gov_cache (
  cache_key  text primary key,
  api        text not null,
  data       jsonb not null,
  fetched_at timestamptz not null default now()
);
alter table public.gov_cache enable row level security;
drop policy if exists gc_read on public.gov_cache;
create policy gc_read on public.gov_cache for select to authenticated
  using (public.my_role() in ('admin','staff','viewer'));

-- ---------------------------------------------------------------------
-- 4. 단일 창구 — 앱은 이 함수 하나만 호출합니다
--    select * from gov_call('dur_elderly', '{"itemName":"와파린"}');
-- ---------------------------------------------------------------------
create or replace function public.gov_call(p_api text, p_params jsonb default '{}'::jsonb)
returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  ep       public.gov_endpoints%rowtype;
  k        text;
  qs       text := '';
  kv       record;
  url      text;
  ck       text;
  cached   public.gov_cache%rowtype;
  resp     extensions.http_response;
  parsed   jsonb;
begin
  if public.my_role() not in ('admin','staff','viewer') then
    return jsonb_build_object('ok', false, 'error', '로그인이 필요합니다');
  end if;

  select * into ep from public.gov_endpoints where api = p_api and enabled;
  if not found then
    return jsonb_build_object('ok', false, 'error', '알 수 없는 API: ' || p_api);
  end if;

  -- 캐시 확인
  ck := p_api || '|' || coalesce(p_params::text, '');
  select * into cached from public.gov_cache
   where cache_key = ck and fetched_at > now() - (ep.cache_hours || ' hours')::interval;
  if found then
    return jsonb_build_object('ok', true, 'cached', true, 'data', cached.data);
  end if;

  select value into k from public.api_keys where name = ep.key_name;
  if k is null then
    return jsonb_build_object('ok', false, 'error', '인증키 미설정',
                              'need_key', ep.key_name, 'label', ep.label);
  end if;

  -- 질의문자열 구성 (고정 파라미터 + 호출 파라미터)
  for kv in select key, value from jsonb_each_text(ep.fixed_params || coalesce(p_params, '{}'::jsonb))
  loop
    qs := qs || '&' || kv.key || '=' || extensions.urlencode(kv.value);
  end loop;
  url := ep.base_url || '?' || ep.key_param || '=' || extensions.urlencode(k) || qs;

  begin
    select * into resp from extensions.http_get(url);
  exception when others then
    return jsonb_build_object('ok', false, 'error', '호출 실패: ' || SQLERRM);
  end;

  if resp.status <> 200 then
    return jsonb_build_object('ok', false, 'error', 'HTTP ' || resp.status,
                              'body', left(coalesce(resp.content,''), 400));
  end if;

  begin
    parsed := resp.content::jsonb;
  exception when others then
    -- XML 등 JSON이 아닌 응답 (대개 인증키 오류)
    return jsonb_build_object('ok', false, 'error', 'JSON 아님 (인증키·승인상태 확인 필요)',
                              'body', left(coalesce(resp.content,''), 400));
  end;

  insert into public.gov_cache(cache_key, api, data)
    values (ck, p_api, parsed)
    on conflict (cache_key) do update set data = excluded.data, fetched_at = now();

  return jsonb_build_object('ok', true, 'cached', false, 'data', parsed);
end $$;

revoke all on function public.gov_call(text, jsonb) from public;
grant execute on function public.gov_call(text, jsonb)      to authenticated;
grant execute on function public.set_api_key(text, text)    to authenticated;
grant execute on function public.api_key_status()           to authenticated;

-- ---------------------------------------------------------------------
-- 5. 환자 복용약 안전성 점검 — 여러 약을 한 번에 확인
--    select * from patient_drug_alerts('<환자 uuid>');
-- ---------------------------------------------------------------------
create or replace function public.patient_drug_alerts(p_patient uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  meds   text[];
  drug   text;
  out_j  jsonb := '[]'::jsonb;
  r      jsonb;
  items  jsonb;
begin
  if public.my_role() not in ('admin','staff','viewer') then
    return jsonb_build_object('ok', false, 'error', '로그인이 필요합니다');
  end if;

  select p.meds into meds from public.patients p where p.id = p_patient;
  if meds is null or array_length(meds,1) is null then
    return jsonb_build_object('ok', true, 'alerts', '[]'::jsonb, 'note', '등록된 복용약이 없습니다');
  end if;

  foreach drug in array meds loop
    r := public.gov_call('dur_elderly', jsonb_build_object('itemName', drug));
    if (r->>'ok')::boolean then
      items := r #> '{data,body,items}';
      if items is not null and jsonb_typeof(items) = 'array' and jsonb_array_length(items) > 0 then
        out_j := out_j || jsonb_build_object(
          'drug', drug, 'kind', '노인주의',
          'detail', coalesce(items->0->>'PROHBT_CONTENT', items->0->>'TYPE_NAME', '노인 주의 성분'));
      end if;
    elsif r->>'error' = '인증키 미설정' then
      return jsonb_build_object('ok', false, 'error', '인증키 미설정', 'need_key', r->>'need_key');
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'alerts', out_j, 'checked', to_jsonb(meds));
end $$;
revoke all on function public.patient_drug_alerts(uuid) from public;
grant execute on function public.patient_drug_alerts(uuid) to authenticated;

-- =====================================================================
--  인증키 넣는 법 (둘 중 하나)
--   ① 앱 → 설정 · 연동 화면에서 입력  (권장)
--   ② 여기서 직접:
--      select public.set_api_key('data_go_kr', '발급받은_Decoding_키');
--      select public.set_api_key('juso',       'juso.go.kr_승인키');
--
--  발급처
--   · data_go_kr : https://www.data.go.kr  회원가입 → 각 API 활용신청 → 일반 인증키(Decoding)
--   · juso       : https://business.juso.go.kr  → 도로명주소 검색 API 신청
-- =====================================================================
