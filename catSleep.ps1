# ================== ASSEMBLIES ==================
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ================== GLOBALS ==================
$AllowClose = $false

# Criar hashtable global para manter objetos vivos e prevenir GC
$global:TrayApp = @{ }
$global:TrayApp.NotifyIcon = New-Object System.Windows.Forms.NotifyIcon
$TrayIcon = $global:TrayApp.NotifyIcon

# ================== INFORMAÇÕES DE AUTOR ==================
$Author = "Bruno Santos Caetano"
$Year   = "2026"

# ================== LOG ==================
$LogDir = $env:ProgramData
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir | Out-Null
}
$LogFile = Join-Path $LogDir "ScreenControl.log"

function Write-Log {
    param([string]$Msg)
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Msg"
    Add-Content -Path $LogFile -Value $line
    if ($OutputBox) {
        $OutputBox.AppendText("$line`r`n")
        $OutputBox.ScrollToEnd()
    }
}

# Log inicial com autor e ano
Write-Log "Aplicação iniciada."
Write-Log "Autor: $Author | Ano: $Year"

# ================== XAML ==================
[xml]$XAML = @"
<Window xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation'
        Title='Screen Control - Field Service'
        Width='620'
        MinHeight='450'
        WindowStartupLocation='CenterScreen'>
    <Grid Margin='10'>
        <Grid.RowDefinitions>
            <RowDefinition Height='Auto'/>
            <RowDefinition Height='*'/>
        </Grid.RowDefinitions>

        <TextBlock Text='Screen Control (AD DS)'
                   FontSize='20'
                   FontWeight='Bold'
                   HorizontalAlignment='Center'
                   Margin='0,0,0,10'/>

        <ScrollViewer Grid.Row='1'>
            <StackPanel>

                <TextBlock Name='StatusLabel'
                           Text='Status: INATIVO'
                           FontWeight='Bold'
                           Foreground='Red'
                           Margin='0,0,0,8'/>

                <Button Name='BtnToggle'
                        Content='Ativar Anti-Lock'
                        Height='35'
                        Margin='0,0,0,8'/>

                <Button Name='BtnDetectGPO'
                        Content='Detectar GPO de Bloqueio'
                        Height='35'
                        Margin='0,0,0,8'/>

                <TextBox Name='OutputBox'
                         MinHeight='180'
                         IsReadOnly='True'
                         VerticalScrollBarVisibility='Auto'
                         Margin='0,0,0,8'/>

                <Button Name='BtnExit'
                        Content='Minimizar'
                        Height='30'
                        Width='100'
                        HorizontalAlignment='Right'/>

                <!-- Informações de autor no rodapé -->
                <TextBlock Name='AuthorLabel'
                           Text='Autor: Bruno Santos Caetano | Ano: 2026'
                           FontStyle='Italic'
                           FontSize='12'
                           HorizontalAlignment='Right'
                           Margin='0,5,0,0'/>

            </StackPanel>
        </ScrollViewer>
    </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $XAML
$Window = [Windows.Markup.XamlReader]::Load($reader)

# ================== CONTROLES ==================
$BtnToggle    = $Window.FindName("BtnToggle")
$BtnDetectGPO = $Window.FindName("BtnDetectGPO")
$BtnExit      = $Window.FindName("BtnExit")
$OutputBox    = $Window.FindName("OutputBox")
$StatusLabel  = $Window.FindName("StatusLabel")
$AuthorLabel  = $Window.FindName("AuthorLabel")

# ================== TIMER ANTI-LOCK ==================
$Timer = New-Object System.Windows.Threading.DispatcherTimer
$Timer.Interval = [TimeSpan]::FromSeconds(240)
$Timer.Add_Tick({
    try {
        $initial = [System.Windows.Forms.Control]::IsKeyLocked([System.Windows.Forms.Keys]::Scroll)
        [System.Windows.Forms.SendKeys]::SendWait("{SCROLLLOCK}")
        Start-Sleep -Milliseconds 100
        if ($initial) { [System.Windows.Forms.SendKeys]::SendWait("{SCROLLLOCK}") }
        Write-Log "Keep-alive enviado."
    } catch { Write-Log "Erro no Keep-alive: $_" }
})

function Start-AntiLock {
    $Timer.Start()
    $StatusLabel.Text = "Status: ATIVO"
    $StatusLabel.Foreground = "Green"
    $BtnToggle.Content = "Desativar Anti-Lock"
    Write-Log "Anti-Lock ativado."
    Update-TrayIcon
}

function Stop-AntiLock {
    $Timer.Stop()
    $StatusLabel.Text = "Status: INATIVO"
    $StatusLabel.Foreground = "Red"
    $BtnToggle.Content = "Ativar Anti-Lock"
    Write-Log "Anti-Lock desativado."
    Update-TrayIcon
}

# ================== GPO DETECTION ==================
function Detect-GPO {
    Write-Log "Detectando GPO..."
    $output = & "$env:SystemRoot\System32\gpresult.exe" /R /SCOPE COMPUTER 2>&1
    $patterns = "InactivityTimeoutSecs","Screen saver timeout","Password protect the screen saver","Lock workstation"
    $matches = $output | Select-String -Pattern $patterns
    if ($matches) { $matches | ForEach-Object { Write-Log $_.Line } }
    else { Write-Log "Nenhuma GPO de bloqueio encontrada." }
}

# ================== TRAY ICON ==================
$ScriptDir = Split-Path -Parent $([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)

$IconInativoPath = Join-Path $ScriptDir "icon-inativo.ico"
$IconAtivoPath   = Join-Path $ScriptDir "icon-ativo.ico"

if (Test-Path $IconInativoPath) { $IconInativo = New-Object System.Drawing.Icon($IconInativoPath) }
else { $IconInativo = [System.Drawing.SystemIcons]::Information }

if (Test-Path $IconAtivoPath) { $IconAtivo = New-Object System.Drawing.Icon($IconAtivoPath) }
else { $IconAtivo = [System.Drawing.SystemIcons]::Shield }

function Update-TrayIcon {
    if ($Timer.IsEnabled) {
        $TrayIcon.Icon = $IconAtivo
        $TrayIcon.Text = "Screen Control - ATIVO"
    } else {
        $TrayIcon.Icon = $IconInativo
        $TrayIcon.Text = "Screen Control - INATIVO"
    }
}

$TrayMenu = New-Object System.Windows.Forms.ContextMenuStrip
$MenuOpen   = $TrayMenu.Items.Add("Abrir")
$MenuToggle = $TrayMenu.Items.Add("Ativar / Desativar Anti-Lock")
$MenuExit   = $TrayMenu.Items.Add("Sair")
$TrayIcon.ContextMenuStrip = $TrayMenu
$TrayIcon.Visible = $true

# ================== EVENTOS ==================
$MenuOpen.Add_Click({ $Window.Show(); $Window.Activate() })
$MenuToggle.Add_Click({ if ($Timer.IsEnabled) { Stop-AntiLock } else { Start-AntiLock } })
$MenuExit.Add_Click({
    Write-Log "Encerrando aplicação."
    $AllowClose = $true
    if ($Timer.IsEnabled) { $Timer.Stop() }
    $TrayIcon.Visible = $false
    $TrayIcon.Dispose()
    [System.Windows.Threading.Dispatcher]::ExitAllFrames()
})

$TrayIcon.Add_DoubleClick({ $Window.Show(); $Window.Activate() })
$BtnToggle.Add_Click({ if ($Timer.IsEnabled) { Stop-AntiLock } else { Start-AntiLock } })
$BtnDetectGPO.Add_Click({ Detect-GPO })
$BtnExit.Add_Click({ $Window.Hide() })
$Window.Add_Closing({ if (-not $AllowClose) { $_.Cancel = $true; $Window.Hide() } })

# ================== START ==================
Write-Log "Aplicação iniciada minimizada no tray."
Update-TrayIcon
$Window.Hide()

# ================== EXECUTAR WPF DISPATCHER ==================
[System.Windows.Threading.Dispatcher]::Run()
