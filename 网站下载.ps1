$ErrorActionPreference = "SilentlyContinue"
chcp 65001 | Out-Null

Clear-Host
Write-Host "====================================================" -ForegroundColor Red
Write-Host "重要声明：本脚本仅用于合法合规的技术研究/个人学习使用" -ForegroundColor Red
Write-Host "====================================================" -ForegroundColor Red
Write-Host "1. 使用本脚本前，必须确保目标网站的资源下载行为符合《网络安全法》《著作权法》等法律法规"
Write-Host "2. 不得用于爬取/下载有版权保护、隐私保护或禁止转载的内容"
Write-Host "3. 不得用于商业用途、恶意攻击、批量爬取等违规行为"
Write-Host "4. 使用者需自行承担因违规使用本脚本产生的全部法律责任"
Write-Host "5. 本脚本作者不对任何违规使用行为造成的后果负责"
Write-Host "====================================================" -ForegroundColor Red
$confirm = Read-Host "请确认已阅读并遵守以上声明（输入 Y 继续，其他键退出）"
if ($confirm -ne "Y" -and $confirm -ne "y") {
    Write-Host "`n你已取消执行，程序退出！" -ForegroundColor Yellow
    Pause
    exit 0
}

$TEMP_HTML = "$env:TEMP\tmp_frontend.html"
$DOWNLOAD_TIMEOUT = 10000
$USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

try {
    New-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "LongPathsEnabled" -Value 1 -PropertyType DWord -Force | Out-Null
}
catch {
    Write-Host "`n提示：未启用长路径支持（非管理员权限），可能导致长路径文件下载失败" -ForegroundColor Yellow
}

Add-Type -AssemblyName System.Windows.Forms
$folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
$folderDialog.Description = "请选择网页资源的保存目录"
$folderDialog.RootFolder = "Desktop"

if ($folderDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
    $SAVE_ROOT = $folderDialog.SelectedPath
    Write-Host "`n已选择保存目录：$SAVE_ROOT" -ForegroundColor Green
}
else {
    Write-Host "`n错误：你取消了目录选择，程序退出！" -ForegroundColor Red
    Pause
    exit 1
}

if (-not (Test-Path $SAVE_ROOT)) {
    New-Item -ItemType Directory -Path $SAVE_ROOT -Force | Out-Null
    Write-Host "已创建保存目录：$SAVE_ROOT" -ForegroundColor Cyan
}

Write-Host "`n===================== 网页资源获取工具 =====================" -ForegroundColor Cyan
Write-Host "支持：本地服务器URL / 远程网页URL（如 https://www.XXX.com）"
$TARGET_URL = Read-Host "请输入要获取的目标URL"

while ($true) {
    if (-not $TARGET_URL) {
        Write-Host "错误：URL不能为空！" -ForegroundColor Red
    }
    elseif (-not ($TARGET_URL -match '^http(s)?://')) {
        Write-Host "错误：URL格式无效，必须以 http:// 或 https:// 开头" -ForegroundColor Red
    }
    else {
        try {
            $null = [Uri]::new($TARGET_URL)
            break
        }
        catch {
            Write-Host "错误：URL格式不合法（$($_.Exception.Message)）" -ForegroundColor Red
        }
    }
    $TARGET_URL = Read-Host "请重新输入有效的目标URL"
}

Write-Host "`n再次确认：你即将下载 $TARGET_URL 的资源，请确保该行为合法合规！" -ForegroundColor Yellow
$confirmUrl = Read-Host "确认继续下载？（Y/N）"
if ($confirmUrl -ne "Y" -and $confirmUrl -ne "y") {
    Write-Host "`n你已取消下载，程序退出！" -ForegroundColor Yellow
    Pause
    exit 0
}

$webClient = New-Object System.Net.WebClient
$webClient.Encoding = [System.Text.Encoding]::UTF8
$webClient.Headers.Add("User-Agent", $USER_AGENT)
$webClient.Timeout = $DOWNLOAD_TIMEOUT

Write-Host "`n正在下载主页面：$TARGET_URL" -ForegroundColor Cyan
try {
    $webClient.DownloadFile($TARGET_URL, $TEMP_HTML)
    Write-Host "主页面下载成功！" -ForegroundColor Green
}
catch {
    Write-Host "`n错误：无法下载主页面！" -ForegroundColor Red
    Write-Host "   原因：$($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "   请检查：1.URL是否有效 2.网络是否正常 3.目标网站是否允许访问" -ForegroundColor Yellow
    Pause
    exit 1
}

Write-Host "`n正在解析并下载静态资源（CSS/JS/图片/字体等）..." -ForegroundColor Cyan
$htmlContent = Get-Content $TEMP_HTML -Raw -Encoding UTF8

$resourcePattern = 'src=["'']([^"'']+)["'']|href=["'']([^"'']+)["'']'
$matches = [regex]::Matches($htmlContent, $resourcePattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

$resources = @()
foreach ($m in $matches) {
    $url = $m.Groups[1].Value.Trim()
    if (-not $url) { $url = $m.Groups[2].Value.Trim() }
    
    if ($url -and 
        $url -notmatch '^#|^data:|^blob:|^mailto:|^tel:|^javascript:|^about:' -and 
        $url -notmatch '^http(s)?://' -and 
        $resources -notcontains $url) {
        $resources += $url
    }
}

$successCount = 1  
$skipCount = 0
$errorCount = 0
$downloadedResources = @()

foreach ($res in $resources) {
    try {
        $cleanRes = $res -replace '\?.*$', '' `
                         -replace '/+', '/' `
                         -replace '^/+', '' `
                         -replace '[<>:"|?*]', '_'
        
        if (-not $cleanRes -or $downloadedResources -contains $cleanRes) {
            $skipCount++
            Write-Host "跳过：$res（原因：空路径/已下载）" -ForegroundColor Gray
            continue
        }

        $savePath = Join-Path $SAVE_ROOT $cleanRes
        $saveDir = Split-Path $savePath -Parent

        if (-not (Test-Path $saveDir)) {
            New-Item -ItemType Directory -Path $saveDir -Force -ErrorAction Stop | Out-Null
        }

        $fullResUrl = [Uri]::new([Uri]::new($TARGET_URL), $res).AbsoluteUri
        
        $webClient.DownloadFile($fullResUrl, $savePath)
        $successCount++  
        $downloadedResources += $cleanRes
        Write-Host "已下载：$cleanRes" -ForegroundColor Green
    }
    catch [System.Net.WebException] {
        $errorCount++
        Write-Host "网络错误：$res（原因：$($_.Exception.Message)）" -ForegroundColor Red
    }
    catch [System.IO.IOException] {
        $skipCount++
        Write-Host "文件错误：$res（原因：$($_.Exception.Message)）" -ForegroundColor Yellow
    }
    catch {
        $skipCount++
        Write-Host "跳过非必需资源：$res（原因：$($_.Exception.Message)）" -ForegroundColor Gray
    }
}

Copy-Item $TEMP_HTML (Join-Path $SAVE_ROOT "index.html") -Force
Remove-Item $TEMP_HTML -Force -ErrorAction SilentlyContinue

Write-Host "`n===================== 下载完成 =====================" -ForegroundColor Cyan
Write-Host "所有文件已保存至：$SAVE_ROOT" -ForegroundColor Green
Write-Host "主页面：$SAVE_ROOT\index.html"
Write-Host "成功下载资源数：$successCount"  
Write-Host "跳过资源数：$skipCount"
Write-Host "网络错误数：$errorCount"
Write-Host "===================================================="
Write-Host "`n重要提醒：下载的资源仅用于个人学习，请勿用于商业/违规用途！" -ForegroundColor Red
Pause