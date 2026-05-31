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
    if ($r -and $r.result) { foreach ($c in $r.result.content) { if ($c.text) { Write-Host "  -> $($c.text)" } } }
    elseif ($r -and $r.error) { Write-Host "  ERROR: $($r.error.message)" }
    return $r
}

Write-Host "=== Push blank FireManager to Studio ==="
$src = "-- FireManager は VehiclePromptHandler に置き換えられました。このスクリプトは無効です。`n"
$srcJson = $src | ConvertTo-Json -Compress
$arr = "[$srcJson]"
$esc = $arr.Replace("\","\\").Replace("'","\'")
Invoke-RunCode @"
local hs=game:GetService('HttpService')
local arr=hs:JSONDecode('$esc')
local src=arr[1]
local p=game:GetService('ServerScriptService'):FindFirstChild('Server')
if not p then return 'Server folder not found' end
local e=p:FindFirstChild('FireManager'); if e then e:Destroy() end
local s=Instance.new('Script'); s.Name='FireManager'; s.Source=src; s.Parent=p
return 'OK: FireManager blanked'
"@

Write-Host ""
Write-Host "=== Delete FireTruckButton from Workspace ==="
Invoke-RunCode @'
local ws = game:GetService("Workspace")
local deleted = {}
-- Delete FireTruckButton
local btn = ws:FindFirstChild("FireTruckButton")
if btn then btn:Destroy(); table.insert(deleted, "FireTruckButton") end
-- Also delete any simple red VehicleSeat-based RescueVehicle (the old fake one)
-- The real one is the Endorsed Vehicle model with a Chassis sub-model
local rv = ws:FindFirstChild("RescueVehicle")
if rv then
    -- Check if it's the OLD fake one (has DriverSeat child directly, not Chassis folder)
    local ds = rv:FindFirstChild("DriverSeat")
    local chassis = rv:FindFirstChild("Chassis")
    if ds and not chassis then
        rv:Destroy()
        table.insert(deleted, "RescueVehicle (old fake)")
    else
        table.insert(deleted, "RescueVehicle (real - kept)")
    end
end
return #deleted > 0 and ("Deleted: " .. table.concat(deleted, ", ")) or "Nothing to delete"
'@

$ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure,"", [System.Threading.CancellationToken]::None).Wait(2000) | Out-Null
Write-Host "Done."
