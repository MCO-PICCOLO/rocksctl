use std::path::PathBuf;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    // 항상 로컬 proto 파일 사용
    let proto_path = PathBuf::from("proto/rocksdbservice.proto");

    println!("proto_path: {:?}", proto_path);
    
    if proto_path.exists() {
        println!("Using proto file: {:?}", proto_path);
        tonic_build::compile_protos(&proto_path)?;
    } else {
        panic!("rocksdbservice.proto file not found at: {:?}", proto_path);
    }
    
    Ok(())
}