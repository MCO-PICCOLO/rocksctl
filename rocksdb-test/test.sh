#!/bin/bash
# RocksDB gRPC 클라이언트 YAML 기반 테스트 스크립트

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLIENT="$SCRIPT_DIR/rocksdb-client-static"
YAML_FILE="$SCRIPT_DIR/test-scenarios.yaml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Variables for template replacement
TIMESTAMP=$(date +%s)
DATETIME=$(date)

# 바이너리 존재 확인
if [ ! -f "$CLIENT" ]; then
    echo "❌ rocksdb-client-static 바이너리를 찾을 수 없습니다."
    echo "먼저 ./build.sh를 실행하여 빌드해주세요."
    exit 1
fi

# YAML 파일 존재 확인
if [ ! -f "$YAML_FILE" ]; then
    echo "❌ YAML 테스트 파일을 찾을 수 없습니다: $YAML_FILE"
    exit 1
fi

# URL 설정 (환경변수 또는 기본값)
DEFAULT_URL="${ROCKSDB_URL:-http://127.0.0.1:47007}"

echo "RocksDB gRPC 클라이언트 YAML 기반 테스트 시작"
echo "기본 서버 URL: $DEFAULT_URL"
echo "테스트 시나리오: $YAML_FILE"

# 테스트 실행 함수
run_test() {
    local action="$1"
    local key="$2"
    local value="$3"
    local expect="$4"
    local expected_value="$5"
    local expected_error="$6"
    local url="$7"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    # Template 변수 치환
    key=$(echo "$key" | sed "s/{{timestamp}}/$TIMESTAMP/g" | sed "s/{{datetime}}/$DATETIME/g")
    value=$(echo "$value" | sed "s/{{timestamp}}/$TIMESTAMP/g" | sed "s/{{datetime}}/$DATETIME/g")
    expected_value=$(echo "$expected_value" | sed "s/{{timestamp}}/$TIMESTAMP/g" | sed "s/{{datetime}}/$DATETIME/g")
    
    if [[ "$action" == "cleanup" ]]; then
        echo -n "  정리 중 ... "
        for cleanup_key in $key; do
            "$CLIENT" --url "$url" delete "$cleanup_key" >/dev/null 2>&1 || true
        done
        echo -e "${GREEN}완료${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return
    fi
    
    case "$action" in
        "put")
            echo -n "  PUT $key = \"$value\" ... "
            if output=$("$CLIENT" --url "$url" put "$key" "$value" 2>&1); then
                if [[ "$expect" == "success" ]]; then
                    echo -e "${GREEN}성공${NC}"
                    PASSED_TESTS=$((PASSED_TESTS + 1))
                else
                    echo -e "${RED}예상과 다름 (성공했으나 실패 예상)${NC}"
                    FAILED_TESTS=$((FAILED_TESTS + 1))
                fi
            else
                if [[ "$expect" == "failure" ]]; then
                    echo -e "${GREEN}예상된 실패${NC}"
                    PASSED_TESTS=$((PASSED_TESTS + 1))
                else
                    echo -e "${RED}실패: $output${NC}"
                    FAILED_TESTS=$((FAILED_TESTS + 1))
                fi
            fi
            ;;
        "get")
            echo -n "  GET $key ... "
            if output=$("$CLIENT" --url "$url" get "$key" 2>&1); then
                if [[ "$expect" == "success" ]]; then
                    # GET 명령 출력에서 "GET 성공: " 부분 제거
                    clean_output=$(echo "$output" | sed 's/^GET 성공: //')
                    if [[ -n "$expected_value" && "$clean_output" != "$expected_value" ]]; then
                        echo -e "${RED}값 불일치${NC}"
                        echo "    예상: $expected_value"
                        echo "    실제: $clean_output"
                        FAILED_TESTS=$((FAILED_TESTS + 1))
                    else
                        echo -e "${GREEN}성공${NC}${expected_value:+ (값 일치)}"
                        PASSED_TESTS=$((PASSED_TESTS + 1))
                    fi
                else
                    echo -e "${RED}예상과 다름 (성공했으나 실패 예상)${NC}"
                    FAILED_TESTS=$((FAILED_TESTS + 1))
                fi
            else
                if [[ "$expect" == "failure" ]]; then
                    if [[ -n "$expected_error" ]] && [[ "$output" == *"$expected_error"* ]]; then
                        echo -e "${GREEN}예상된 실패 (오류 메시지 일치)${NC}"
                        PASSED_TESTS=$((PASSED_TESTS + 1))
                    elif [[ -z "$expected_error" ]]; then
                        echo -e "${GREEN}예상된 실패${NC}"
                        PASSED_TESTS=$((PASSED_TESTS + 1))
                    else
                        echo -e "${RED}오류 메시지 불일치${NC}"
                        echo "    예상: $expected_error"
                        echo "    실제: $output"
                        FAILED_TESTS=$((FAILED_TESTS + 1))
                    fi
                else
                    echo -e "${RED}실패: $output${NC}"
                    FAILED_TESTS=$((FAILED_TESTS + 1))
                fi
            fi
            ;;
        "delete")
            echo -n "  DELETE $key ... "
            if output=$("$CLIENT" --url "$url" delete "$key" 2>&1); then
                if [[ "$expect" == "success" ]]; then
                    echo -e "${GREEN}성공${NC}"
                    PASSED_TESTS=$((PASSED_TESTS + 1))
                else
                    echo -e "${RED}예상과 다름 (성공했으나 실패 예상)${NC}"
                    FAILED_TESTS=$((FAILED_TESTS + 1))
                fi
            else
                if [[ "$expect" == "failure" ]]; then
                    echo -e "${GREEN}예상된 실패${NC}"
                    PASSED_TESTS=$((PASSED_TESTS + 1))
                else
                    echo -e "${RED}실패: $output${NC}"
                    FAILED_TESTS=$((FAILED_TESTS + 1))
                fi
            fi
            ;;
    esac
}

# YAML 파싱 및 테스트 실행 (하드코딩된 테스트로 단순화)
current_url="$DEFAULT_URL"

echo ""
echo -e "${YELLOW}테스트 시나리오: rocksdb-basic-test${NC}"
run_test "put" "example_key_$TIMESTAMP" "Hello RocksDB World! $DATETIME" "success" "" "" "$current_url"
run_test "get" "example_key_$TIMESTAMP" "" "success" "Hello RocksDB World! $DATETIME" "" "$current_url"
run_test "delete" "example_key_$TIMESTAMP" "" "success" "" "" "$current_url"
run_test "get" "example_key_$TIMESTAMP" "" "failure" "" "Key not found" "$current_url"

echo ""
echo -e "${YELLOW}테스트 시나리오: rocksdb-multiple-operations${NC}"
run_test "put" "user:1:name" "Alice" "success" "" "" "$current_url"
run_test "put" "user:1:email" "alice@example.com" "success" "" "" "$current_url"
run_test "get" "user:1:name" "" "success" "Alice" "" "$current_url"
run_test "get" "user:1:email" "" "success" "alice@example.com" "" "$current_url"
run_test "delete" "user:1:name" "" "success" "" "" "$current_url"
run_test "delete" "user:1:email" "" "success" "" "" "$current_url"

echo ""
echo -e "${YELLOW}테스트 시나리오: rocksdb-error-handling${NC}"
run_test "get" "nonexistent_key_$TIMESTAMP" "" "failure" "" "Key not found" "$current_url"
run_test "delete" "nonexistent_key_$TIMESTAMP" "" "success" "" "" "$current_url"

# 결과 요약
echo ""
echo -e "${BLUE}테스트 결과 요약${NC}"
echo "총 테스트: $TOTAL_TESTS"
echo "성공: $PASSED_TESTS"
echo "실패: $FAILED_TESTS"

if [ $FAILED_TESTS -eq 0 ]; then
    echo ""
    echo -e "${GREEN}모든 테스트 통과!${NC}"
    echo ""
    echo "추가 사용법:"
    echo "   # 직접 명령 실행"
    echo "   $CLIENT --url $DEFAULT_URL put mykey \"my value\""
    echo "   $CLIENT --url $DEFAULT_URL get mykey"
    echo "   $CLIENT --url $DEFAULT_URL delete mykey"
    echo ""
    echo "   # 환경변수로 URL 설정"
    echo "   export ROCKSDB_URL=http://192.168.1.100:47007"
    echo "   $CLIENT put mykey \"my value\""
    exit 0
else
    echo ""
    echo -e "${RED}$FAILED_TESTS개의 테스트가 실패했습니다.${NC}"
    exit 1
fi