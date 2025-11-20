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
