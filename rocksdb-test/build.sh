#!/bin/bash
# RocksDB gRPC 클라이언트 정적 빌드 자동화 스크립트

set -e  # 오류 발생시 스크립트 중단

echo "RocksDB gRPC 클라이언트 정적 빌드 시작..."

# 현재 디렉토리 확인
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "작업 디렉토리: $SCRIPT_DIR"

# proto 파일 확인
echo "proto 파일 확인..."
if [ -f "$SCRIPT_DIR/proto/rocksdbservice.proto" ]; then
    echo "proto 파일 존재 확인 완료"
else
    echo "오류: proto 파일을 찾을 수 없습니다: $SCRIPT_DIR/proto/rocksdbservice.proto"
    echo "필요한 파일이 누락되었습니다."
    exit 1
fi

# Docker 이미지 빌드
echo "Docker 빌드 시작 (약 15-20분 소요)..."
docker build -t rocksdb-client-builder .

# 기존 바이너리 백업
if [ -f "$SCRIPT_DIR/rocksdb-client-static" ]; then
    echo "기존 바이너리 백업..."
    mv "$SCRIPT_DIR/rocksdb-client-static" "$SCRIPT_DIR/rocksdb-client-static.bak.$(date +%Y%m%d_%H%M%S)"
fi

# 정적 바이너리 추출
echo "정적 바이너리 추출..."
docker create --name temp-rocksdb-client rocksdb-client-builder
docker cp temp-rocksdb-client:/rocksdb-client "$SCRIPT_DIR/rocksdb-client-static"
docker rm temp-rocksdb-client

# 실행 권한 부여
chmod +x "$SCRIPT_DIR/rocksdb-client-static"

# 바이너리 정보 출력
echo "빌드 결과:"
ls -lh "$SCRIPT_DIR/rocksdb-client-static"
file "$SCRIPT_DIR/rocksdb-client-static"
echo -n "링크 정보: "
ldd "$SCRIPT_DIR/rocksdb-client-static" 2>/dev/null || echo "statically linked"

# 간단한 테스트
echo "바이너리 테스트..."
if "$SCRIPT_DIR/rocksdb-client-static" --help > /dev/null 2>&1; then
    echo "바이너리 실행 성공"
else
    echo "바이너리 실행 실패"
    exit 1
fi

echo ""
echo "빌드 완료!"
echo "생성된 파일: $SCRIPT_DIR/rocksdb-client-static"
echo ""
echo "사용법:"
echo "  $SCRIPT_DIR/rocksdb-client-static --help"
echo "  $SCRIPT_DIR/rocksdb-client-static put mykey \"my value\""
echo "  $SCRIPT_DIR/rocksdb-client-static get mykey"
echo "  $SCRIPT_DIR/rocksdb-client-static delete mykey"
echo ""
echo "다른 서버 연결:"
echo "  $SCRIPT_DIR/rocksdb-client-static --url http://HOST_IP:47007 put mykey \"value\""