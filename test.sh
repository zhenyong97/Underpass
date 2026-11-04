#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h}"
mkdir -p "$project_dir/.build/module-cache"
swiftc -Onone -module-cache-path "$project_dir/.build/module-cache" \
  "$project_dir"/Sources/Channels/*.swift "$project_dir/Sources/Runtime/RuntimeIO.swift" "$project_dir/Sources/Runtime/EngineConfiguration.swift" \
  "$project_dir/Sources/Runtime/EngineClient.swift" "$project_dir/Sources/Runtime/RuleTransaction.swift" "$project_dir/Sources/Runtime/ProxyRestoration.swift" "$project_dir/Sources/App/ChannelBrowser.swift" "$project_dir/Tests/CoreTests.swift" \
  -framework SystemConfiguration -o "$project_dir/.build/core-tests"
"$project_dir/.build/core-tests" "$project_dir" "$@"
swiftc -Onone -module-cache-path "$project_dir/.build/module-cache" \
  "$project_dir"/Sources/Channels/*.swift "$project_dir/Sources/Runtime/RuntimeIO.swift" "$project_dir/Sources/Runtime/EngineConfiguration.swift" \
  "$project_dir/Sources/Runtime/EngineClient.swift" "$project_dir/Tests/EngineClientProbe.swift" \
  -framework SystemConfiguration -o "$project_dir/.build/engine-probe"
python3 "$project_dir/Tests/LocalRoutingTest.py"
