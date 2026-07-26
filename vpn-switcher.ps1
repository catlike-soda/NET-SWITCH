# ============================================================
# VPN 切换管理器
# 用法: 右键以管理员运行 PowerShell，输入:
#   & "e:\codingsum\vscodeprogram\1\vpn-switcher.ps1"
# 或直接双击 VPN切换.bat
# ============================================================

$script:VPNs = @(
    [PSCustomObject]@{
        Key          = "farmer"
        Name         = "农夫山泉 farmer"
        ExePath      = "D:\zahuo1\NongfuSpring\farmer\farmer.exe"
        Services     = @("farmerHelperService")
        Processes    = @("farmer", "farmerCore", "farmerHelperService")
        ProxyPort    = 7892
        HasTUN       = $true
        TUNAdapter   = "farmer"
    }
    [PSCustomObject]@{
        Key          = "clash"
        Name         = "Clash Verge"
        ExePath      = "D:\zahuo1\、fanqiang\clash-verge.exe"
        Services     = @("clash_verge_service")
        Processes    = @("clash-verge", "clash-verge-service")
        ProxyPort    = 7897
        HasTUN       = $true
        TUNAdapter   = "clash"
    }
    [PSCustomObject]@{
        Key          = "v2rayN"
        Name         = "v2rayN"
        ExePath      = "D:\zahuo1\v2rayN-windows-64\v2rayN.exe"
        Services     = @()
        Processes    = @("v2rayN", "xray", "v2ray")
        ProxyPort    = 10808
        HasTUN       = $false
        TUNAdapter   = ""
    }
    [PSCustomObject]@{
        Key          = "quark"
        Name         = "Quark"
        ExePath      = "D:\zahuo1\Quark\quark_proxy.exe"
        Services     = @()
        Processes    = @("quark_proxy", "new_quark_proxy")
        ProxyPort    = 0
        HasTUN       = $false
        TUNAdapter   = ""
    }
)

# ==================== 工具函数 ====================

function Write-Step($msg) { Write-Host ">>> $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "  [!!] $msg" -ForegroundColor Yellow }
function Write-Fail($msg) { Write-Host "  [XX] $msg" -ForegroundColor Red }

function Test-Admin {
    $current = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($current)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Press-Enter {
    Write-Host ""
    Write-Host "按回车返回主界面..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# ==================== 判断进程是否"残留" ====================
# 残留 = 进程/服务在跑，但主程序 GUI 没开

function Get-ResidualProcesses {
    $residuals = @()
    foreach ($vpn in $script:VPNs) {
        # 检查主 GUI 是否开着
        $guiProcName = ($vpn.ExePath -split '\\')[-1] -replace '\.exe$',''
        $guiRunning = $false
        try {
            $guiProc = Get-Process -Name $guiProcName -ErrorAction SilentlyContinue
            if ($guiProc) {
                # 主程序在运行，检查是否有窗口 (有窗口 = GUI 开着)
                if ($guiProc.MainWindowHandle -ne 0) {
                    $guiRunning = $true
                }
            }
        } catch { }

        if (-not $guiRunning) {
            # GUI 没开 → 所有该 VPN 的进程和服务都是残留
            foreach ($svcName in $vpn.Services) {
                try {
                    $svc = Get-Service -Name $svcName -ErrorAction Stop
                    if ($svc.Status -eq 'Running') {
                        $residuals += [PSCustomObject]@{ Type="服务"; Name=$svcName; VPN=$vpn.Name }
                    }
                } catch { }
            }
            foreach ($procName in $vpn.Processes) {
                try {
                    $procs = Get-Process -Name $procName -ErrorAction SilentlyContinue
                    if ($procs) {
                        $residuals += [PSCustomObject]@{ Type="进程"; Name=$procName; VPN=$vpn.Name }
                    }
                } catch { }
            }
        }
    }
    return $residuals
}

# ==================== 核心操作 ====================

function Clear-Residuals {
    Clear-Host
    Write-Host ""
    Write-Host "╔══════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║        🧹 扫描残留进程               ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    $residuals = Get-ResidualProcesses

    if ($residuals.Count -eq 0) {
        Write-OK "没有残留进程，很干净！"
        Press-Enter
        return
    }

    Write-Host "  发现以下残留 (GUI 没开但后台还在跑):" -ForegroundColor Yellow
    Write-Host ""
    $residuals | ForEach-Object {
        Write-Host "    [$($_.Type)] $($_.Name)  ← $($_.VPN)" -ForegroundColor DarkGray
    }
    Write-Host ""

    $confirm = Read-Host "是否清理这些残留? [Y/n]"
    if ($confirm -eq 'n' -or $confirm -eq 'N') {
        Write-Host "已取消。" -ForegroundColor DarkGray
        Press-Enter
        return
    }

    Write-Host ""
    foreach ($r in $residuals) {
        if ($r.Type -eq "服务") {
            try {
                Stop-Service -Name $r.Name -Force -ErrorAction Stop
                Set-Service -Name $r.Name -StartupType Disabled -ErrorAction SilentlyContinue
                Write-OK "已停止并禁用服务: $($r.Name)"
            } catch {
                Write-Fail "无法停止: $($r.Name)"
            }
        } else {
            try {
                Get-Process -Name $r.Name -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
                Write-OK "已杀掉进程: $($r.Name)"
            } catch {
                Write-Fail "无法杀掉: $($r.Name)"
            }
        }
    }

    Write-Host ""
    Write-OK "残留清理完成！"
    Press-Enter
}

function Switch-VPN($target) {
    Clear-Host
    Write-Host ""
    Write-Host "╔══════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host ("║  启动: " + $target.Name.PadRight(30) + "║") -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    # 只清理残留(其他VPN GUI没开的)，不动正在用的
    $residuals = Get-ResidualProcesses
    if ($residuals.Count -gt 0) {
        Write-Step "先清理残留..."
        foreach ($r in $residuals) {
            if ($r.Type -eq "服务") {
                try {
                    Stop-Service -Name $r.Name -Force -ErrorAction Stop
                    Set-Service -Name $r.Name -StartupType Disabled -ErrorAction SilentlyContinue
                    Write-OK "停止 $($r.Name)"
                } catch { }
            } else {
                try {
                    Get-Process -Name $r.Name -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
                    Write-OK "杀掉 $($r.Name)"
                } catch { }
            }
        }
        Write-Host ""
    }

    # 启用并启动目标服务
    foreach ($svcName in $target.Services) {
        try {
            Set-Service -Name $svcName -StartupType Automatic -ErrorAction SilentlyContinue
            $svc = Get-Service -Name $svcName -ErrorAction Stop
            if ($svc.Status -ne 'Running') {
                Start-Service -Name $svcName -ErrorAction Stop
            }
            Write-OK "服务 $svcName 已就绪"
        } catch {
            Write-Warn "服务 $svcName 启动失败: $_"
        }
    }

    # 启动主程序(没开才启动)
    $exeName = ($target.ExePath -split '\\')[-1] -replace '\.exe$',''
    $alreadyRunning = Get-Process -Name $exeName -ErrorAction SilentlyContinue
    if (-not $alreadyRunning) {
        if ($target.ExePath -and (Test-Path $target.ExePath)) {
            Start-Process -FilePath $target.ExePath
            Write-OK "已启动 $($target.Name)"
            Start-Sleep -Seconds 2
        } else {
            Write-Fail "找不到: $($target.ExePath)"
        }
    } else {
        Write-OK "$($target.Name) 已在运行"
    }

    # 设置系统代理
    if ($target.ProxyPort -gt 0) {
        try {
            Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -Name ProxyEnable -Value 1
            Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -Name ProxyServer -Value "127.0.0.1:$($target.ProxyPort)"
            Write-OK "系统代理 -> 127.0.0.1:$($target.ProxyPort)"
        } catch {
            Write-Warn "系统代理设置失败"
        }
    }

    # 修 TUN MTU
    if ($target.TUNAdapter) {
        $adapter = Get-NetAdapter -Name $target.TUNAdapter -ErrorAction SilentlyContinue
        if ($adapter -and $adapter.Status -eq 'Up') {
            try {
                netsh interface ipv4 set subinterface $target.TUNAdapter mtu=1400 store=persistent 2>&1 | Out-Null
                Write-OK "TUN MTU -> 1400"
            } catch { }
        }
    }

    if ($target.HasTUN) {
        Write-Host "  [i] 请在客户端内确认 TUN 模式已开启" -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host "  $($target.Name) 已就绪" -ForegroundColor Green
    Press-Enter
}

function Show-Status {
    Write-Host ""
    Write-Host "====== 当前 VPN 状态 ======" -ForegroundColor Magenta
    Write-Host ""

    foreach ($vpn in $script:VPNs) {
        $isActive = $false
        $info = @()

        # 检查 GUI
        $exeName = ($vpn.ExePath -split '\\')[-1] -replace '\.exe$',''
        try {
            $gui = Get-Process -Name $exeName -ErrorAction SilentlyContinue
            if ($gui -and $gui.MainWindowHandle -ne 0) {
                $isActive = $true
                $info += "GUI:开"
            } elseif ($gui) {
                $info += "GUI:后台"
            }
        } catch { }

        # 服务
        foreach ($svcName in $vpn.Services) {
            try {
                $svc = Get-Service -Name $svcName -ErrorAction Stop
                if ($svc.Status -eq 'Running') { $info += "服务:运行" } else { $info += "服务:停" }
            } catch { $info += "服务:无" }
        }

        # TUN
        if ($vpn.TUNAdapter) {
            $tun = Get-NetAdapter -Name $vpn.TUNAdapter -ErrorAction SilentlyContinue
            if ($tun -and $tun.Status -eq 'Up') { $info += "TUN:UP" }
        }

        # 残留判定
        $hasGUI = ($info -match 'GUI:开').Count -gt 0
        $hasSvc = ($info -match '服务:运行').Count -gt 0
        $isResidual = ($hasSvc -and -not $hasGUI)

        $num = [array]::IndexOf($script:VPNs, $vpn) + 1
        if ($isActive -or $hasSvc) {
            $tag = if ($isResidual) { "[残留]" } else { "[活跃]" }
            $color = if ($isResidual) { "Yellow" } else { "Green" }
            Write-Host "  [$num] $($vpn.Name) $tag" -ForegroundColor $color
            Write-Host "      $($info -join ', ')" -ForegroundColor DarkGray
        } else {
            Write-Host "  [$num] $($vpn.Name)  [未运行]" -ForegroundColor DarkGray
        }
    }

    Write-Host ""
    try {
        $proxy = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
        if ($proxy.ProxyEnable -eq 1) {
            Write-Host "  系统代理: $($proxy.ProxyServer)" -ForegroundColor Yellow
        } else {
            Write-Host "  系统代理: 未设置" -ForegroundColor DarkGray
        }
    } catch { }
}

# ==================== 主菜单 ====================

function Main {
    Clear-Host
    Write-Host ""
    Write-Host "╔══════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║        🌐 VPN 切换管理器             ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    if (-not (Test-Admin)) {
        Write-Host "  [!] 请以管理员身份运行" -ForegroundColor Red
        Write-Host ""
        Write-Host "  右键 PowerShell -> 以管理员运行，然后:" -ForegroundColor Yellow
        Write-Host "  & `"$PSCommandPath`"" -ForegroundColor White
        Write-Host ""
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        return
    }

    Show-Status

    Write-Host ""
    Write-Host "====== 操作 ======" -ForegroundColor Magenta
    Write-Host ""
    Write-Host "  [1] 农夫山泉 farmer"
    Write-Host "  [2] Clash Verge"
    Write-Host "  [3] v2rayN"
    Write-Host "  [4] Quark"
    Write-Host "  [C] 清理残留进程 (只清GUI没开的)"
    Write-Host "  [Q] 退出"
    Write-Host ""

    $choice = Read-Host "选择"

    switch ($choice) {
        '1'  { Switch-VPN ($script:VPNs[0]); Main }
        '2'  { Switch-VPN ($script:VPNs[1]); Main }
        '3'  { Switch-VPN ($script:VPNs[2]); Main }
        '4'  { Switch-VPN ($script:VPNs[3]); Main }
        'C'  { Clear-Residuals; Main }
        'c'  { Clear-Residuals; Main }
        'Q'  { return }
        'q'  { return }
        ''   { Main }
        default {
            Write-Host "无效选择" -ForegroundColor Red
            Start-Sleep -Seconds 1
            Main
        }
    }
}

Main
