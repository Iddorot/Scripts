# =============================================================================
# modules/logger.ps1
# Coloured, levelled console logging with optional transcript file.
# =============================================================================

$script:TranscriptPath = $null

function Start-RunLog {
    param([string]$LogDir = "$PSScriptRoot\..\logs")
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    $ts  = Get-Date -Format "yyyyMMdd-HHmmss"
    $script:TranscriptPath = Join-Path $LogDir "run-$ts.log"
    Start-Transcript -Path $script:TranscriptPath -Append | Out-Null
    Write-Log "INFO" "Transcript started -> $($script:TranscriptPath)"
}

function Stop-RunLog {
    if ($script:TranscriptPath) {
        Stop-Transcript | Out-Null
        Write-Log "INFO" "Transcript saved -> $($script:TranscriptPath)"
    }
}

function Write-Log {
    param(
        [ValidateSet("INFO","SUCCESS","WARN","ERROR","STEP","SKIP","DEBUG")]
        [string]$Level = "INFO",
        [string]$Message
    )

    $stamp = Get-Date -Format "HH:mm:ss"
    $color = switch ($Level) {
        "INFO"    { "Cyan"    }
        "SUCCESS" { "Green"   }
        "WARN"    { "Yellow"  }
        "ERROR"   { "Red"     }
        "STEP"    { "Magenta" }
        "SKIP"    { "DarkGray"}
        "DEBUG"   { "Gray"    }
    }

    $prefix = switch ($Level) {
        "INFO"    { "[i] " }
        "SUCCESS" { "[OK] " }
        "WARN"    { "[!!] " }
        "ERROR"   { "[ERR] " }
        "STEP"    { ">? " }
        "SKIP"    { ">>? " }
        "DEBUG"   { "[..] " }
    }

    Write-Host "$stamp  $prefix[$Level]  $Message" -ForegroundColor $color
}

function Assert-Module {
    param([string[]]$Names)
    foreach ($name in $Names) {
        if (-not (Get-Module -ListAvailable -Name $name)) {
            Write-Log "WARN" "Module '$name' not found - installing..."
            Install-Module $name -Scope CurrentUser -Force -AllowClobber
        }
        if (-not (Get-Module -Name $name)) {
            Import-Module $name -ErrorAction Stop
        } else {
            Write-Log "DEBUG" "Module '$name' already loaded, skipping import"
        }
    }
}
 