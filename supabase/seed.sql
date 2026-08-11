-- =====================================================================
--  HomeDenti — 예시 데이터 (선택)
--  실제 환자 정보가 아닌 가상 데이터입니다. 팀 교육·시연용으로만 사용하세요.
--  실제 운영을 시작할 때는 아래 "초기화" 블록으로 전부 지우고 시작하면 됩니다.
--  실행: Supabase → SQL Editor → 붙여넣기 → Run  (schema.sql 실행 후)
-- =====================================================================

-- ── 참여 의료진 ───────────────────────────────────────────────────────
insert into public.staff (name, clinic, role, regions, slots, tel, unit_fee) values
  ('정상욱','태양치과','원장',      '{성동구,광진구}',              '화·목 오후','02-000-0001',180000),
  ('김하늘','태양치과','협력의',    '{중랑구,동대문구}',            '수 종일',   '02-000-0002',180000),
  ('박선영','연합 협력의','협력의', '{성동구}',                     '금 오전',   '02-000-0003',180000),
  ('이수민','태양치과','치과위생사','{성동구,광진구,중랑구}',        '주 4일',    '02-000-0011', 60000)
on conflict do nothing;

-- ── 보유 장비 ────────────────────────────────────────────────────────
insert into public.equipment (name, category, serial, status, last_check, next_check, cycles) values
  ('포터블 유닛체어 A','유닛','PU-2401','출동중','2026-07-28','2026-08-28',132),
  ('포터블 유닛체어 B','유닛','PU-2402','가용',  '2026-08-03','2026-09-03', 97),
  ('포터블 X-ray','영상','PX-1180','가용',      '2026-08-01','2026-08-31',210),
  ('이동식 석션','석션','SC-330','점검중',      '2026-08-09','2026-08-12',305),
  ('무선 핸드피스 세트','핸드피스','HP-772','출동중','2026-08-05','2026-09-05',188),
  ('휴대용 멸균 파우치 키트','멸균','ST-050','가용','2026-08-08','2026-08-15', 64),
  ('응급 키트(산소·에피네프린)','응급','EM-009','가용','2026-07-20','2026-08-20', 12)
on conflict (serial) do nothing;

update public.equipment e set holder_id = s.id
  from public.staff s where e.serial='PU-2401' and s.name='정상욱';
update public.equipment e set holder_id = s.id
  from public.staff s where e.serial='HP-772' and s.name='김하늘';

-- ── 환자 (가상) ──────────────────────────────────────────────────────
insert into public.patients
  (name,birth_year,sex,tel,guardian_name,guardian_rel,guardian_tel,region,address,place,
   ltc_grade,mobility,source,status,diseases,meds,risks,ohat,consent_care,consent_content)
values
  ('김O자',1938,'여','010-****-1122','김O수','자녀','010-****-9080','성동구','성동구 행당동','재가',
   '장기요양 2등급','와상 (이동 불가)','전화','진행중',
   '{뇌졸중 후유증,고혈압,당뇨}','{와파린,메트포르민}','{"출혈위험(와파린)",흡인위험}',11,true,false),
  ('박O호',1941,'남','010-****-3344','박O민','자녀','010-****-7712','광진구','광진구 자양동','시설',
   '장기요양 3등급','휠체어 이동','기관의뢰','진행중',
   '{"치매(중등도)",골다공증}','{도네페질,비스포스포네이트}','{"MRONJ 위험(BP제제)","협조도 저하"}',9,true,true),
  ('이O순',1945,'여','010-****-5566','이O경','배우자','010-****-2231','중랑구','중랑구 면목동','재가',
   '장기요양 4등급','실내 보행 가능','이메일','대상자 확정',
   '{파킨슨병}','{레보도파}','{연하곤란}',7,true,false),
  ('최O식',1936,'남','010-****-7788','최O라','자녀','010-****-4410','성동구','성동구 금호동','재가',
   '장기요양 1등급','와상 (이동 불가)','전화','상담중',
   '{만성신부전,심부전}','{푸로세미드}','{"전신상태 불안정"}',14,false,false),
  ('정O분',1943,'여','010-****-9900','정O우','자녀','010-****-6653','동대문구','동대문구 답십리동','재가',
   '인지지원등급','보조기 보행','전화','진행중','{경도인지장애}','{}','{}',5,true,true),
  ('한O례',1939,'여','010-****-1010','한O진','자녀','010-****-3399','광진구','광진구 구의동','시설',
   '장기요양 2등급','휠체어 이동','기관의뢰','종료','{고혈압}','{암로디핀}','{}',4,true,false)
on conflict do nothing;

update public.patients p set doctor_id = s.id from public.staff s
  where s.name='정상욱' and p.name in ('김O자','박O호');
update public.patients p set doctor_id = s.id from public.staff s
  where s.name='김하늘' and p.name in ('이O순','정O분');
update public.patients p set doctor_id = s.id from public.staff s
  where s.name='박선영' and p.name = '한O례';

-- ── 접수 · 상담 ──────────────────────────────────────────────────────
insert into public.intakes (received_at,channel,from_name,from_rel,from_tel,subject,region,note,status,ref_code) values
  ('2026-08-11 09:12+09','전화','김O수','자녀','010-****-9080','모친 와상, 잇몸 붓고 통증','성동구',
   '장기요양 2등급, 와파린 복용. 방문 가능 여부 문의.','신규','A-20260811-01'),
  ('2026-08-10 16:40+09','이메일','서울OO요양원','시설 담당자','02-000-1234','입소자 4인 구강검진 요청','광진구',
   '시설 단체 검진 문의. 수가·동의서 절차 안내 필요.','상담중','A-20260810-02'),
  ('2026-08-10 11:05+09','전화','이O경','배우자','010-****-2231','의치가 헐거워 식사 어려움','중랑구',
   '8/12 초진 방문 확정.','대상자 확정','A-20260810-01'),
  ('2026-08-09 14:22+09','기관의뢰','성동구 통합돌봄창구','기관','02-000-5678','통합지원회의 의뢰 건','성동구',
   '돌봄통합지원법 대상자. 방문구강관리 우선 필요 판단.','신규','A-20260809-01'),
  ('2026-08-08 10:31+09','전화','최O라','자녀','010-****-4410','부친 전신상태 문의','성동구',
   '만성신부전·심부전. 주치의 소견 확인 후 재상담.','보류','A-20260808-01')
on conflict do nothing;

-- ── 방문 (일정 + 치료 히스토리) ──────────────────────────────────────
insert into public.visits (patient_id,visit_date,visit_time,type,status,doctor_id,region,title,fee_code,act_codes,note)
select p.id,'2026-07-09','10:00','초진평가','완료',s.id,'성동구','초진 구강평가 (OHAT 13점)','V-DENT-1','{U0221}',
       '다수 잔존치근, 의치 부적합.'
  from public.patients p, public.staff s where p.name='김O자' and s.name='정상욱'
on conflict do nothing;
insert into public.visits (patient_id,visit_date,visit_time,type,status,doctor_id,region,title,fee_code,oral_care,note)
select p.id,'2026-07-23','14:00','구강관리','완료',s.id,'성동구','치면세균막 관리 · 보호자 교육','V-ORAL',false,
       '보호자 칫솔질 각도 교육.'
  from public.patients p, public.staff s where p.name='김O자' and s.name='이수민'
on conflict do nothing;
insert into public.visits (patient_id,visit_date,visit_time,type,status,doctor_id,region,title,fee_code,act_codes,note)
select p.id,'2026-08-06','10:00','치료','완료',s.id,'성동구','#36 잔존치근 발치','V-DENT-2','{U0111}',
       'INR 확인 후 시행. 지혈 양호.'
  from public.patients p, public.staff s where p.name='김O자' and s.name='정상욱'
on conflict do nothing;
insert into public.visits (patient_id,visit_date,visit_time,type,status,doctor_id,region,title,fee_code)
select p.id,'2026-08-11','10:00','치료','예약',s.id,'성동구','#37 우식 치료 예정','V-DENT-2'
  from public.patients p, public.staff s where p.name='김O자' and s.name='정상욱'
on conflict do nothing;
insert into public.visits (patient_id,visit_date,visit_time,type,status,doctor_id,region,title,fee_code,oral_care)
select p.id,'2026-08-04','14:00','구강관리','완료',s.id,'광진구','의치 세정 및 조정','V-ORAL',false
  from public.patients p, public.staff s where p.name='박O호' and s.name='이수민'
on conflict do nothing;
insert into public.visits (patient_id,visit_date,visit_time,type,status,doctor_id,region,title,fee_code)
select p.id,'2026-08-12','13:00','치료','예약',s.id,'광진구','하악 의치 조정','V-DENT-2'
  from public.patients p, public.staff s where p.name='박O호' and s.name='정상욱'
on conflict do nothing;
insert into public.visits (patient_id,visit_date,visit_time,type,status,doctor_id,region,title,fee_code,note)
select p.id,'2026-08-12','09:30','초진평가','예약',s.id,'중랑구','초진 방문 예정','V-DENT-1','연하평가 동반 예정.'
  from public.patients p, public.staff s where p.name='이O순' and s.name='김하늘'
on conflict do nothing;
insert into public.visits (patient_id,visit_date,visit_time,type,status,region,title,fee_code)
select p.id,'2026-08-13','11:00','초진평가','미배정','성동구','초진 방문 (담당 미배정)','V-DENT-1'
  from public.patients p where p.name='최O식'
on conflict do nothing;
insert into public.visits (patient_id,visit_date,visit_time,type,status,doctor_id,region,title,fee_code,act_codes)
select p.id,'2026-08-05','10:30','치료','완료',s.id,'동대문구','#25 복합레진 충전','V-DENT-2','{U4413}'
  from public.patients p, public.staff s where p.name='정O분' and s.name='김하늘'
on conflict do nothing;
insert into public.visits (patient_id,visit_date,visit_time,type,status,doctor_id,region,title,fee_code,oral_care)
select p.id,'2026-08-14','14:00','구강관리','예약',s.id,'성동구','정기 구강관리','V-ORAL',false
  from public.patients p, public.staff s where p.name='김O자' and s.name='이수민'
on conflict do nothing;

-- ── 콘텐츠 소재 ──────────────────────────────────────────────────────
insert into public.contents (title,channel,status,consent,note) values
  ('와상 어르신 발치, 어디까지 가능할까요','유튜브','편집중',false,'동의 미취득 → 재연/일러스트로 대체 제작'),
  ('요양시설 의치 관리 3분 가이드','유튜브','게시완료',true,'조회수 1.2만 · 문의 전환 6건'),
  ('집에서 하는 어르신 구강체조','인스타그램','기획',true,'릴스 3편 시리즈'),
  ('돌봄통합지원법, 치과는 무엇이 달라지나','유튜브','게시완료',true,'제도 설명 · 기관 문의 4건')
on conflict do nothing;

update public.contents c set patient_id = p.id from public.patients p
  where c.title like '와상%' and p.name='김O자';
update public.contents c set patient_id = p.id from public.patients p
  where c.title like '요양시설%' and p.name='박O호';

-- =====================================================================
--  초기화 (실제 운영 시작 전에 예시 데이터를 지우려면 아래 주석을 해제)
-- =====================================================================
-- truncate public.visits, public.contents, public.intakes, public.patients,
--          public.equipment, public.staff restart identity cascade;
