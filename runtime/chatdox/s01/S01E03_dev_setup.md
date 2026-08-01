# 3. 개발 환경 세팅

> 이 챕터에서는 채독스 개발을 시작하기 위한 환경을 컴퓨터에 구축합니다.
> 설치 순서를 그대로 따라하면 동일한 환경이 만들어집니다.

---

## 📋 설치 목록 (한눈에 보기)

| 순서 | 도구 | 버전 | 용도 |
|------|------|------|------|
| 1 | Git | 최신 | 버전 관리 |
| 2 | rbenv | 최신 | Ruby 버전 관리 |
| 3 | Ruby | 3.4.x | 프로그래밍 언어 |
| 4 | Rails | 8.1.x | 웹 프레임워크 |
| 5 | Node.js *(선택)* | LTS | 기본 스택(tailwindcss-rails + importmap-rails)에는 불필요 |
| 6 | VS Code | 최신 | 코드 편집기 |
| 7 | GitHub 계정 | - | 코드 저장소 |

---

## 1️⃣ Git 설치

### macOS

```bash
# Homebrew 설치 (없는 경우)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Git 설치
brew install git
```

### Windows

[https://git-scm.com/download/win](https://git-scm.com/download/win) 에서 다운로드 후 설치

### 설치 확인

```bash
git --version
# git version 2.x.x
```

### Git 초기 설정

```bash
git config --global user.name "이름"
git config --global user.email "이메일@example.com"
```

> 💡 **WSL을 쓴다면** Windows 쪽 Git에 이미 이름/이메일을 설정해뒀어도, WSL은 완전히 별개의 리눅스 환경이라 `~/.gitconfig`도 따로 있습니다. WSL 터미널에서도 위 명령을 한 번 더 실행해야 합니다 — 안 하면 `git commit` 시 "Author identity unknown" 에러가 납니다.

---

## 2️⃣ Ruby 설치 (rbenv 사용)

Ruby 버전을 유연하게 관리하기 위해 **rbenv**를 사용합니다.

### macOS

```bash
# rbenv 설치
brew install rbenv ruby-build

# rbenv 초기화 (쉘 설정 추가)
echo 'eval "$(rbenv init -)"' >> ~/.zshrc
source ~/.zshrc

# Ruby 3.4 설치
rbenv install 3.4.9
rbenv global 3.4.9

# 설치 확인
ruby --version
# ruby 3.4.9
```

### Windows

[RubyInstaller](https://rubyinstaller.org/downloads/) 에서 **Ruby+Devkit 3.4.x (x64)** 다운로드 후 설치

```bash
# 설치 확인
ruby --version
```

> 💡 설치 마지막 단계에서 **"Run 'ridk install'"** 체크박스를 반드시 체크하세요.

### Windows (WSL)

WSL(Windows Subsystem for Linux)을 쓰면 Windows에서도 macOS/Linux와 동일한 방식으로 rbenv를 사용할 수 있습니다. RubyInstaller 대신 이 방법을 쓰고 싶다면 아래를 따라하세요.

> 💡 WSL2 + Ubuntu가 이미 설치되어 있다는 전제입니다. 아직이라면 PowerShell(관리자 권한)에서 `wsl --install` 실행 후 재부팅하세요.

```bash
# 빌드에 필요한 패키지 설치
sudo apt update
sudo apt install -y build-essential libssl-dev libreadline-dev zlib1g-dev libffi-dev libyaml-dev

# rbenv + ruby-build 설치
git clone https://github.com/rbenv/rbenv.git ~/.rbenv
echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.bashrc
echo 'eval "$(rbenv init -)"' >> ~/.bashrc
source ~/.bashrc

git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build

# Ruby 3.4 설치
rbenv install 3.4.9
rbenv global 3.4.9

# 설치 확인
ruby --version
# ruby 3.4.9
```

> 💡 VS Code에서 WSL 안의 프로젝트를 열려면 WSL 확장이 필요합니다 — 5️⃣ "WSL 환경이라면" 참고.

### 이미 이전 버전(3.3.x)을 설치했다면

rbenv는 여러 Ruby 버전을 나란히 설치해두고 전환할 수 있습니다. 기존 3.3.x를 지우지 않고 3.4.9를 추가로 설치하면 됩니다.

```bash
# 3.4.9 추가 설치 (기존 버전은 그대로 남음)
rbenv install 3.4.9

# 이 프로젝트에서만 3.4.9를 쓰도록 지정
cd chatdox  # 프로젝트 폴더 안에서
rbenv local 3.4.9

# 또는 이 컴퓨터의 기본 버전 자체를 바꾸고 싶다면
rbenv global 3.4.9

# 버전 확인
ruby --version
# ruby 3.4.9

# 버전을 바꿨다면 의존성도 다시 설치
bundle install
```

> 💡 `rbenv local`은 프로젝트 폴더에 `.ruby-version` 파일을 만들어 그 폴더 안에서만 버전을 고정합니다. `chatdox-platform`처럼 이미 `.ruby-version`이 있는 프로젝트라면 이 명령을 따로 실행할 필요 없이, 그 폴더로 이동한 뒤 `rbenv install 3.4.9`만 해주면 rbenv가 알아서 `.ruby-version`에 적힌 버전을 사용합니다.

---

## 3️⃣ Rails 설치

```bash
# Rails 8.1 설치
gem install rails -v "~> 8.1"

# 설치 확인
rails --version
# Rails 8.1.x
```

---

## 4️⃣ Node.js 설치 (선택사항)

> 💡 **이 커리큘럼에서는 Node.js가 필수가 아닙니다.** `rails new --css tailwind`로 생성하면 **tailwindcss-rails** gem이 Tailwind의 standalone CLI(Ruby 플랫폼별 네이티브 바이너리)를 내장해서 Node.js 없이도 CSS를 빌드합니다. JavaScript도 **importmap-rails**를 쓰기 때문에 esbuild/webpack 같은 번들러가 필요 없고, 따라서 Node.js/npm도 필요 없습니다.
>
> 이후 챕터에서 `cssbundling-rails`/`jsbundling-rails`로 전환하거나, npm 패키지가 필요한 별도 JS 도구를 쓰고 싶다면 이 단계를 설치하세요. 그게 아니라면 건너뛰어도 됩니다.

### macOS

```bash
brew install node
```

### Windows

[https://nodejs.org](https://nodejs.org) 에서 **LTS 버전** 다운로드 후 설치

### 설치 확인

```bash
node --version   # v20.x.x 이상
npm --version    # 10.x.x 이상
```

---

## 5️⃣ VS Code 설치 & 설정

[https://code.visualstudio.com](https://code.visualstudio.com) 에서 다운로드

### 권장 확장 프로그램

VS Code에서 `Ctrl+Shift+X` (Extensions) 열고 설치:

| 확장 이름 | 용도 |
|-----------|------|
| Ruby LSP | Ruby 코드 자동완성, 오류 표시 |
| ERB Formatter/Beautify | ERB 파일 포맷팅 |
| Tailwind CSS IntelliSense | Tailwind 클래스 자동완성 |
| GitLens | Git 이력 시각화 |
| GitHub Copilot | AI 코드 어시스턴트 |

### WSL 환경이라면

[WSL 확장(Remote - WSL)](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-wsl)을 먼저 설치하세요. Windows 쪽 VS Code에 설치하면 됩니다.

```bash
# WSL 터미널에서 프로젝트 폴더로 이동한 뒤
code .
```

`code .`를 처음 실행하면 VS Code가 "WSL: Ubuntu에서 실행 중"으로 전환되면서, 위 표의 확장들을 **WSL 쪽에도 따로 설치**하라는 안내가 뜹니다. Windows에 이미 설치되어 있어도 WSL 컨테이너 안에서는 별개로 인식되기 때문입니다 — Extensions 패널에 뜨는 **"Install in WSL: Ubuntu"** 버튼을 눌러 하나씩(또는 한꺼번에) 설치하면 됩니다.

---

## 6️⃣ GitHub 계정 & SSH 설정

### GitHub 계정 생성

[https://github.com](https://github.com) 에서 계정 생성

### SSH 키 생성

```bash
ssh-keygen -t ed25519 -C "이메일@example.com"
# 엔터 3번 (기본값 사용)
```

### SSH 공개키 GitHub에 등록

```bash
# 공개키 출력
cat ~/.ssh/id_ed25519.pub
```

1. [GitHub Settings → SSH and GPG keys](https://github.com/settings/keys) 이동
2. **New SSH key** 클릭
3. 출력된 내용 전체 붙여넣기

### 연결 확인

```bash
ssh -T git@github.com
# Hi [username]! You've successfully authenticated.
```

---

## 7️⃣ 프로젝트 준비

환경 설치가 완료되면 채독스 프로젝트를 준비합니다. 상황에 따라 둘 중 하나를 선택하세요.

### A. 새로 생성하기 (처음 시작하는 경우)

```bash
# 원하는 경로로 이동
cd ~/projects  # 또는 원하는 폴더

# Rails 프로젝트 생성
rails new chatdox \
  --css tailwind \
  --database sqlite3 \
  --skip-test

# 생성된 폴더로 이동
cd chatdox

# 서버 실행 (Tailwind CSS 워처까지 함께 뜨는 bin/dev 사용)
bin/dev
```

> 💡 `--css tailwind`로 만든 프로젝트는 `rails server`만 실행하면 Tailwind CSS가 변경 사항을 감지해 다시 빌드해주지 않습니다. `bin/dev`는 `Procfile.dev`를 읽어 Rails 서버와 Tailwind 워처를 동시에 띄웁니다.

### B. 기존 리포지토리 클론하기 (이미 만들어진 프로젝트에 합류하는 경우)

팀에 합류했거나, 이미 생성된 chatdox 프로젝트를 이어서 개발한다면 새로 만들지 않고 클론합니다.

```bash
# 원하는 경로로 이동
cd ~/projects

# 리포지토리 클론
git clone git@github.com:[username]/chatdox.git
cd chatdox

# 의존성 설치
bundle install

# 데이터베이스 준비
rails db:prepare

# 서버 실행 (Tailwind CSS 워처까지 함께 뜨는 bin/dev 사용)
bin/dev
```

> 💡 `git clone`이 SSH로 안 되면 6️⃣에서 등록한 SSH 키를 먼저 확인하세요. `https://github.com/[username]/chatdox.git` 형태로 HTTPS 클론도 가능하지만, **HTTPS는 `git push`할 때 비밀번호 입력이 막혀있어** 별도로 Personal Access Token을 발급해야 합니다 (아래 트러블슈팅 참고). 가능하면 SSH를 쓰는 걸 권장합니다.

두 방법 모두 브라우저에서 [http://localhost:3000](http://localhost:3000) 접속 → Rails 기본 화면(A) 또는 채독스 화면(B)이 보이면 성공!

---

## 8️⃣ GitHub 리포지토리 연결

> 이 단계는 **7️⃣-A(새로 생성)**로 진행한 경우에만 필요합니다. **7️⃣-B(클론)**로 시작했다면 `origin`이 이미 연결되어 있으니 건너뛰세요.

```bash
# Git 초기화 (이미 되어 있음)
git init

# 첫 커밋
git add .
git commit -m "Initial Rails project setup"

# GitHub에서 새 리포지토리 생성 후
git remote add origin git@github.com:[username]/chatdox.git
git branch -M main
git push -u origin main
```

---

## 🔍 환경 확인 최종 체크

모든 설치가 완료되면 아래 명령어로 한 번에 확인하세요:

```bash
git --version     # git version 2.x.x
ruby --version    # ruby 3.4.x
rails --version   # Rails 8.1.x
node --version    # v20.x.x 이상 (Node.js를 설치했다면)
```

---

## 🚨 자주 발생하는 문제

**`rails` 명령어를 찾을 수 없습니다**
```bash
gem install rails
# 이후 터미널 재시작
```

**`bundle install` 오류 (macOS)**
```bash
xcode-select --install
```

**포트 3000이 이미 사용 중입니다**
```bash
PORT=3001 bin/dev  # 다른 포트 사용
```

**Windows에서 `rails new` 오류**
```bash
# Gemfile에서 gem "tzinfo-data" 주석 해제 확인
```

**WSL에서 `rbenv install` 시 fiddle/psych 빌드 실패**
```bash
# libffi, libyaml 누락이 원인. 위 "빌드에 필요한 패키지 설치" 명령에
# libffi-dev libyaml-dev가 빠졌다면 추가 설치 후 재시도
sudo apt install -y libffi-dev libyaml-dev
rbenv install 3.4.9
```

**WSL에서 `git commit` 시 "Author identity unknown" 에러**
```bash
# Windows Git에 이름/이메일을 설정해뒀어도 WSL은 별개 환경이라
# ~/.gitconfig가 따로 없으면 나는 에러. WSL 터미널에서 다시 설정
git config --global user.name "이름"
git config --global user.email "이메일@example.com"
```

**`git push` 시 "Invalid username or token. Password authentication is not supported"**
```text
원인: 리포지토리 remote가 HTTPS(https://github.com/...)로 설정되어 있고,
GitHub는 2021년부터 git push/pull에 비밀번호 로그인을 지원하지 않는다.
```
```bash
# 해결 1 (권장): remote를 SSH로 바꾼다 — 6️⃣에서 등록한 SSH 키를 그대로 사용
git remote set-url origin git@github.com:[username]/chatdox.git
git remote -v  # origin이 git@github.com:... 형태인지 확인

# 해결 2: HTTPS를 계속 쓰고 싶다면 비밀번호 대신 Personal Access Token 발급
# GitHub → Settings → Developer settings → Personal access tokens → Generate new token
# 이후 비밀번호를 물어볼 때 그 토큰을 붙여넣는다

# 해결 3 (제일 간편): GitHub CLI(gh)로 인증을 통째로 맡긴다
# 설치 (WSL/Ubuntu)
sudo apt install gh -y
# 설치 (macOS)
brew install gh
# 설치 (Windows) - https://cli.github.com 에서 설치 프로그램 다운로드

# 인증 (한 번만 하면 됨)
gh auth login
# GitHub.com 선택 → HTTPS 또는 SSH 선택 → 브라우저로 로그인
# 이후 git push/pull이 gh가 관리하는 인증으로 자동 처리된다
```

> 💡 SSH 키를 직접 만들고 등록하는 것도 번거롭게 느껴진다면, `gh auth login` 하나로 인증까지 끝내는 게 제일 간편합니다 — SSH/PAT를 따로 설정할 필요가 없습니다.

---

## ✅ 챕터 3 체크리스트

- [ ] Ruby 3.4.x 설치 완료
- [ ] Rails 8.1.x 설치 완료
- [ ] (선택) Node.js LTS 설치 완료
- [ ] VS Code + 권장 확장 프로그램 설치
- [ ] GitHub SSH 연결 완료
- [ ] 프로젝트 준비 완료 (`rails new chatdox` 새로 생성, 또는 `git clone`으로 기존 리포 가져오기)
- [ ] `http://localhost:3000` 접속 성공
- [ ] (새로 생성한 경우만) GitHub 리포지토리 첫 커밋 완료

---

## ➡️ 다음 챕터

**[4. 랜딩페이지 구축 →](/docs/4)**

> 환경 준비 완료! 이제 채독스의 첫 화면인 랜딩페이지를 만들어봅니다.
