#!/bin/bash

echo "🎯 RocksDB Client with ListKeys-Based Operations Demo"
echo "===================================================="
echo ""

CLIENT="./rocksdb-client-static"
SERVER_URL="http://localhost:47010"

echo "📋 Available Commands:"
echo "  • put: Store data"
echo "  • get: Retrieve data (now uses ListKeys internally!)"
echo "  • delete: Remove data"
echo "  • get-prefix: Get data by prefix"
echo "  • list-all: List all keys using ListKeys RPC"
echo "  • list-keys: List keys with prefix using ListKeys RPC"
echo ""

echo "🔍 Key Features:"
echo "  ✅ Get command now uses ListKeys + GetByPrefix instead of Get RPC"
echo "  ✅ Handles internal prefixes (yaml:, logging:) transparently"
echo "  ✅ Enhanced error messages with available keys"
echo "  ✅ Clean display format showing both internal and user-friendly names"
echo ""

if ! netstat -tlnp 2>/dev/null | grep -q ":47010 " && ! ss -tlnp 2>/dev/null | grep -q ":47010 "; then
    echo "⚠️  Multi-database service not running on port 47010"
    echo "   Start it with:"
    echo "   cd /home/lge/Desktop/2025/pullpiri"
    echo "   nohup ./src/server/rocksdbservice/target/debug/main_multi_db \\"
    echo "     --yaml-path /tmp/pullpiri_yaml_db \\"
    echo "     --logging-path /tmp/pullpiri_system_db \\"
    echo "     --port 47010 > /tmp/multidb.log 2>&1 &"
    echo ""
    echo "💡 Demo Commands (run after starting service):"
else
    echo "✅ Service is running! Running demo..."
    echo ""
    
    echo "1️⃣ Put some test data:"
    $CLIENT --url $SERVER_URL put scenario/demo "Demo scenario data"
    $CLIENT --url $SERVER_URL put /piccolo/metrics/memory "Memory: 75%"
    echo ""
    
    echo "2️⃣ Get data using ListKeys-based approach:"
    $CLIENT --url $SERVER_URL get scenario/demo
    echo ""
    $CLIENT --url $SERVER_URL get /piccolo/metrics/memory
    echo ""
    
    echo "3️⃣ List all keys:"
    $CLIENT --url $SERVER_URL list-all --limit 10
    echo ""
    
    echo "4️⃣ List keys with prefix:"
    $CLIENT --url $SERVER_URL list-keys --prefix "yaml:scenario" --limit 5
    echo ""
    
    echo "5️⃣ Error handling for missing key:"
    $CLIENT --url $SERVER_URL get missing/key 2>&1 || true
fi

echo ""
echo "🎉 ListKeys-Based Operations Demo Complete!"
echo ""
echo "📚 Summary of Changes:"
echo "  • Get command: Get RPC → ListKeys + GetByPrefix"
echo "  • New commands: list-all, list-keys"
echo "  • Enhanced error handling and display"
echo "  • Transparent internal prefix handling"
