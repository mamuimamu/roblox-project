# Push src/ scripts to Roblox Studio via /proxy WebSocket on port 13469

Add-Type -AssemblyName System.Net.Http

$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ws.ConnectAsync([Uri]"ws://127.0.0.1:13469/proxy", [System.Threading.CancellationToken]::None).Wait(5000) | Out-Null
if ($ws.State -ne "Open") { Write-Host "Failed to connect"; exit 1 }
Write-Host "Connected to /proxy WebSocket"

function WsSend($obj) {
    $json = $obj | ConvertTo-Json -Depth 20 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $seg = [ArraySegment[byte]]::new($bytes)
    $ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [System.Threading.CancellationToken]::None).Wait(5000) | Out-Null
}

# CancellationToken を使わず pending task を再利用することで
# タイムアウト時に WebSocket が Aborted 状態になるのを防ぐ
$script:pendingRecvTask = $null
$script:pendingRecvBuf  = $null

function WsRecv([int]$ms = 15000) {
    $mem = New-Object System.IO.MemoryStream
    do {
        if ($null -ne $script:pendingRecvTask) {
            $t   = $script:pendingRecvTask
            $buf = $script:pendingRecvBuf
            $script:pendingRecvTask = $null
            $script:pendingRecvBuf  = $null
        } else {
            $buf = [byte[]]::new(65536)
            $seg = [ArraySegment[byte]]::new($buf)
            $t   = $ws.ReceiveAsync($seg, [System.Threading.CancellationToken]::None)
        }
        if (-not $t.Wait($ms)) {
            $script:pendingRecvTask = $t
            $script:pendingRecvBuf  = $buf
            Write-Host "  [recv timeout]"; return $null
        }
        $result = $t.Result
        if ($result.MessageType -eq "Close") { return $null }
        if ($result.Count -gt 0) { $mem.Write($buf, 0, $result.Count) }
        if ($result.EndOfMessage) { break }
    } while ($true)
    $json = [System.Text.Encoding]::UTF8.GetString($mem.ToArray())
    return $json | ConvertFrom-Json
}

# Receive initial tools_updated message
$init = WsRecv 8000
if ($init) {
    if ($init.control_type -eq "tools_updated") {
        $toolNames = $init.tools | ForEach-Object { $_.name }
        Write-Host "Tools available: $($toolNames -join ', ')"
    } else {
        Write-Host "Initial msg type: $($init.type) / $($init.control_type)"
    }
}

$msgId = 0

function Invoke-RunCode([string]$lua) {
    $script:msgId++
    WsSend @{
        type     = "json_rpc"
        jsonrpc  = "2.0"
        id       = "$($script:msgId)"
        method   = "tools/call"
        params   = @{ name = "execute_luau"; arguments = @{ code = $lua } }
    }
    $r = WsRecv 20000
    if ($null -eq $r) { Write-Host "  [no response]"; return $null }
    # might be a control message first, skip and retry
    while ($r -and $r.type -eq "control") {
        Write-Host "  [control: $($r.control_type)]"
        $r = WsRecv 10000
    }
    if ($r -and $r.result) {
        foreach ($c in $r.result.content) { if ($c.text) { Write-Host "  -> $($c.text)" } }
    } elseif ($r -and $r.error) {
        Write-Host "  ERROR: $($r.error.message)"
    } else {
        Write-Host "  [unexpected: $($r | ConvertTo-Json -Compress)]"
    }
    return $r
}

function Push-LuaFile([string]$path,[string]$parentLua,[string]$name,[string]$cls) {
    Write-Host "  $name ($cls)..."
    $src     = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
    $srcJson = $src | ConvertTo-Json -Compress
    $arr     = "[$srcJson]"
    $esc     = $arr.Replace("\","\\").Replace("'","\'")
    $lua = @"
local hs=game:GetService("HttpService")
local arr=hs:JSONDecode('$esc')
local src=arr[1]
local p=$parentLua
local e=p:FindFirstChild("$name"); if e then e:Destroy() end
local s=Instance.new("$cls"); s.Name="$name"; s.Source=src; s.Parent=p
print("OK:$name")
"@
    Invoke-RunCode $lua
}

$r = "c:\Users\kr_im\roblox-project\src"

Write-Host ""
Write-Host "=== Test ==="
Invoke-RunCode 'print("MCP connection test OK")'

Write-Host ""
Write-Host "=== Containers ==="
Invoke-RunCode 'local rs=game:GetService("ReplicatedStorage"); local s=rs:FindFirstChild("Shared"); if s and s:IsA("Folder") then print("Shared OK") else if s then s:Destroy() end local f=Instance.new("Folder");f.Name="Shared";f.Parent=rs;print("Created Shared") end'

Push-LuaFile "$r\Server\init.server.lua" 'game:GetService("ServerScriptService")' "Server" "Script"

Invoke-RunCode 'local sp=game:GetService("StarterPlayer");local sps=sp:FindFirstChild("StarterPlayerScripts") or sp:WaitForChild("StarterPlayerScripts");local c=sps:FindFirstChild("Client");if c and c:IsA("Folder") then print("Client OK") else if c then c:Destroy() end local f=Instance.new("Folder");f.Name="Client";f.Parent=sps;print("Created Client") end'

Write-Host ""
Write-Host "=== Scripts ==="
Push-LuaFile "$r\Shared\Config.lua"                       'game:GetService("ReplicatedStorage"):FindFirstChild("Shared")'                                              "Config"               "ModuleScript"
Push-LuaFile "$r\Shared\GameConfig.lua"                   'game:GetService("ReplicatedStorage"):FindFirstChild("Shared")'                                              "GameConfig"           "ModuleScript"
Push-LuaFile "$r\Server\FireManager.server.lua"           'game:GetService("ServerScriptService"):FindFirstChild("Server")'                                            "FireManager"          "Script"
Push-LuaFile "$r\Server\ScoreManager.server.lua"          'game:GetService("ServerScriptService"):FindFirstChild("Server")'                                            "ScoreManager"         "Script"
Push-LuaFile "$r\Server\VehiclePromptHandler.server.lua"   'game:GetService("ServerScriptService"):FindFirstChild("Server")'                                            "VehiclePromptHandler"   "Script"
Push-LuaFile "$r\Server\WaterCannonHandler.server.lua"     'game:GetService("ServerScriptService"):FindFirstChild("Server")'                                            "WaterCannonHandler"     "Script"
Push-LuaFile "$r\Server\GameModeManager.server.lua"       'game:GetService("ServerScriptService"):FindFirstChild("Server")'                                            "GameModeManager"        "Script"
Push-LuaFile "$r\Server\BurningHouseManager.server.lua"   'game:GetService("ServerScriptService"):FindFirstChild("Server")'                                            "BurningHouseManager"    "Script"
Push-LuaFile "$r\Server\TownGenerator.server.lua"         'game:GetService("ServerScriptService"):FindFirstChild("Server")'                                            "TownGenerator"          "Script"
Push-LuaFile "$r\Server\LightingSetup.server.lua"        'game:GetService("ServerScriptService"):FindFirstChild("Server")'                                            "LightingSetup"          "Script"
Push-LuaFile "$r\Server\VehicleColorizer.server.lua"    'game:GetService("ServerScriptService"):FindFirstChild("Server")'                                            "VehicleColorizer"       "Script"
Push-LuaFile "$r\Client\ExtinguisherController.client.lua"  'game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts"):FindFirstChild("Client")'          "ExtinguisherController"   "LocalScript"
Push-LuaFile "$r\Client\BurningHouseController.client.lua"  'game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts"):FindFirstChild("Client")'          "BurningHouseController"   "LocalScript"
Push-LuaFile "$r\Client\ScoreUIController.client.lua"      'game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts"):FindFirstChild("Client")'          "ScoreUIController"       "LocalScript"
Push-LuaFile "$r\Client\VehicleController.client.lua"      'game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts"):FindFirstChild("Client")'          "VehicleController"       "LocalScript"
Push-LuaFile "$r\Client\WaterCannonController.client.lua"  'game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts"):FindFirstChild("Client")'          "WaterCannonController"   "LocalScript"
Push-LuaFile "$r\Client\MinimapController.client.lua"     'game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts"):FindFirstChild("Client")'          "MinimapController"       "LocalScript"

Write-Host ""
Write-Host "=== Done ==="
$ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure,"", [System.Threading.CancellationToken]::None).Wait(2000) | Out-Null
