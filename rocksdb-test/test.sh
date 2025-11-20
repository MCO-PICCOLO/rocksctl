#!/bin/bash
# RocksDB gRPC 클라이언트 YAML 기반 테스트 스크립트

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLIENT="$SCRIPT_DIR/rocksdb-client-static"
YAML_FILE="${1:-$SCRIPT_DIR/test-scenarios.yaml}"

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

# Check if client exists
if [[ ! -f "$CLIENT" ]]; then
    echo -e "${RED}오류: $CLIENT 파일을 찾을 수 없습니다${NC}"
    echo "먼저 ./build.sh를 실행하여 클라이언트를 빌드하세요"
    exit 1
fi

# Check if YAML file exists
if [[ ! -f "$YAML_FILE" ]]; then
    echo -e "${RED}오류: $YAML_FILE 파일을 찾을 수 없습니다${NC}"
    exit 1
fi

# Function to run a single test
run_test() {
    local action="$1"
    local key="$2"
    local value="$3"
    local expect="$4"
    local expected_value="$5"
    local expected_error="$6"
    local url="$7"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    case "$action" in
        "put")
            echo -n "  PUT $key ... "
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
                    if [[ -n "$expected_error" && "$output" == *"$expected_error"* ]]; then
                        echo -e "${GREEN}예상된 실패 (오류 메시지 일치)${NC}"
                        PASSED_TESTS=$((PASSED_TESTS + 1))
                    else
                        echo -e "${RED}예상된 실패 (오류 메시지 불일치)${NC}"
                        FAILED_TESTS=$((FAILED_TESTS + 1))
                    fi
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
                    if [[ -n "$expected_value" ]]; then
                        # Extract the actual value (remove "GET 성공: " prefix)
                        actual_value="${output#GET 성공: }"
                        if [[ "$actual_value" == "$expected_value" ]]; then
                            echo -e "${GREEN}성공 (값 일치)${NC}"
                            PASSED_TESTS=$((PASSED_TESTS + 1))
                        else
                            echo -e "${RED}실패 (값 불일치)${NC}"
                            FAILED_TESTS=$((FAILED_TESTS + 1))
                        fi
                    else
                        echo -e "${GREEN}성공${NC}"
                        PASSED_TESTS=$((PASSED_TESTS + 1))
                    fi
                else
                    echo -e "${RED}예상과 다름 (성공했으나 실패 예상)${NC}"
                    FAILED_TESTS=$((FAILED_TESTS + 1))
                fi
            else
                if [[ "$expect" == "failure" ]]; then
                    if [[ -n "$expected_error" && "$output" == *"$expected_error"* ]]; then
                        echo -e "${GREEN}예상된 실패 (오류 메시지 일치)${NC}"
                        PASSED_TESTS=$((PASSED_TESTS + 1))
                    else
                        echo -e "${RED}예상된 실패 (오류 메시지 불일치)${NC}"
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
                    if [[ -n "$expected_error" && "$output" == *"$expected_error"* ]]; then
                        echo -e "${GREEN}예상된 실패 (오류 메시지 일치)${NC}"
                        PASSED_TESTS=$((PASSED_TESTS + 1))
                    else
                        echo -e "${RED}예상된 실패 (오류 메시지 불일치)${NC}"
                        FAILED_TESTS=$((FAILED_TESTS + 1))
                    fi
                else
                    echo -e "${RED}실패: $output${NC}"
                    FAILED_TESTS=$((FAILED_TESTS + 1))
                fi
            fi
            ;;
        "get-prefix")
            echo -n "  GET-PREFIX $key ... "
            if output=$("$CLIENT" --url "$url" get-prefix "$key" 2>&1); then
                if [[ "$expect" == "success" ]]; then
                    echo -e "${GREEN}성공${NC}"
                    # Show summary of results
                    echo "$output" | grep "개 키 발견\|조회됨" | sed 's/^/    /'
                    PASSED_TESTS=$((PASSED_TESTS + 1))
                else
                    echo -e "${RED}예상과 다름 (성공했으나 실패 예상)${NC}"
                    FAILED_TESTS=$((FAILED_TESTS + 1))
                fi
            else
                if [[ "$expect" == "failure" ]]; then
                    if [[ -n "$expected_error" && "$output" == *"$expected_error"* ]]; then
                        echo -e "${GREEN}예상된 실패 (오류 메시지 일치)${NC}"
                        PASSED_TESTS=$((PASSED_TESTS + 1))
                    else
                        echo -e "${RED}예상된 실패 (오류 메시지 불일치)${NC}"
                        FAILED_TESTS=$((FAILED_TESTS + 1))
                    fi
                else
                    echo -e "${RED}실패: $output${NC}"
                    FAILED_TESTS=$((FAILED_TESTS + 1))
                fi
            fi
            ;;
    esac
}

# Simple YAML parser for our test format
run_yaml_tests() {
    local yaml_file="$1"
    local server_url="http://127.0.0.1:47007"
    
    echo "RocksDB gRPC 클라이언트 YAML 기반 테스트 시작"
    echo "테스트 시나리오: $yaml_file"
    echo ""
    
    # Extract scenario name
    local scenario_name=$(grep "name:" "$yaml_file" | head -1 | sed 's/.*name: *//; s/"//g')
    echo -e "${YELLOW}테스트 시나리오: $scenario_name${NC}"
    
    # Extract server URL if present
    local yaml_url=$(grep "url:" "$yaml_file" | head -1 | sed 's/.*url: *//; s/"//g')
    if [[ -n "$yaml_url" ]]; then
        server_url="$yaml_url"
    fi
    
    # Parse tests using a simpler approach
    local in_tests=false
    local current_action=""
    local current_key=""
    local current_value=""
    local current_expect=""
    local current_expected_value=""
    local current_expected_error=""
    local collecting_value=false
    
    while IFS= read -r line; do
        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        
        # Check if we're in tests section
        if [[ "$line" =~ tests: ]]; then
            in_tests=true
            continue
        fi
        
        if [[ "$in_tests" == true ]]; then
            # New test item
            if [[ "$line" =~ -[[:space:]]*name: ]]; then
                # Execute previous test if we have complete data
                if [[ -n "$current_action" && -n "$current_key" ]]; then
                    run_test "$current_action" "$current_key" "$current_value" "$current_expect" "$current_expected_value" "$current_expected_error" "$server_url"
                fi
                
                # Reset for new test
                current_action=""
                current_key=""
                current_value=""
                current_expect=""
                current_expected_value=""
                current_expected_error=""
                collecting_value=false
                continue
            fi
            
            # Stop collecting multi-line value when we hit a new property
            if [[ "$collecting_value" == true && "$line" =~ ^[[:space:]]*[a-zA-Z]+: ]]; then
                collecting_value=false
            fi
            
            # Parse properties
            if [[ "$line" =~ action:[[:space:]]*\"?([^\"]+)\"? ]]; then
                current_action="${BASH_REMATCH[1]}"
                current_action="${current_action//\"/}"
            elif [[ "$line" =~ key:[[:space:]]*\"?([^\"]+)\"? ]]; then
                current_key="${BASH_REMATCH[1]}"
                current_key="${current_key//\"/}"
            elif [[ "$line" =~ value:[[:space:]]*\"([^\"]+)\" ]]; then
                current_value="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ value:[[:space:]]*\| ]]; then
                collecting_value=true
                current_value=""
            elif [[ "$collecting_value" == true ]]; then
                # Remove leading spaces but preserve relative indentation
                clean_line="${line#        }"
                if [[ -n "$current_value" ]]; then
                    current_value="${current_value}\n${clean_line}"
                else
                    current_value="${clean_line}"
                fi
            elif [[ "$line" =~ expect:[[:space:]]*\"?([^\"]+)\"? ]]; then
                current_expect="${BASH_REMATCH[1]}"
                current_expect="${current_expect//\"/}"
            elif [[ "$line" =~ expected_value:[[:space:]]*\"([^\"]+)\" ]]; then
                current_expected_value="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ expected_error:[[:space:]]*\"([^\"]+)\" ]]; then
                current_expected_error="${BASH_REMATCH[1]}"
            fi
        fi
    done < "$yaml_file"
    
    # Execute the last test
    if [[ -n "$current_action" && -n "$current_key" ]]; then
        run_test "$current_action" "$current_key" "$current_value" "$current_expect" "$current_expected_value" "$current_expected_error" "$server_url"
    fi
}

# Run the tests
run_yaml_tests "$YAML_FILE"

# Print summary
echo ""
echo -e "${BLUE}테스트 결과 요약${NC}"
echo "총 테스트: $TOTAL_TESTS"
echo -e "${GREEN}성공: $PASSED_TESTS${NC}"
echo -e "${RED}실패: $FAILED_TESTS${NC}"

if [[ $FAILED_TESTS -gt 0 ]]; then
    echo ""
    echo -e "${RED}${FAILED_TESTS}개의 테스트가 실패했습니다.${NC}"
    exit 1
else
    echo ""
    echo -e "${GREEN}모든 테스트가 성공했습니다!${NC}"
    exit 0
fi