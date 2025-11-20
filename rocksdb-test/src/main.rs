use clap::{Parser, Subcommand};
use tonic::Request;
use std::process::exit;

// Generated gRPC code
pub mod rocksdbservice {
    tonic::include_proto!("rocksdbservice");
}

use rocksdbservice::{
    rocks_db_service_client::RocksDbServiceClient,
    PutRequest, GetRequest, DeleteRequest, GetByPrefixRequest, ListKeysRequest
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
    GetPrefix {
        prefix: String,
        #[arg(long, default_value = "100")]
        limit: i32,
    },
    /// List all keys (uses ListKeys RPC)
    ListAll {
        #[arg(long, default_value = "100")]
        limit: i32,
    },
    /// List keys with prefix (uses ListKeys RPC)
    ListKeys {
        #[arg(long, default_value = "")]
        prefix: String,
        #[arg(long, default_value = "100")]
        limit: i32,
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
            // 🔄 Rollback: Use direct Get RPC (original behavior)
            let request = Request::new(GetRequest { key: key.clone() });
            
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
        Commands::GetPrefix { prefix, limit } => {
            let request = Request::new(GetByPrefixRequest { prefix: prefix.clone(), limit });
            match client.get_by_prefix(request).await {
                Ok(response) => {
                    let resp = response.into_inner();
                    if resp.pairs.is_empty() {
                        println!("프리픽스 '{}' 와 일치하는 키를 찾을 수 없습니다", prefix);
                    } else {
                        println!("프리픽스 '{}' 검색 결과: {}개 키 발견", prefix, resp.total_count);
                        let pairs_count = resp.pairs.len();
                        println!("────────────────────────────────────────");
                        for pair in resp.pairs {
                            println!("키: {}", pair.key);
                            if pair.value.len() > 200 {
                                println!("값: {}... ({} bytes)", &pair.value[..200], pair.value.len());
                            } else {
                                println!("값: {}", pair.value);
                            }
                            println!("────────────────────────────────────────");
                        }
                        println!("총 {}개 키-값 쌍 조회됨", pairs_count);
                    }
                }
                Err(e) => {
                    eprintln!("GET_PREFIX 오류: {}", e);
                    exit(1);
                }
            }
        }
        Commands::ListAll { limit } => {
            println!("🔍 모든 키 조회 중 (limit: {})...", limit);
            
            let request = Request::new(ListKeysRequest { 
                prefix: "".to_string(), // Empty prefix to get all keys
                limit 
            });
            
            match client.list_keys(request).await {
                Ok(response) => {
                    let resp = response.into_inner();
                    if resp.keys.is_empty() {
                        println!("저장된 키가 없습니다");
                    } else {
                        println!("전체 키 목록: {}개 키 발견", resp.total_count);
                        println!("────────────────────────────────────────");
                        for (i, key) in resp.keys.iter().enumerate() {
                            // Show both internal and clean key formats
                            let clean_key = if key.starts_with("yaml:") {
                                key.strip_prefix("yaml:").unwrap_or(key)
                            } else if key.starts_with("logging:") {
                                key.strip_prefix("logging:").unwrap_or(key)
                            } else {
                                key
                            };
                            println!("{}. {} (내부: {})", i + 1, clean_key, key);
                        }
                        println!("────────────────────────────────────────");
                        println!("총 {}개 키 조회됨", resp.keys.len());
                    }
                }
                Err(e) => {
                    eprintln!("LIST_ALL 오류: {}", e);
                    exit(1);
                }
            }
        }
        Commands::ListKeys { prefix, limit } => {
            println!("🔍 키 검색 중 (prefix: '{}', limit: {})...", prefix, limit);
            
            let request = Request::new(ListKeysRequest { prefix: prefix.clone(), limit });
            
            match client.list_keys(request).await {
                Ok(response) => {
                    let resp = response.into_inner();
                    if resp.keys.is_empty() {
                        println!("프리픽스 '{}' 와 일치하는 키를 찾을 수 없습니다", prefix);
                    } else {
                        println!("프리픽스 '{}' 검색 결과: {}개 키 발견", prefix, resp.total_count);
                        println!("────────────────────────────────────────");
                        for (i, key) in resp.keys.iter().enumerate() {
                            let clean_key = if key.starts_with("yaml:") {
                                key.strip_prefix("yaml:").unwrap_or(key)
                            } else if key.starts_with("logging:") {
                                key.strip_prefix("logging:").unwrap_or(key)
                            } else {
                                key
                            };
                            println!("{}. {} (내부: {})", i + 1, clean_key, key);
                        }
                        println!("────────────────────────────────────────");
                        println!("총 {}개 키 조회됨", resp.keys.len());
                    }
                }
                Err(e) => {
                    eprintln!("LIST_KEYS 오류: {}", e);
                    exit(1);
                }
            }
        }
    }
}
