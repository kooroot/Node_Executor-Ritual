#!/usr/bin/env bash
#
# ritual_node_linux.sh
# Linux(Ubuntu 계열) 환경에서 Infernet(Ritual Node) 설치 & 세팅을 자동화하는 스크립트.
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

echo "===== Ritual Node Setup Script (Linux) ====="
echo "[안내] 본 스크립트는 Ubuntu 계열 환경을 가정하고 있습니다."
echo "      Docker가 미리 설치되지 않았다면 자동으로 설치를 진행합니다."
echo "      스크립트 실행 중 'sudo' 암호를 요구할 수 있습니다."
echo

##################################
# 1. 시스템 업데이트 & 필수 패키지 설치 (Python, pip 포함)
##################################
echo "[단계 1] 시스템 업데이트 및 패키지 설치..."
sudo apt update && sudo apt upgrade -y
sudo apt -qy install curl git jq lz4 build-essential screen python3 python3-pip

# Python 관련 패키지 설치 / 업그레이드
echo "[안내] pip3 업그레이드 & infernet-cli / infernet-client 설치"
pip3 install --upgrade pip
pip3 install infernet-cli infernet-client

##################################
# 2. Docker 설치 확인
##################################
echo "[단계 2] Docker 설치 확인..."
if command -v docker &> /dev/null; then
  echo " - Docker 이미 설치됨, 건너뜁니다."
else
  echo " - Docker 미설치 상태, 설치 진행..."
  sudo apt install -y docker.io
  sudo systemctl enable docker
  sudo systemctl start docker
fi

##################################
# 3. Docker Compose 설치 확인
##################################
echo "[단계 3] Docker Compose 설치 확인..."
if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
  echo " - docker compose 미설치, 설치 진행..."
  # 예시 버전: v2.29.2
  sudo curl -L "https://github.com/docker/compose/releases/download/v2.29.2/docker-compose-$(uname -s)-$(uname -m)" \
       -o /usr/local/bin/docker-compose
  sudo chmod +x /usr/local/bin/docker-compose

  DOCKER_CONFIG=${DOCKER_CONFIG:-$HOME/.docker}
  mkdir -p "$DOCKER_CONFIG/cli-plugins"
  curl -SL "https://github.com/docker/compose/releases/download/v2.20.2/docker-compose-linux-x86_64" \
      -o "$DOCKER_CONFIG/cli-plugins/docker-compose"
  chmod +x "$DOCKER_CONFIG/cli-plugins/docker-compose"
else
  echo " - docker compose(또는 docker-compose) 이미 설치됨, 건너뜁니다."
fi

echo "[확인] Docker Compose 버전:"
docker compose version || docker-compose version

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

# /usr/bin/forge 제거 (ZOE ERROR 방지)
if [ -f /usr/bin/forge ]; then
  echo "[안내] /usr/bin/forge 제거..."
  sudo rm /usr/bin/forge
fi

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
RPC_URL="https://mainnet.base.org/"
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

# 8.1 deploy/config.json 수정
sed -i "s|\"registry_address\": \".*\"|\"registry_address\": \"$REGISTRY\"|" deploy/config.json
sed -i "s|\"private_key\": \".*\"|\"private_key\": \"$PRIVATE_KEY\"|" deploy/config.json
sed -i "s|\"sleep\": [0-9]*|\"sleep\": $SLEEP|" deploy/config.json
sed -i "s|\"starting_sub_id\": [0-9]*|\"starting_sub_id\": $START_SUB_ID|" deploy/config.json
sed -i "s|\"batch_size\": [0-9]*|\"batch_size\": $BATCH_SIZE|" deploy/config.json
sed -i "s|\"trail_head_blocks\": [0-9]*|\"trail_head_blocks\": $TRAIL_HEAD_BLOCKS|" deploy/config.json

# 8.2 projects/hello-world/container/config.json
sed -i "s|\"registry_address\": \".*\"|\"registry_address\": \"$REGISTRY\"|" projects/hello-world/container/config.json
sed -i "s|\"private_key\": \".*\"|\"private_key\": \"$PRIVATE_KEY\"|" projects/hello-world/container/config.json
sed -i "s|\"sleep\": [0-9]*|\"sleep\": $SLEEP|" projects/hello-world/container/config.json
sed -i "s|\"starting_sub_id\": [0-9]*|\"starting_sub_id\": $START_SUB_ID|" projects/hello-world/container/config.json
sed -i "s|\"batch_size\": [0-9]*|\"batch_size\": $BATCH_SIZE|" projects/hello-world/container/config.json
sed -i "s|\"trail_head_blocks\": [0-9]*|\"trail_head_blocks\": $TRAIL_HEAD_BLOCKS|" projects/hello-world/container/config.json

# 8.3 Deploy.s.sol 수정
sed -i "s|\(registry\s*=\s*\).*|\1$REGISTRY;|" projects/hello-world/contracts/script/Deploy.s.sol
sed -i "s|\(RPC_URL\s*=\s*\).*|\1\"$RPC_URL\";|" projects/hello-world/contracts/script/Deploy.s.sol

# 8.4 docker-compose.yaml
sed -i "s|image: ritualnet/infernet:.*|image: ritualnet/infernet:$INFERNET_VERSION|" deploy/docker-compose.yaml
# node 이미지 latest
sed -i 's|ritualnetwork/infernet-node:[^"]*|ritualnetwork/infernet-node:latest|' deploy/docker-compose.yaml

# 8.5 Makefile 수정 (sender, RPC_URL)
MAKEFILE_PATH="projects/hello-world/contracts/Makefile"
sed -i "s|^sender := .*|sender := $PRIVATE_KEY|"  "$MAKEFILE_PATH"
sed -i "s|^RPC_URL := .*|RPC_URL := $RPC_URL|"    "$MAKEFILE_PATH"

##################################
# 9. 컨테이너 재시작
##################################
echo
echo "[단계 9] docker compose down & up..."
docker compose -f deploy/docker-compose.yaml down
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
docker compose -f deploy/docker-compose.yaml up -d
echo "[안내] infernet-node 로그 확인: docker logs infernet-node"

##################################
# 12. 프로젝트 컨트랙트 배포 + 주소 추출
##################################
echo
echo "[단계 12] 프로젝트 컨트랙트 배포..."
DEPLOY_OUTPUT=$(project=hello-world make deploy-contracts 2>&1)
echo "$DEPLOY_OUTPUT"

# 새로 배포된 컨트랙트 주소 (예: Deployed SaysHello:  0x...)
NEW_ADDR=$(echo "$DEPLOY_OUTPUT" | grep -oP 'Deployed SaysHello:\s+\K0x[0-9a-fA-F]{40}')
if [ -z "$NEW_ADDR" ]; then
  echo "[경고] 새 컨트랙트 주소를 찾지 못했습니다. 수동으로 CallContract.s.sol 수정해야 할 수 있음."
else
  echo "[안내] Deployed SaysHello 주소: $NEW_ADDR"
  # CallContract.s.sol에서 기존 주소를 새 주소로 교체
  # ex) SaysGM saysGm = SaysGM(0x13D69Cf7...); -> SaysGM saysGm = SaysGM(0xA529dB3c9...)
  sed -i "s|SaysGM saysGm = SaysGM(0x[0-9a-fA-F]\+);|SaysGM saysGm = SaysGM($NEW_ADDR);|" \
      projects/hello-world/contracts/script/CallContract.s.sol

  # call-contract
  echo
  echo "[단계 12.2] 새 주소로 call-contract 실행..."
  project=hello-world make call-contract
fi

echo
echo "===== Ritual Node Setup Completed (Linux) ====="
