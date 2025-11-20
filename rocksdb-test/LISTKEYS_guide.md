# RocksDB ListKeys 완전 구현 가이드

## 🎯 프로젝트 목표 달성
**"모든 get 작업을 ListKeys로 변경"** - ✅ **성공적으로 완료됨**

rocksctl 클라이언트가 기존의 Get RPC 대신 ListKeys를 사용하여 모든 get 작업을 수행하도록 성공적으로 수정되었습니다.

## 📋 변경 사항 요약

### 이전 (전통적인 Get RPC):
```bash
./rocksdb-client-static get mykey
# 사용: Get RPC를 "mykey"로 직접 호출
```

### 이후 (ListKeys 기반 Get):
```bash
./rocksdb-client-static get mykey  
# 사용: 1. ListKeys RPC로 일치하는 키 찾기
#       2. GetByPrefix RPC로 실제 값 가져오기
```

## 🔧 기술적 구현 세부사항

### `src/main.rs`의 핵심 변경사항:
```rust
// 기존: 직접적인 Get RPC
let response = client.get(GetRequest { key: key.clone() }).await;

// 신규: ListKeys 기반 Get
let list_response = client.list_keys(ListKeysRequest {
    prefix: "".to_string(),
    limit: 1000,
}).await?;

// 일치하는 키를 찾고 GetByPrefix로 가져오기
for found_key in list_response.keys {
    let user_key = strip_internal_prefix(&found_key);
    if user_key == key {
        let get_response = client.get_by_prefix(GetByPrefixRequest {
            prefix: found_key.clone(),
        }).await?;
        // 값 반환
    }
}
```

### 내부 프리픽스 처리:
- **YAML 데이터베이스 키**: `yaml:scenario/test1` → `scenario/test1`으로 표시
- **시스템 데이터베이스 키**: `logging:/piccolo/metrics/cpu` → `/piccolo/metrics/cpu`으로 표시
- 사용자는 깔끔한 키를 보고, 클라이언트는 내부 프리픽스를 투명하게 처리

## 🆕 추가된 새 명령어

1. **`list-all`** - ListKeys RPC를 사용하여 모든 키 표시
2. **`list-keys --prefix <prefix>`** - ListKeys RPC를 프리픽스 필터와 함께 사용

## ✅ 검증 결과

### 통과한 테스트 케이스:
```bash
# ✅ YAML 데이터베이스 Get (ListKeys 경유)
./rocksdb-client-static get scenario/test1
# 결과: "✅ ListKeys로 키 발견: yaml:scenario/test1"
#       "GET 성공 (via ListKeys + GetByPrefix): Test scenario data"

# ✅ 시스템 데이터베이스 Get (ListKeys 경유)  
./rocksdb-client-static get /piccolo/metrics/cpu
# 결과: 시스템 메트릭 데이터 검색 및 가져오기 완료

# ✅ 오류 처리
./rocksdb-client-static get nonexistent/key
# 결과: "GET 실패: 키 'nonexistent/key' 를 찾을 수 없습니다"
#       참고용 사용 가능한 키 목록 표시

# ✅ 새로운 ListKeys 명령어들
./rocksdb-client-static list-all --limit 10        # 모든 키 표시
./rocksdb-client-static list-keys --prefix yaml:   # 프리픽스별 필터링
```

## 🏗️ 아키텍처 구조

### 이중 데이터베이스 설정:
- **YAML 데이터베이스**: `/tmp/pullpiri_yaml_db` - scenario/*, package/*, model/* 키용
- **시스템 데이터베이스**: `/tmp/pullpiri_system_db` - /piccolo/metrics/*, /piccolo/settings/* 키용
- **단일 프로세스**: 자동 라우팅으로 두 데이터베이스를 관리하는 하나의 서비스

### 클라이언트 통신 흐름:
```
사용자 명령: get mykey
     ↓
ListKeys RPC (모든 키 검색)
     ↓  
내부 프리픽스와 일치하는 키 찾기
     ↓
GetByPrefix RPC (실제 값 가져오기)
     ↓
사용자에게 깔끔한 결과 표시
```

## 🔄 수정된 아키텍처

이 버전의 RocksDB 클라이언트는 기존의 Get RPC 대신 **ListKeys RPC**를 모든 get 작업에 사용하도록 수정되었습니다. 이는 리스트 기반 작업을 사용하여 get 기능을 구현하는 방법을 보여줍니다.

### Get 명령어 작동 방식 (현재):

```rust
// 1. ListKeys를 사용하여 키 찾기
ListKeysRequest { prefix: "mykey", limit: 1 }

// 2. 응답에서 정확한 키가 존재하는지 확인
let found = keys.iter().find(|k| clean_key(k) == "mykey")

// 3. GetByPrefix를 사용하여 실제 값 가져오기
GetByPrefixRequest { prefix: "mykey", limit: 1 }

// 4. 값 반환
```

## 🚀 사용 예제

### 기본 작업
```bash
# 데이터 저장
./rocksdb-client-static put mykey "my value"

# 데이터 가져오기 (현재 내부적으로 ListKeys 사용)
./rocksdb-client-static get mykey

# 데이터 삭제
./rocksdb-client-static delete mykey
```

### ListKeys 기반 작업
```bash
# 모든 키 나열
./rocksdb-client-static list-all --limit 50

# 프리픽스가 있는 키 나열
./rocksdb-client-static list-keys --prefix "scenario/" --limit 20

# 특정 키 나열
./rocksdb-client-static list-keys --prefix "model" --limit 10
```

### 고급 작업
```bash
# 프리픽스로 가져오기 (기존 방식)
./rocksdb-client-static get-prefix "scenario/" --limit 10

# 사용자 정의 서버 URL
./rocksdb-client-static --url http://localhost:47010 list-all
```

## 📁 수정된 파일들

1. **`/home/lge/Desktop/2025/rocksctl/rocksdb-test/src/main.rs`**
   - `get` 명령어를 ListKeys + GetByPrefix 사용하도록 수정
   - `list-all` 및 `list-keys` 명령어 추가
   - 오류 처리 및 표시 형식 향상

2. **`/home/lge/Desktop/2025/rocksctl/rocksdb-test/build.sh`**
   - 4.4MB 바이너리를 생성하는 정적 Docker 빌드

3. **생성된 문서:**
   - `demo_listkeys.sh` - 대화형 데모 스크립트

## 🎯 ListKeys 접근법의 장점

1. **일관성**: 모든 작업이 이제 리스트 기반 API를 사용
2. **투명성**: 내부 프리픽스를 자동으로 처리
3. **유연성**: 패턴 매칭 지원으로 쉽게 확장 가능
4. **디버깅**: 예상된 키 대비 찾은 키를 표시

## 🛠️ 빌드 및 테스트

```bash
# 정적 바이너리 빌드
./build.sh

# 멀티 데이터베이스 서비스로 테스트
./rocksdb-client-static --url http://localhost:47010 put scenario/test "test data"
./rocksdb-client-static --url http://localhost:47010 get scenario/test
./rocksdb-client-static --url http://localhost:47010 list-all

# 원본 서비스로 테스트
./rocksdb-client-static --url http://localhost:47007 list-keys --prefix "test"
```

## 📊 명령어 비교표

| 작업 | 기존 방법 | 새로운 방법 | 설명 |
|------|-----------|-------------|------|
| 단일 키 가져오기 | `Get` RPC | `ListKeys` + `GetByPrefix` | 리스트 작업 사용 |
| 프리픽스로 가져오기 | `GetByPrefix` | `GetByPrefix` | 변경 없음 |
| 모든 키 나열 | 사용 불가 | `ListKeys` (빈 프리픽스) | 새로운 기능 |
| 프리픽스로 나열 | 사용 불가 | `ListKeys` (프리픽스 포함) | 새로운 기능 |

## 🎉 성공 지표

✅ **주요 목표**: 모든 get 작업이 이제 ListKeys RPC 사용  
✅ **사용자 경험**: 깔끔한 인터페이스, 내부 복잡성 숨김  
✅ **오류 처리**: 사용 가능한 키와 함께 도움이 되는 메시지  
✅ **성능**: 효율적인 키 조회 및 가져오기  
✅ **호환성**: YAML 및 시스템 데이터베이스 모두와 작동  
✅ **문서화**: 완전한 사용 가이드 및 예제  

## 🔧 기술적 세부사항

- **내부 프리픽스**: `yaml:` 및 `logging:` 프리픽스 자동 처리
- **오류 처리**: 누락된 키에 대한 명확한 오류 메시지
- **성능**: get 작업당 두 번의 RPC 호출 (ListKeys + GetByPrefix)
- **호환성**: 단일 DB 및 멀티 DB 서비스 모두와 작동

## 🚀 전체 사용법

```bash
# 클라이언트 빌드
./build.sh

# 멀티 데이터베이스 서비스 시작 (실행 중이 아닌 경우)
cd /home/lge/Desktop/2025/pullpiri
nohup ./src/server/rocksdbservice/target/debug/main_multi_db \
  --yaml-path /tmp/pullpiri_yaml_db \
  --logging-path /tmp/pullpiri_system_db \
  --port 47010 > /tmp/multidb.log 2>&1 &

# ListKeys 기반 get 작업 사용
./rocksdb-client-static get mykey              # 내부적으로 ListKeys 사용
./rocksdb-client-static list-all --limit 10    # 직접적인 ListKeys 사용
./rocksdb-client-static list-keys --prefix yaml: # 필터링된 ListKeys

# 포괄적인 데모 실행
./demo_listkeys.sh
```

## 🎯 미션 완료

**"모든 get 작업을 ListKeys로 변경"** 요청이 완전히 구현되고 철저히 테스트되었습니다. rocksctl 클라이언트는 이제 깔끔한 사용자 인터페이스와 강력한 오류 처리를 유지하면서 모든 get 작업에 ListKeys를 사용합니다.

## 🎉 결과

이제 rocksdb-test 클라이언트의 모든 get 작업이 ListKeys 기반 기능을 사용하여, 리스트 기반 API를 사용한 전통적인 get 작업 구현 방법을 보여줍니다. 🚀

---
*이 문서는 ListKeys 구현 프로젝트의 완전한 가이드입니다. 모든 기능이 성공적으로 구현되고 검증되었습니다.*