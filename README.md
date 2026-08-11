# 돌봄 (dolbom) · 방문치과 통합관리 플랫폼

트리즈컴퍼니 × 태양치과(정상욱 원장) 방문진료 운영 시스템.
치과 PC·원장님 휴대폰·방문 현장 어디서든 **같은 데이터**를 보고 입력합니다.

- **운영 어드민** — 대시보드 / 접수·상담 / 환자관리 / 일정·방문배정 / 장비 / 참여의료진 / 제도·수가 / 안전 체크리스트 / 콘텐츠 소재 / 설정
- **보호자 프론트** — 홈 / 방문 신청 / 대상자 자가확인 / 진행 상황 조회 / 제도 안내 *(로그인 불필요)*

---

## 30분이면 원격 접속까지 끝납니다

순서대로만 하시면 됩니다. **1~2단계만 해도 URL이 나와 원격 접속은 됩니다.**
3~4단계를 해야 여러 기기가 같은 데이터를 봅니다.

### 1단계 · GitHub에 올리기 (10분)

1. https://github.com/new 에서 저장소를 만듭니다.
   - 이름: `dolbom` (자유)
   - **Public** 선택 *(Private이면 GitHub Pages에 유료 플랜 필요)*
   - README 체크는 해제
2. 이 폴더 전체를 올립니다. 터미널에서:

```bash
cd dolbom
git init
git add .
git commit -m "돌봄 v1"
git branch -M main
git remote add origin https://github.com/<본인계정>/dolbom.git
git push -u origin main
```

> 터미널이 익숙하지 않으시면, GitHub 저장소 화면의 **Add file → Upload files** 로 폴더 안 파일을 통째로 끌어다 놓아도 됩니다. (`.github` 폴더는 웹 업로드로 안 올라갈 수 있으니, 이 경우 2단계에서 "Deploy from a branch"를 선택하세요.)

### 2단계 · GitHub Pages 켜기 (2분)

저장소 → **Settings → Pages**

- Source: **GitHub Actions** 선택 *(웹 업로드로 올리셨다면 "Deploy from a branch" → Branch: `main`, Folder: `/ (root)`)*
- 1~2분 뒤 주소가 나옵니다: `https://<계정>.github.io/dolbom/`

이 주소를 휴대폰에서 열고 **홈 화면에 추가**하면 앱처럼 실행됩니다.
(iPhone: 공유 → 홈 화면에 추가 / Android: 메뉴 → 홈 화면에 추가)

이 시점에서는 **데모 모드**입니다. 화면은 다 되지만 기기마다 데이터가 따로 저장됩니다.

### 3단계 · Supabase 프로젝트 만들기 (10분)

1. https://supabase.com 가입 → **New project**
   - Name: `dolbom`
   - Database Password: 안전하게 보관
   - **Region: Northeast Asia (Seoul)** ← 반드시 서울로
2. 왼쪽 메뉴 **SQL Editor** → **New query**
   - `supabase/schema.sql` 파일 내용을 **전부 복사해 붙여넣고 Run**
   - (예시 데이터를 보고 싶으면 `supabase/seed.sql` 도 같은 방식으로 Run)
3. 왼쪽 메뉴 **Project Settings → API** 에서 두 값을 복사
   - `Project URL`
   - `anon public` 키

### 4단계 · 앱에 연결하기 (3분)

`index.html` 파일 상단에서 이 부분을 찾아 두 줄을 채웁니다:

```js
const CONFIG = {
  SUPABASE_URL:      'https://abcdefgh.supabase.co',
  SUPABASE_ANON_KEY: 'eyJhbGciOi...',
  CLINIC_NAME:       '태양치과'
};
```

저장하고 다시 push 하면 (또는 GitHub 웹에서 연필 아이콘으로 수정 → Commit) 1~2분 뒤 반영됩니다.

> **anon key는 공개되어도 안전합니다.** 이 앱은 RLS(행 수준 보안)로 보호되어, 로그인하지 않으면 환자 정보에 접근할 수 없습니다. `service_role` 키는 **절대** 이 파일에 넣지 마세요.

### 5단계 · 계정 만들고 권한 올리기 (5분)

1. 배포된 주소를 열면 **직원 로그인** 화면이 나옵니다 → "계정 만들기"로 가입
2. Supabase → **SQL Editor** 에서 아래를 실행 (이메일을 본인 것으로 교체)

```sql
update public.profiles set app_role = 'admin', name = '정상욱'
  where id = (select id from auth.users where email = 'your@email.com');
```

3. 앱에서 새로고침 → 전체 데이터가 보입니다.

직원을 추가할 때는 같은 방식으로 `app_role`을 정해 주시면 됩니다.

| 권한 | 할 수 있는 일 | 누구에게 |
|---|---|---|
| `pending` | **아무것도 못 봄 (기본값)** | 가입 직후 모든 계정 |
| `viewer` | 조회만 | 참관·실습생 |
| `staff` | 조회 + 등록/수정 | 협력의·위생사·코디네이터 |
| `admin` | 전부 + 삭제 | 원장 |

> 주소가 공개되어 있으므로 **누구나 가입 자체는 가능**합니다. 다만 신규 계정은 `pending`으로 시작해
> 환자 정보를 한 줄도 볼 수 없습니다. 원장님이 위 SQL로 권한을 올려준 계정만 데이터에 접근합니다.
> 가입 자체를 막고 싶으면 Supabase → Authentication → Sign In / Providers → Email의
> **Allow new users to sign up**을 꺼두고, 직원은 Authentication → Users에서 직접 초대하세요.

---

## 방문 현장에서 (오프라인 대비)

요양시설이나 지하 주차장처럼 전파가 약한 곳을 전제로 만들었습니다.

- 앱 화면은 기기에 캐시되어 **인터넷이 끊겨도 실행**됩니다.
- 오프라인 상태에서 입력한 내용은 기기에 저장되고, **연결되면 자동으로 전송**됩니다. 상단 표시가 `전송대기 N` 으로 바뀝니다.
- 마지막으로 받아온 환자·일정 데이터는 오프라인에서도 조회할 수 있습니다.
- 다른 기기에서 입력한 내용은 **실시간으로 반영**됩니다. 새로고침이 필요 없습니다.

## 수가가 확정 고시되면

이 앱의 모든 금액은 `fee_master` 테이블 하나에서 나옵니다. Supabase에서 그 표의 `points`와 `amount`만 고치면 대시보드·일정·시뮬레이터에 한 번에 반영됩니다.

```sql
update public.fee_master set points = 1300, amount = 131430 where code = 'V-DENT-1';
```

---

## 파일 구성

```
dolbom/
├── index.html              앱 전체 (화면 + 로직, 단일 파일)
├── manifest.webmanifest    홈 화면 설치용
├── sw.js                   오프라인 캐시 · 서비스워커
├── icons/                  앱 아이콘
├── supabase/
│   ├── schema.sql          테이블 · 권한(RLS) · 실시간 · 기본 수가/제도 데이터
│   └── seed.sql            예시 데이터 (가상 · 선택)
└── .github/workflows/deploy.yml
```

## 데이터 구조 요약

| 테이블 | 내용 |
|---|---|
| `profiles` | 로그인 계정 권한 (admin/staff/viewer) |
| `staff` | 참여 의료진 (로그인하지 않는 인력 포함) |
| `intakes` | 접수·상담. 보호자 신청도 여기로 들어옴 |
| `patients` | 환자 인적사항·전신상태·동의 |
| `visits` | **일정과 치료 히스토리를 하나로** — 예약이 완료되면 그대로 진료기록 |
| `equipment` | 포터블 장비 대여·점검 주기 |
| `fee_master` | 수가 마스터 (여기만 고치면 전체 반영) |
| `rules` | 제도·규정 카드 |
| `contents` | 콘텐츠 소재 + 동의 게이팅 |

---

## 주의사항

- 이 저장소의 예시 데이터는 **전부 가상**입니다. 실제 환자 정보가 아닙니다.
- 실제 환자 정보를 입력하기 전에 **개인정보 처리방침 수립과 법률 검토**를 권장합니다. 의료 데이터에는 개인정보보호법·의료법이 적용됩니다.
- 방문치과진료 수가는 **2026년 6월 공개된 1차 가이드라인** 기준이며 확정 고시가 아닙니다. 청구 시뮬레이터는 내부 판단용입니다.
- Supabase 무료 플랜은 일정 기간 미사용 시 프로젝트가 일시 정지될 수 있습니다. 실운영 시 유료 플랜을 검토하세요.

## 참고 자료

- [의료·요양 등 지역 돌봄의 통합지원에 관한 법률 — 국가법령정보센터](https://www.law.go.kr/lsInfoP.do?lsiSeq=261447&viewCls=lsRvsDocInfoR)
- [시행령·시행규칙 제정안 입법예고 — 보건복지부](https://www.mohw.go.kr/board.es?mid=a10503000000&bid=0027&list_no=1486235&act=view)
- [방문치과진료 수가 1차 가이드라인 — 치의신보](https://www.kwda.co.kr/bbs/board.php?bo_table=206&wr_id=1076)
- [2026년 달라지는 제도, 치과계와 맞닿은 변화 — 치과신문](https://www.dentalnews.or.kr/news/article.html?no=46229)
- [일차의료 방문진료 수가 시범사업 지침 — 심평원](https://www.hira.or.kr/bbs/157/2024/11/BZ202411140797067.pdf)
