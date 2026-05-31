Add-Type -AssemblyName System.Net.Http

$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ws.ConnectAsync([Uri]"ws://127.0.0.1:13469/proxy", [System.Threading.CancellationToken]::None).Wait(5000) | Out-Null
if ($ws.State -ne "Open") { Write-Host "Failed to connect"; exit 1 }
Write-Host "Connected"

function WsSend($obj) {
    $json = $obj | ConvertTo-Json -Depth 20 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $seg = [ArraySegment[byte]]::new($bytes)
    $ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [System.Threading.CancellationToken]::None).Wait(5000) | Out-Null
}
$script:pendingRecvTask = $null
$script:pendingRecvBuf  = $null
function WsRecv([int]$ms = 15000) {
    $mem = New-Object System.IO.MemoryStream
    do {
        if ($null -ne $script:pendingRecvTask) {
            $t = $script:pendingRecvTask; $buf = $script:pendingRecvBuf
            $script:pendingRecvTask = $null; $script:pendingRecvBuf = $null
        } else {
            $buf = [byte[]]::new(65536)
            $seg = [ArraySegment[byte]]::new($buf)
            $t = $ws.ReceiveAsync($seg, [System.Threading.CancellationToken]::None)
        }
        if (-not $t.Wait($ms)) { $script:pendingRecvTask = $t; $script:pendingRecvBuf = $buf; return $null }
        $result = $t.Result
        if ($result.MessageType -eq "Close") { return $null }
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

Write-Host "=== All Workspace top-level children ==="
Invoke-RunCode @'
local lines = {}
for _, child in ipairs(game:GetService("Workspace"):GetChildren()) do
    local extra = ""
    if child:IsA("BasePart") then
        extra = " color=" .. tostring(child.BrickColor) .. " pos=" .. tostring(child.Position)
    end
    table.insert(lines, child.Name .. " [" .. child.ClassName .. "]" .. extra)
end
return table.concat(lines, "\n")
'@

Write-Host ""
Write-Host "=== Red-colored parts anywhere in Workspace ==="
Invoke-RunCode @'
local lines = {}
local redColors = {"Really red", "Bright red", "Crimson", "Red", "Dark red", "Maroon"}
local function isRed(bc)
    local s = tostring(bc)
    for _, r in ipairs(redColors) do
        if s == r then return true end
    end
    return false
end
for _, part in ipairs(game:GetService("Workspace"):GetDescendants()) do
    if part:IsA("BasePart") and isRed(part.BrickColor) then
        local pos = part.Position
        table.insert(lines, part:GetFullName() .. " [" .. part.ClassName .. "] size=" .. tostring(part.Size) .. " pos=" .. string.format("%.1f,%.1f,%.1f", pos.X, pos.Y, pos.Z))
    end
end
return #lines > 0 and table.concat(lines, "\n") or "none found"
'@

Write-Host ""
Write-Host "=== Scripts/ClickDetectors/ProximityPrompts in Workspace (not in RescueVehicle) ==="
Invoke-RunCode @'
local lines = {}
local rv = game:GetService("Workspace"):FindFirstChild("RescueVehicle")
for _, obj in ipairs(game:GetService("Workspace"):GetDescendants()) do
    -- skip RescueVehicle internals
    local skip = false
    local p = obj
    while p do
        if p == rv then skip = true; break end
        p = p.Parent
    end
    if not skip then
        if obj:IsA("Script") or obj:IsA("LocalScript") or obj:IsA("ClickDetector") or obj:IsA("ProximityPrompt") then
            table.insert(lines, obj:GetFullName() .. " [" .. obj.ClassName .. "]")
        end
    end
end
return #lines > 0 and table.concat(lines, "\n") or "none found"
'@

$ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure,"", [System.Threading.CancellationToken]::None).Wait(2000) | Out-Null
