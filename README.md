# Ritual Node Setup (Linux)

이 저장소에는 **리눅스(Ubuntu 계열)** 환경에서 **Ritual Node**(Infernet) 설치와 설정을 자동화하는 스크립트(`ritual_node_linux.sh`)가 포함되어 있습니다.  
아래 스크립트는 다음 과정을 한 번에 처리합니다:

1. **Docker / Docker Compose** 설치 확인 및 자동 설치  
2. **Python3 / pip3** 설치 후 `infernet-cli`, `infernet-client` 설치  
3. **Foundry** 설치 (이미 anvil이 실행 중이면 자동 종료 후 업데이트)  
4. **infernet-container-starter** 리포지토리 클론  
5. `screen` 세션에서 초기 배포(`make deploy-container`) 수행  
6. **사용자에게 Private Key**(0x...)를 입력받은 뒤,  
7. `config.json`, `Deploy.s.sol`, `docker-compose.yaml`, `Makefile` 등을 자동 수정  
   - **Registry 주소**를 `0x3B1554f346DFe5c482Bb4BA31b880c1C18412170`로 설정  
   - **노드 이미지**를 `ritualnetwork/infernet-node:latest`로 변경  
   - 기타 `sleep`, `batch_size`, `RPC_URL` 등 값 변경  
8. 컨테이너(노드) 재시작 후 **Forge** 라이브러리를 설치  
9. 마지막으로 **프로젝트 컨트랙트 배포**(`make deploy-contracts`) → **새 컨트랙트 주소**를 추출 → `CallContract.s.sol`에 반영 → `make call-contract`로 최종 테스트

---

## 설치 및 실행 방법

1. 스크립트를 다운로드
  ```bash
  wget https://raw.githubusercontent.com/kooroot/Node_Executor-Ritual/refs/heads/main/ritual_node.sh
  ```

2. 실행 권한을 부여
  ```bash
  chmod +x ritual_node_linux.sh
  ```

3. 스크립트를 실행  
  ```bash
  ./ritual_node_linux.sh
  ```
   - 도중에 **Private Key**(`0x...`)를 묻는 입력란이 있으며,  
   - Docker/Foundry/infernet-container-starter 등이 자동 설치/클론/설정됩니다.  
   - 설치 과정에서 `sudo` 암호 입력이 필요할 수 있습니다.

4. 노드 작동 확인 및 등록
  [Basescan](https://basescan.org/)에서 노드를 구동한 주소를 검색
  <img width="1352" alt="image" src="https://github.com/user-attachments/assets/279035ed-322d-4d11-a248-df4d48c49dff" />
  Contract Creation 후 Say GM 메소드의 To 주소가 노드 주소입니다.
  Say GM까지 정상 작동했다면 [노드등록주소](https://basescan.org/address/0x8d871ef2826ac9001fb2e33fdd6379b6aabf449c#writeContract)에 접속하여 지갑을 연결한 후
  registerNode (0x672d7a0d) -> 약 1시간 후(Cooldown) -> activateNode (0x105ddd1d)순으로 진행합니다.
  <img width="1365" alt="image" src="https://github.com/user-attachments/assets/e2412e09-cc6a-4578-a142-bd1ca05e054f" />

---

## 주요 변경 사항 / 설정 파일

- **`deploy/config.json` / `projects/hello-world/container/config.json`**  
  - `registry_address`: `0x3B1554f346DFe5c482Bb4BA31b880c1C18412170`  
  - `private_key`: 사용자 입력값  
  - `sleep`, `batch_size`, `trail_head_blocks` 등 자동 치환  
- **`projects/hello-world/contracts/script/Deploy.s.sol`**  
  - `registry = 0x3B1554f346DFe5c482Bb4BA31b880c1C18412170;`  
  - `RPC_URL = "https://mainnet.base.org";`  
- **`deploy/docker-compose.yaml`**  
  - `image: ritualnet/infernet:<VERSION>` → `1.4.0`  
  - `ritualnetwork/infernet-node:latest`로 치환  
- **`projects/hello-world/contracts/Makefile`**  
  - `sender := <PRIVATE_KEY>`  
  - `RPC_URL := https://mainnet.base.org`

---

## 배포 후 테스트 (CallContract)

1. `make deploy-contracts` 명령으로 **SaysHello**(또는 **SaysGM**) 컨트랙트 주소를 추출  
2. `CallContract.s.sol` 안의 `SaysGM(0x...)` 주소를 **새 주소**로 바꿔치기  
3. `make call-contract` 실행 → **sayGM** 함수를 호출해 성공 여부 확인

---

## 문제 해결

- **Docker / Python / Foundry** 등의 설치 과정에서 에러가 발생하면 로그를 자세히 살펴보세요.  
- **config.json**에 설정된 `registry_address`, `private_key`, `sleep`, `batch_size` 값이 맞는지, Ritual 공식 문서를 재확인하세요.  
- 배포 시 **Gas** 또는 **Base 토큰** 잔고가 부족하면 revert가 발생할 수 있습니다.  
- 스크립트는 `grep -oP` 등을 사용하므로, Ubuntu 환경에서 **PCRE** 지원이 필요합니다.  
- Makefile / Deploy.s.sol / docker-compose.yaml 구조가 바뀌면 `sed` 정규식을 수정해야 합니다.

---

## 문의 / 이슈
- **Ritual Node** 자체 문의: [Ritual 공식 문서](https://docs.ritual.net/) 또는 커뮤니티  
- **스크립트** 관련 문의나 버그 제보: 본 저장소의 [Issues](../../issues) 탭에 등록해주세요.
- **텔레그램 채널**: [Telegram 공지방](https://t.me/web3_laborer)
