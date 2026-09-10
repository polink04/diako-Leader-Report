# Diako Leader Report

GitHub Pages에서 실행되는 그룹장 주간보고 웹입니다.

## 제공 기능

- 허용된 대표·리더의 이메일/비밀번호 로그인
- 계정별 보고서 영구 저장과 PC·모바일 자동 동기화
- 다른 작성자의 보고서 비공개
- 대표 계정의 전체 보고서 조회 및 코멘트
- 리더의 지난 보고서 수정·보완 및 최근 수정 시각 기록
- 대표 계정의 보고서 삭제(작성 리더의 목록에서도 즉시 삭제)
- 대표 코멘트 작성자 확인
- A4 인쇄 최적화
- 모바일·PC 반응형 화면

## 1. Supabase 준비

1. [Supabase](https://supabase.com/)에서 새 프로젝트를 만듭니다.
2. `SQL Editor`에서 `supabase-schema.sql` 전체를 실행합니다.
3. `Project Settings → API`에서 다음 값을 확인합니다.
   - Project URL
   - anon 또는 publishable key
4. `index.html` 상단의 설정값을 수정합니다.

```js
const SUPABASE_URL = "https://YOUR_PROJECT.supabase.co";
const SUPABASE_ANON_KEY = "YOUR_SUPABASE_ANON_KEY";
```

> `service_role` 키는 절대 HTML에 넣지 마세요. 브라우저에는 anon/publishable key만 사용합니다.

## 2. 로그인 계정 설정

`supabase-schema.sql` 실행 후 `allowed_report_users` 테이블에 대표와 리더의 이메일을 등록합니다. 실제 비밀번호는 Supabase `Authentication → Users`에서 각 사용자를 생성할 때 설정합니다.

- 대표 계정은 `is_admin = true`
- 리더 계정은 `is_admin = false`
- 공개 GitHub 저장소에는 실제 이메일이나 비밀번호를 기록하지 않습니다.

Supabase의 `Authentication → URL Configuration`에서 다음 주소를 추가합니다.

```text
https://polink04.github.io/diako-Leader-Report/
```

로그인은 Supabase 이메일/비밀번호 인증을 사용합니다.

## 3. GitHub Pages에 올리기

1. GitHub에 `diako-leader-report` 저장소를 만듭니다.
2. 이 폴더의 `index.html`, `supabase-schema.sql`, `README.md`를 업로드합니다.
3. 저장소의 `Settings → Pages`로 이동합니다.
4. `Deploy from a branch`를 선택합니다.
5. Branch는 `main`, 폴더는 `/(root)`로 선택해 저장합니다.
6. 배포 후 아래 주소로 접속합니다.

```text
https://polink04.github.io/diako-Leader-Report/
```

## 작동 방식

로그인한 그룹장의 Supabase 계정 ID에 보고서가 귀속됩니다. 따라서 같은 계정으로 로그인하면 컴퓨터와 모바일에서 동일한 지난 보고서를 확인하고 수정할 수 있습니다. 대표 계정은 모든 보고서를 열람하고 코멘트를 남길 수 있습니다. 데이터베이스 테이블은 직접 공개하지 않고 권한을 확인하는 제한된 함수만 호출하도록 구성했습니다.

## 주의사항

- GitHub Pages 주소는 공개 URL이지만, 허용 목록과 Supabase 사용자 계정에 모두 등록된 사람만 보고서를 사용할 수 있습니다.
- 비밀번호는 GitHub 파일이나 SQL 파일에 기록하지 않습니다.
- 기존 ChatGPT Sites 버전에 저장된 보고서는 Supabase로 자동 이전되지 않습니다.
