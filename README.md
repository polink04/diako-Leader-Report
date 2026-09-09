# Diako Leader Report

GitHub Pages에서 실행되는 그룹장 주간보고 웹입니다.

## 제공 기능

- 링크 방문자의 보고서 작성 및 영구 저장
- 작성자별 개인 수정 링크와 `지난 보고서`
- 다른 작성자의 보고서 비공개
- 대표 계정의 전체 보고서 조회 및 코멘트
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

## 2. 대표 로그인 설정

현재 대표 이메일은 `polink@oogs.io`로 설정되어 있습니다. 다른 이메일을 사용하려면 아래 두 곳을 함께 변경합니다.

- `index.html`의 `ADMIN_EMAIL`
- `supabase-schema.sql`의 `polink@oogs.io`

Supabase의 `Authentication → URL Configuration`에서 다음 주소를 추가합니다.

```text
https://polink04.github.io/diako-leader-report/
```

대표 로그인은 이메일로 발송되는 매직링크 방식입니다.

## 3. GitHub Pages에 올리기

1. GitHub에 `diako-leader-report` 저장소를 만듭니다.
2. 이 폴더의 `index.html`, `supabase-schema.sql`, `README.md`를 업로드합니다.
3. 저장소의 `Settings → Pages`로 이동합니다.
4. `Deploy from a branch`를 선택합니다.
5. Branch는 `main`, 폴더는 `/(root)`로 선택해 저장합니다.
6. 배포 후 아래 주소로 접속합니다.

```text
https://polink04.github.io/diako-leader-report/
```

## 작동 방식

그룹장이 처음 보고서를 저장하면 추측하기 어려운 개인 수정 토큰을 발급합니다. 토큰은 해당 브라우저에 저장되고 개인 수정 링크에도 포함됩니다. 대표님은 `대표 로그인` 후 전체 보고서를 볼 수 있습니다. 데이터베이스 테이블은 직접 공개하지 않고 제한된 함수만 호출하도록 구성했습니다.

## 주의사항

- GitHub Pages 주소 자체는 공개 URL입니다. 주소를 전달받은 사람은 새 보고서를 작성할 수 있습니다.
- 작성자는 개인 수정 링크를 북마크해야 다른 기기에서도 기존 보고서를 수정할 수 있습니다.
- 기존 ChatGPT Sites 버전에 저장된 보고서는 Supabase로 자동 이전되지 않습니다.
