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