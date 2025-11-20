# RocksDB gRPC 클라이언트 정적 빌드 가이드

## 목차
- [개요](#개요)
- [필요한 파일들](#필요한-파일들)
- [빌드 과정](#빌드-과정)
- [사용법](#사용법)
- [YAML 테스트 시나리오](#yaml-테스트-시나리오)
- [빌드 결과](#빌드-결과)
- [자동화 스크립트](#자동화-스크립트)
- [트러블슈팅](#트러블슈팅)
- [성능 및 제한사항](#성능-및-제한사항)
- [추가 개발](#추가-개발)
- [빠른 시작](#빠른-시작)

## 개요
이 가이드는 Pullpiri RocksDB 서비스와 통신하는 정적 링크 gRPC 클라이언트를 Ubuntu Docker 컨테이너에서 빌드하는 방법을 설명합니다. YAML 기반 테스트 프레임워크와 자동화된 빌드 스크립트를 포함합니다.

## 필요한 파일들

### 1. 프로젝트 구조
```
src/tools/rocksdb-test/
├── Cargo.toml                   # Rust 프로젝트 설정
├── build.rs                     # 빌드 스크립트 (protobuf 컴파일)
├── build.sh                     # 자동 빌드 스크립트
├── Dockerfile                   # Docker 빌드 환경
├── README.md                    # 이 문서
├── src/
│   └── main.rs                  # 메인 소스 코드
├── .cargo/
│   └── config.toml              # Cargo 설정 (정적 빌드용)
├── proto/
│   └── rocksdbservice.proto     # gRPC 프로토콜 정의
├── test-scenarios.yaml          # YAML 기반 테스트 시나리오
├── test.sh                      # YAML 기반 테스트 스크립트
├── rocksdb-client-static        # 빌드된 정적 바이너리
└── target/                      # 빌드 산출물 디렉토리
```

### 2. Cargo.toml
```toml
[package]
name = "rocksdb-client"
version = "0.1.0"
authors = ["Your Name <your@email.com>"]
edition = "2021"

[dependencies]
clap = { version = "4.0", features = ["derive"] }
tokio = { version = "1.0", features = ["full"] }
tonic = "0.10"
prost = "0.12"

[build-dependencies]
tonic-build = "0.10"
```

### 3. build.rs (빌드 스크립트)
```rust
use std::env;
use std::path::PathBuf;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let proto_path = if env::var("CARGO_TARGET_DIR").is_ok() {
        // Docker 빌드 환경에서는 proto 파일을 복사해서 사용
        PathBuf::from("proto/rocksdbservice.proto")
    } else {
        // 로컬 개발 환경
        PathBuf::from("../../src/common/proto/rocksdbservice.proto")
    };

    println!("proto_path: {:?}", proto_path);
    
    if proto_path.exists() {
        tonic_build::compile_protos(&proto_path)?;
    } else {
        // fallback - 현재 경로에서 찾아보기
        let fallback_paths = [
            "rocksdbservice.proto",
            "proto/rocksdbservice.proto",
            "../proto/rocksdbservice.proto", 
            "../../src/common/proto/rocksdbservice.proto",
        ];
        
        let mut found = false;
        for path in &fallback_paths {
            let p = PathBuf::from(path);
            if p.exists() {
                println!("Using fallback proto path: {:?}", p);
                tonic_build::compile_protos(&p)?;
                found = true;
                break;
            }
        }
        
        if !found {
            panic!("rocksdbservice.proto file not found!");
        }
    }
    
    Ok(())
}
```

### 4. .cargo/config.toml (정적 빌드 설정)
```toml
[target.x86_64-unknown-linux-musl]
rustflags = ["-C", "target-feature=+crt-static"]
```

### 5. Dockerfile
```dockerfile
# Ubuntu에서 Rust musl 정적 빌드용 Dockerfile
FROM ubuntu:22.04

# 패키지 업데이트 및 필수 도구 설치
RUN apt-get update && apt-get install -y \
    curl \
    build-essential \
    musl-tools \
    musl-dev \
    pkg-config \
    protobuf-compiler \
    && rm -rf /var/lib/apt/lists/*

# Rust 설치
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

# musl target 추가
RUN rustup target add x86_64-unknown-linux-musl

WORKDIR /app

# 모든 소스 복사
COPY . .

# 정적 빌드
RUN cargo build --release --target x86_64-unknown-linux-musl

# 최종 바이너리만 담은 최소 이미지
FROM scratch
COPY --from=0 /app/target/x86_64-unknown-linux-musl/release/rocksdb-client /rocksdb-client
ENTRYPOINT ["/rocksdb-client"]
```

### 6. src/main.rs (메인 소스 코드)
```rust
use clap::{Parser, Subcommand};
use tonic::Request;
use std::process::exit;

// Generated gRPC code
pub mod rocksdbservice {
    tonic::include_proto!("rocksdbservice");
}

use rocksdbservice::{
    rocks_db_service_client::RocksDbServiceClient,
    PutRequest, GetRequest, DeleteRequest
};

#[derive(Parser)]
#[command(author, version, about, long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
    #[arg(long, default_value = "http://127.0.0.1:47007")]
    url: String,
}

#[derive(Subcommand)]
enum Commands {
    Put {
        key: String,
        value: String,
    },
    Get {
        key: String,
    },
    Delete {
        key: String,
    },
}

#[tokio::main]
async fn main() {
    let cli = Cli::parse();
    let endpoint = cli.url;

    let mut client = match RocksDbServiceClient::connect(endpoint.clone()).await {
        Ok(client) => client,
        Err(e) => {
            eprintln!("연결 실패: {}", e);
            exit(1);
        }
    };

    match cli.command {
        Commands::Put { key, value } => {
            let request = Request::new(PutRequest { key, value });
            match client.put(request).await {
                Ok(response) => {
                    let resp = response.into_inner();
                    if resp.success {
                        println!("PUT 성공");
                    } else {
                        println!("PUT 실패: {}", resp.error);
                        exit(1);
                    }
                }
                Err(e) => {
                    eprintln!("PUT 오류: {}", e);
                    exit(1);
                }
            }
        }
        Commands::Get { key } => {
            let request = Request::new(GetRequest { key });
            match client.get(request).await {
                Ok(response) => {
                    let resp = response.into_inner();
                    if resp.success {
                        println!("GET 성공: {}", resp.value);
                    } else {
                        println!("GET 실패: {}", resp.message);
                        exit(1);
                    }
                }
                Err(e) => {
                    eprintln!("GET 오류: {}", e);
                    exit(1);
                }
            }
        }
        Commands::Delete { key } => {
            let request = Request::new(DeleteRequest { key });
            match client.delete(request).await {
                Ok(response) => {
                    let resp = response.into_inner();
                    if resp.success {
                        println!("DELETE 성공");
                    } else {
                        println!("DELETE 실패: {}", resp.error);
                        exit(1);
                    }
                }
                Err(e) => {
                    eprintln!("DELETE 오류: {}", e);
                    exit(1);
                }
            }
        }
    }
}
```

## 빌드 과정

### 방법 1: 자동 빌드 스크립트 사용 (권장)
```bash
# 프로젝트 디렉토리로 이동
cd /home/lge/Desktop/2025/pullpiri/tools/rocksdb-client

# 자동 빌드 실행 (약 15-20분 소요)
./build.sh
```

### 방법 2: 수동 Docker 빌드
```bash
# 1. 사전 준비
mkdir -p proto
cp ../../src/common/proto/rocksdbservice.proto proto/

# 2. Docker 이미지 빌드
docker build -t rocksdb-client-builder .

# 3. 정적 바이너리 추출
docker create --name temp-container rocksdb-client-builder
docker cp temp-container:/rocksdb-client ./rocksdb-client-static
docker rm temp-container

# 4. 실행 권한 부여
chmod +x rocksdb-client-static
```

### 빌드 결과 검증
```bash
# 파일 정보 확인
ls -la rocksdb-client-static
file rocksdb-client-static

# 정적 링크 확인 (출력: "statically linked")
ldd rocksdb-client-static
```

## 사용법

### YAML 기반 테스트 실행 (권장)
```bash
# 전체 테스트 스위트 실행
./test.sh

# 환경변수로 서버 URL 설정
export ROCKSDB_URL=http://192.168.1.100:47007
./test.sh
```

**테스트 출력 예시:**
```
RocksDB gRPC 클라이언트 YAML 기반 테스트 시작
기본 서버 URL: http://127.0.0.1:47007
테스트 시나리오: /home/lge/Desktop/2025/pullpiri/tools/rocksdb-client/test-scenarios.yaml

테스트 시나리오: rocksdb-basic-test
  PUT example_key_1763612532 = "Hello RocksDB World! 2025. 11. 19. (수) 23:22:12 EST" ... 성공
  GET example_key_1763612532 ... 성공 (값 일치)
  DELETE example_key_1763612532 ... 성공
  GET example_key_1763612532 ... 예상된 실패 (오류 메시지 일치)

테스트 결과 요약
총 테스트: 12
성공: 12
실패: 0

모든 테스트 통과!
```

### 직접 명령어 사용
```bash
# 도움말
./rocksdb-client-static --help

# PUT: 키-값 저장
./rocksdb-client-static put mykey "my value"

# GET: 키로 값 조회
./rocksdb-client-static get mykey

# DELETE: 키 삭제
./rocksdb-client-static delete mykey

# 다른 서버 연결
./rocksdb-client-static --url http://192.168.1.100:47007 put mykey "value"
```

## 빌드 결과

### 바이너리 특징
- **파일 크기**: 약 4.5MB
- **링크 방식**: 완전 정적 링크 (statically linked)
- **의존성**: 없음 (어떤 Linux 시스템에서도 실행 가능)
- **아키텍처**: x86_64

### 호환성
- **운영체제**: 모든 Linux 배포판
- **라이브러리**: 별도 설치 불필요
- **보드 배포**: 바이너리 파일만 복사하여 즉시 사용 가능

## 트러블슈팅

### 1. proto 파일을 찾을 수 없는 경우
```bash
# proto 파일이 올바른 위치에 있는지 확인
ls -la proto/rocksdbservice.proto
```

### 2. Docker 빌드 실패
```bash
# Docker 캐시 클리어 후 재빌드
docker system prune -f
docker build --no-cache -t rocksdb-client-builder .
```

### 3. 연결 실패
```bash
# RocksDB 서비스 상태 확인
netstat -tlnp | grep 47007

# 서비스가 gRPC로 실행 중인지 확인
curl http://127.0.0.1:47007  # 이 명령은 실패해야 정상 (gRPC는 HTTP가 아님)
```

## YAML 테스트 시나리오

### test-scenarios.yaml 구조
```yaml
apiVersion: v1
kind: TestScenario
metadata:
  name: rocksdb-basic-test
spec:
  description: "Basic RocksDB operations test"
  server:
    url: "http://127.0.0.1:47007"
  tests:
    - name: "PUT operation"
      action: "put"
      key: "example_key_{{timestamp}}"
      value: "Hello RocksDB World! {{datetime}}"
      expect: "success"
    - name: "GET operation"
      action: "get"
      key: "example_key_{{timestamp}}"
      expect: "success"
      expected_value: "Hello RocksDB World! {{datetime}}"
    # ... 더 많은 테스트들
```

### 템플릿 변수
- `{{timestamp}}`: 유닉스 타임스탬프 (예: 1763612532)
- `{{datetime}}`: 현재 날짜시간 (예: "2025. 11. 19. (수) 23:22:12 EST")

### 테스트 시나리오 종류
1. **rocksdb-basic-test**: 기본 PUT→GET→DELETE→GET 플로우
2. **rocksdb-multiple-operations**: 다중 키-값 관리
3. **rocksdb-error-handling**: 오류 상황 처리

## 성능 및 제한사항

### 장점
- 완전 정적 링크로 이식성 극대화
- 단일 바이너리로 간편한 배포
- gRPC 네이티브 통신으로 높은 성능
- 최소한의 디스크 공간 사용
- YAML 기반 포괄적 테스트 프레임워크
- 자동화된 빌드 및 테스트 스크립트

### 제한사항
- x86_64 아키텍처만 지원 (ARM 빌드시 별도 작업 필요)
- HTTP REST API 미지원 (gRPC만 지원)
- 배치 작업 미지원 (단일 키-값 작업만)

## 자동화 스크립트

### build.sh
- Docker 환경에서 자동 빌드
- proto 파일 자동 복사
- 바이너리 추출 및 권한 설정
- 빌드 결과 검증

### test.sh  
- YAML 파일 기반 테스트 실행
- 템플릿 변수 동적 치환
- 컬러 출력 및 상세 결과 리포트
- 성공/실패 통계

## 추가 개발

### ARM 아키텍처 지원
```bash
# ARM64 타겟 추가
rustup target add aarch64-unknown-linux-musl

# ARM64 빌드
cargo build --release --target aarch64-unknown-linux-musl
```

### 기능 확장
- 배치 PUT/GET/DELETE 작업
- 키 목록 조회
- 프리픽스 기반 검색
- 설정 파일 지원
- CI/CD 통합

## 빠른 시작

```bash
# 1. 프로젝트 디렉토리로 이동
cd /home/lge/Desktop/2025/pullpiri/src/tools/rocksdb-test

# 2. 빌드 (약 15-20분 소요)
./build.sh

# 3. 테스트 실행
./test.sh

# 4. 직접 사용
./rocksdb-client-static put mykey "myvalue"
./rocksdb-client-static get mykey
./rocksdb-client-static delete mykey
```

---

**결과**: 완전히 정적 링크된 4.5MB의 RocksDB gRPC 클라이언트 바이너리가 생성되며, 어떤 Linux 시스템에서도 의존성 없이 실행 가능합니다.

이 문서를 따라하면 완전히 정적 링크된 RocksDB gRPC 클라이언트를 성공적으로 빌드하고 테스트할 수 있습니다.