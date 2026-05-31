Add-Type -AssemblyName System.Net.Http
$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ws.ConnectAsync([Uri]"ws://127.0.0.1:13469/proxy", [System.Threading.CancellationToken]::None).Wait(5000) | Out-Null
if ($ws.State -ne "Open") { Write-Host "Failed to connect"; exit 1 }
function WsSend($obj) { $json = $obj | ConvertTo-Json -Depth 20 -Compress; $bytes = [System.Text.Encoding]::UTF8.GetBytes($json); $seg = [ArraySegment[byte]]::new($bytes); $ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [System.Threading.CancellationToken]::None).Wait(5000) | Out-Null }
$script:pendingRecvTask = $null; $script:pendingRecvBuf = $null
function WsRecv([int]$ms = 15000) {
    $mem = New-Object System.IO.MemoryStream
    do {
        if ($null -ne $script:pendingRecvTask) { $t = $script:pendingRecvTask; $buf = $script:pendingRecvBuf; $script:pendingRecvTask = $null; $script:pendingRecvBuf = $null }
        else { $buf = [byte[]]::new(65536); $seg = [ArraySegment[byte]]::new($buf); $t = $ws.ReceiveAsync($seg, [System.Threading.CancellationToken]::None) }
        if (-not $t.Wait($ms)) { $script:pendingRecvTask = $t; $script:pendingRecvBuf = $buf; return $null }
        $result = $t.Result; if ($result.MessageType -eq "Close") { return $null }
        if ($result.Count -gt 0) { $mem.Write($buf, 0, $result.Count) }
        if ($result.EndOfMessage) { break }
    } while ($true)
    return [System.Text.Encoding]::UTF8.GetString($mem.ToArray()) | ConvertFrom-Json
}
$init = WsRecv 8000
$script:msgId = 0
function Invoke-RunCode([string]$lua) {
    $script:msgId++
    WsSend @{ type="json_rpc"; jsonrpc="2.0"; id="$($script:msgId)"; method="tools/call"; params=@{name="execute_luau";arguments=@{code=$lua}} }
    $r = WsRecv 20000
    while ($r -and $r.type -eq "control") { $r = WsRecv 10000 }
    if ($r -and $r.result) { foreach ($c in $r.result.content) { if ($c.text) { Write-Host $c.text } } }
    elseif ($r -and $r.error) { Write-Host "ERROR: $($r.error.message)" }
    return $r
}

Write-Host "=== Handle MeshPart full properties ==="
Invoke-RunCode @'
local tool = game:GetService("StarterPack"):FindFirstChildOfClass("Tool")
if not tool then return "Tool not found" end
local handle = tool:FindFirstChild("Handle")
if not handle then return "Handle not found" end
local lines = {}
table.insert(lines, "Tool.Name = " .. tool.Name)
table.insert(lines, "Handle.ClassName = " .. handle.ClassName)
if handle:IsA("MeshPart") then
    table.insert(lines, "Handle.MeshId = " .. handle.MeshId)
    table.insert(lines, "Handle.TextureID = " .. handle.TextureID)
    table.insert(lines, "Handle.Size = " .. tostring(handle.Size))
    table.insert(lines, "Handle.Color = " .. tostring(handle.Color))
end
-- Check for all children
for _, child in ipairs(handle:GetChildren()) do
    table.insert(lines, "  child: " .. child.Name .. " [" .. child.ClassName .. "]")
    if child:IsA("SpecialMesh") then
        table.insert(lines, "    MeshId=" .. child.MeshId)
        table.insert(lines, "    TextureId=" .. child.TextureId)
    end
end
-- Also check for Decals/Textures
for _, desc in ipairs(tool:GetDescendants()) do
    if desc:IsA("Decal") or desc:IsA("Texture") or desc:IsA("SpecialMesh") then
        table.insert(lines, "desc: " .. desc:GetFullName() .. " TextureId=" .. (desc.TextureId or "n/a"))
    end
end
return table.concat(lines, "\n")
'@

$ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure,"", [System.Threading.CancellationToken]::None).Wait(2000) | Out-Null
