#!/usr/bin/env bash
#
# ritual_mac.sh
# macOS 환경에서 Infernet(Ritual Node) 설치 & 세팅을 자동화하는 스크립트.
#
# 특징:
# 1) Docker / Docker Compose 설치 확인
# 2) Python3 / pip3 설치 후 infernet-cli, infernet-client 설치
# 3) Foundry 설치 (anvil 실행 중이면 종료)
# 4) infernet-container-starter 클론 + screen 배포
# 5) config.json / Deploy.s.sol / docker-compose.yaml / Makefile / Forge 한 번에 수정
# 6) 원-엔터로 Private Key만 입력하면 진행
# 7) 배포 후 로그에서 새 컨트랙트 주소를 추출 → CallContract.s.sol에 반영 → call-contract 실행
#
# 주의:
# - script/Deploy.s.sol 로그에서 'Deployed SaysHello:  0x...' 구문이 존재해야 주소를 grep 추출 가능
# - registry 주소를 0x3B1554f346DFe5c482Bb4BA31b880c1C18412170 로 설정
# - node 이미지는 'ritualnetwork/infernet-node:latest' 로 치환
# - 만약 실제 Makefile에 변수명이 다르거나, Deploy.s.sol 로그가 다른 형식이면 sed 정규식을 맞춰 수정 필요

echo "===== Ritual Node Setup Script (macOS) ====="
echo "[안내] 본 스크립트는 macOS 환경을 가정하고 있습니다."
echo "      Docker Desktop이 미리 설치되지 않았다면 자동으로 설치를 안내합니다."
echo

##################################
# 1. 시스템 업데이트 & 필수 패키지 설치 (Python, pip 포함)
##################################
echo "[단계 1] 필수 패키지 설치..."

# Homebrew 설치 확인
if ! command -v brew &> /dev/null; then
  echo " - Homebrew가 설치되어 있지 않습니다. 설치를 진행합니다..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
  echo " - Homebrew가 이미 설치되어 있습니다."
fi

# 필수 패키지 설치
brew install curl git jq python3 coreutils gnu-sed

# Python 관련 패키지 설치 / 업그레이드
echo "[안내] pip3 업그레이드 & infernet-cli / infernet-client 설치"
pip3 install --upgrade pip
pip3 install infernet-cli infernet-client

##################################
# 2. Docker 설치 확인
##################################
echo "[단계 2] Docker 설치 확인..."
if command -v docker &> /dev/null; then
  echo " - Docker가 이미 설치되어 있습니다."
else
  echo " - Docker가 설치되어 있지 않습니다."
  echo " - Docker Desktop을 설치하려면 다음 URL을 방문하세요: https://www.docker.com/products/docker-desktop"
  echo " - Docker Desktop 설치 후 이 스크립트를 다시 실행하세요."
  exit 1
fi

echo "[확인] Docker 버전:"
docker --version

##################################
# 3. Docker Compose 설치 확인
##################################
echo "[단계 3] Docker Compose 설치 확인..."
if ! docker compose version &> /dev/null; then
  echo " - Docker Compose가 설치되어 있지 않습니다. Docker Desktop에는 일반적으로 포함되어 있습니다."
  echo " - Docker Desktop을 확인하고 다시 시도하세요."
  exit 1
else
  echo " - Docker Compose가 이미 설치되어 있습니다."
fi

echo "[확인] Docker Compose 버전:"
docker compose version

##################################
# 4. Foundry 설치 & 환경변수 설정
##################################
echo
echo "[단계 4] Foundry 설치 (옵션)"
# anvil 실행 중이면 종료
if pgrep anvil &>/dev/null; then
  echo "[경고] anvil 프로세스가 실행 중입니다. Foundry 업데이트를 위해 종료합니다."
  pkill anvil
  sleep 2
fi

cd ~ || exit 1
mkdir -p foundry
cd foundry
curl -L https://foundry.paradigm.xyz | bash

# 설치 / 업데이트
$HOME/.foundry/bin/foundryup

# PATH에 ~/.foundry/bin 추가
if [[ ":$PATH:" != *":$HOME/.foundry/bin:"* ]]; then
  export PATH="$HOME/.foundry/bin:$PATH"
fi

echo "[확인] forge 버전:"
forge --version || {
  echo "[오류] forge 명령을 찾지 못했습니다. ~/.foundry/bin이 PATH에 없거나 설치 실패일 수 있습니다."
  exit 1
}

echo "[안내] Foundry 설치 및 환경 변수 설정이 완료되었습니다."
cd ~ || exit 1

##################################
# 5. infernet-container-starter 클론
##################################
echo
echo "[단계 5] infernet-container-starter 클론..."
git clone https://github.com/ritual-net/infernet-container-starter
cd infernet-container-starter || { echo "[오류] 디렉토리 이동 실패"; exit 1; }

##################################
# 6. screen 세션에서 초기 배포(make deploy-container)
##################################
echo "[단계 6] screen -S ritual 세션에서 컨테이너 배포 시작..."
sleep 1
screen -S ritual -dm bash -c '
project=hello-world make deploy-container;
exec bash
'

echo "[안내] screen 세션(ritual)에서 배포 작업을 진행 중(백그라운드)."

##################################
# 7. 사용자 입력 (Private Key)
##################################
echo
echo "[단계 7] Ritual Node 구성 파일 수정..."

read -p "Enter your Private Key (0x...): " PRIVATE_KEY

# 기본 설정
RPC_URL="https://base.drpc.org"
RPC_URL_SUB="https://mainnet.base.org/"
# Registry 주소 교체
REGISTRY="0x3B1554f346DFe5c482Bb4BA31b880c1C18412170"
SLEEP=3
START_SUB_ID=160000
BATCH_SIZE=50  # public RPC 시 권장
TRAIL_HEAD_BLOCKS=3
INFERNET_VERSION="1.4.0"  # infernet 이미지 태그

##################################
# 8. config.json / Deploy.s.sol / docker-compose.yaml / Makefile 수정
##################################

# GNU sed 사용
GSED="gsed"
if ! command -v gsed &> /dev/null; then
  echo "[경고] GNU sed(gsed)가 설치되어 있지 않아 기본 sed를 사용합니다."
  GSED="sed -i ''"
else
  GSED="gsed -i"
fi

# 8.1 deploy/config.json 수정
$GSED "s|\"registry_address\": \".*\"|\"registry_address\": \"$REGISTRY\"|" deploy/config.json
$GSED "s|\"private_key\": \".*\"|\"private_key\": \"$PRIVATE_KEY\"|" deploy/config.json
$GSED "s|\"sleep\": [0-9]*|\"sleep\": $SLEEP|" deploy/config.json
$GSED "s|\"starting_sub_id\": [0-9]*|\"starting_sub_id\": $START_SUB_ID|" deploy/config.json
$GSED "s|\"batch_size\": [0-9]*|\"batch_size\": $BATCH_SIZE|" deploy/config.json
$GSED "s|\"trail_head_blocks\": [0-9]*|\"trail_head_blocks\": $TRAIL_HEAD_BLOCKS|" deploy/config.json
$GSED 's|"rpc_url": ".*"|"rpc_url": "https://mainnet.base.org"|' deploy/config.json
$GSED 's|"rpc_url": ".*"|"rpc_url": "https://mainnet.base.org"|' projects/hello-world/container/config.json


# 8.2 projects/hello-world/container/config.json
$GSED "s|\"registry_address\": \".*\"|\"registry_address\": \"$REGISTRY\"|" projects/hello-world/container/config.json
$GSED "s|\"private_key\": \".*\"|\"private_key\": \"$PRIVATE_KEY\"|" projects/hello-world/container/config.json
$GSED "s|\"sleep\": [0-9]*|\"sleep\": $SLEEP|" projects/hello-world/container/config.json
$GSED "s|\"starting_sub_id\": [0-9]*|\"starting_sub_id\": $START_SUB_ID|" projects/hello-world/container/config.json
$GSED "s|\"batch_size\": [0-9]*|\"batch_size\": $BATCH_SIZE|" projects/hello-world/container/config.json
$GSED "s|\"trail_head_blocks\": [0-9]*|\"trail_head_blocks\": $TRAIL_HEAD_BLOCKS|" projects/hello-world/container/config.json

# 8.3 Deploy.s.sol 수정
$GSED "s|\(registry\s*=\s*\).*|\1$REGISTRY;|" projects/hello-world/contracts/script/Deploy.s.sol
$GSED "s|\(RPC_URL\s*=\s*\).*|\1\"$RPC_URL\";|" projects/hello-world/contracts/script/Deploy.s.sol

# node 이미지를 macOS와 호환되는 버전으로 설정
echo "[안내] 노드 이미지를 macOS 호환 버전(v1.4.0)으로 수정..."
# v1.4.0 버전 사용
$GSED 's|ritualnetwork/infernet-node:[^"]*|ritualnetwork/infernet-node:latest-gpu|' deploy/docker-compose.yaml

# 8.5 Makefile 수정 (sender, RPC_URL)
MAKEFILE_PATH="projects/hello-world/contracts/Makefile"
$GSED "s|^sender := .*|sender := $PRIVATE_KEY|"  "$MAKEFILE_PATH"
$GSED "s|^RPC_URL := .*|RPC_URL := $RPC_URL|"    "$MAKEFILE_PATH"

##################################
# 9. 컨테이너 재시작
##################################
echo
echo "[단계 9] docker compose down & up..."
docker compose -f deploy/docker-compose.yaml down

# infernet-node 이미지 pull 시도 (macOS 호환성을 위해 명시적으로 이미지 미리 pull)
echo "[안내] macOS 호환 이미지 준비 중..."
docker pull ritualnetwork/infernet-node:latest-gpu
docker pull ritualnetwork/hello-world-infernet:latest

# 컨테이너 시작
docker compose -f deploy/docker-compose.yaml up -d

echo
echo "[안내] 컨테이너가 백그라운드(-d)에서 실행 중입니다."
echo "docker ps 로 상태를 확인하세요. logs: docker logs infernet-node"

##################################
# 10. Forge 라이브러리 설치 (충돌 제거)
##################################
echo
echo "[단계 10] Forge install (프로젝트 종속성)"
cd ~/infernet-container-starter/projects/hello-world/contracts || exit 1
rm -rf lib/forge-std
rm -rf lib/infernet-sdk

forge install --no-commit foundry-rs/forge-std
forge install --no-commit ritual-net/infernet-sdk

##################################
# 11. 컨테이너 재시작
##################################
echo
echo "[단계 11] docker compose 재시작..."
cd ~/infernet-container-starter || exit 1
docker compose -f deploy/docker-compose.yaml down

# 컨테이너 시작
docker compose -f deploy/docker-compose.yaml up -d

# 상태 확인
echo "[안내] infernet-node 로그 확인: docker logs infernet-node"
echo "[안내] 컨테이너 상태 확인: docker ps"

##################################
# 12. 프로젝트 컨트랙트 배포 + 주소 추출
##################################
echo
echo "[단계 12] 프로젝트 컨트랙트 배포..."
DEPLOY_OUTPUT=$(project=hello-world make deploy-contracts 2>&1)
echo "$DEPLOY_OUTPUT"

# 새로 배포된 컨트랙트 주소 (예: Deployed SaysHello:  0x...)
NEW_ADDR=$(echo "$DEPLOY_OUTPUT" | grep -o 'Deployed SaysHello:[[:space:]]*0x[0-9a-fA-F]\{40\}' | grep -o '0x[0-9a-fA-F]\{40\}')
if [ -z "$NEW_ADDR" ]; then
  echo "[경고] 새 컨트랙트 주소를 찾지 못했습니다. 수동으로 CallContract.s.sol 수정해야 할 수 있음."
else
  echo "[안내] Deployed SaysHello 주소: $NEW_ADDR"
  # CallContract.s.sol에서 기존 주소를 새 주소로 교체
  # ex) SaysGM saysGm = SaysGM(0x13D69Cf7...); -> SaysGM saysGm = SaysGM(0xA529dB3c9...)
  $GSED "s|SaysGM saysGm = SaysGM(0x[0-9a-fA-F]\+);|SaysGM saysGm = SaysGM($NEW_ADDR);|" \
      projects/hello-world/contracts/script/CallContract.s.sol

  # call-contract
  echo
  echo "[단계 12.2] 새 주소로 call-contract 실행..."
  project=hello-world make call-contract
fi

echo
echo "===== Ritual Node Setup Completed (macOS) ====="
