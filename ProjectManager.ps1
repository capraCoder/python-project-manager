# ═══════════════════════════════════════════════════════════════════════════════
# ⚡ Python Project Manager for PowerShell
# ═══════════════════════════════════════════════════════════════════════════════
# Lightning-fast Python project switching on Windows
# Author: capraCoder
# GitHub: https://github.com/capraCoder/python-project-manager
# 
# Features:
#   • Sub-second project switching (vs Poetry's 10+ seconds)
#   • Auto-healing broken environments  
#   • Smart shortcuts: p01, runproj 13a, mkuse data-analysis
#   • Lazy-loaded p001-p999 aliases (zero startup cost)
#   • Windows-native PowerShell integration
#
# Usage:
#   mkuse experiment    # Create + switch in one command
#   p03                # Quick run project03  
#   runproj 13a        # Smart parsing → project13a
#   whichproj          # Show current project
#
# Requirements: Windows 10+, PowerShell 7.0+, Python 3.8+
# License: MIT
# ═══════════════════════════════════════════════════════════════════════════════

# Configuration
$Base = "C:\Code"
$PyVer = "3.13"
$CurrentFile = Join-Path $Base ".CURRENT"
$script:ValidatedProjects = @{}

function Ensure-Project {
    param([string]$name)
    if ($script:ValidatedProjects[$name]) { return }
    
    $dir = Join-Path $Base $name
    $venv = Join-Path $dir ".venv"
    $scriptPath = Join-Path $dir "$name.py"
    $pythonExe = Join-Path $venv "Scripts\python.exe"
    
    $needsVenv = !(Test-Path $venv)
    $needsScript = !(Test-Path $scriptPath)
    
    if ($needsVenv -or $needsScript) {
        New-Item -ItemType Directory -Force -Path $dir -ErrorAction SilentlyContinue | Out-Null
        
        if ($needsVenv) {
            Write-Host "Creating venv for $name..." -ForegroundColor Yellow
            py -$PyVer -m venv $venv 2>$null
            if ($LASTEXITCODE -eq 0) {
                & $pythonExe -m pip install --upgrade pip --quiet 2>$null
                if ($LASTEXITCODE -ne 0) { & $pythonExe -m ensurepip --upgrade 2>$null }
            } else { throw "Failed to create virtual environment for $name" }
        }
        
        if ($needsScript) { "print(`"Hello from $name`")" | Set-Content -Encoding UTF8 -Path $scriptPath }
    }
    
    $script:ValidatedProjects[$name] = $true
}

function New-Project { 
    param([string]$name) 
    Ensure-Project $name
    Write-Host "Project '$name' ready" -ForegroundColor Green 
}

function Use-Project {
    param([string]$name)
    $src = Join-Path $Base $name
    if (!(Test-Path $src)) { Ensure-Project $name }
    $null = robocopy $src (Join-Path $Base "project00") /MIR /XD ".venv" "__pycache__" ".git" /XF "*.pyc" /NFL /NDL /NJH /NJS /nc /ns
    $name | Set-Content -Encoding ASCII -Path $CurrentFile -NoNewline
    Write-Host "→ $name" -ForegroundColor Cyan
}

function Run-Project {
    param([string]$name)
    if (-not $name) {
        if (Test-Path $CurrentFile) { $name = (Get-Content -Raw $CurrentFile).Trim() }
        else { throw "No current project. Use: useproj <n>" }
    }
    
    $dir = Join-Path $Base $name
    if (!(Test-Path $dir)) { Ensure-Project $name }
    
    $exe = Join-Path $dir ".venv\Scripts\python.exe"
    $scriptPath = Join-Path $dir "$name.py"
    
    if (!(Test-Path $exe) -or !(Test-Path $scriptPath)) {
        Ensure-Project $name
        $exe = Join-Path $dir ".venv\Scripts\python.exe"
        $scriptPath = Join-Path $dir "$name.py"
    }
    
    & $exe $scriptPath
}

$script:ProjectPattern = [regex]::new('^(\d{1,3})([a-zA-Z0-9]*)$', 'IgnoreCase')

function runproj {
    param([string]$arg)
    if (-not $arg -and $MyInvocation.Line -match '^runproj(\S+)$') { $arg = $matches[1] }
    
    if ($arg) {
        $match = $script:ProjectPattern.Match($arg)
        if ($match.Success) {
            $num = [int]$match.Groups[1].Value
            $suffix = $match.Groups[2].Value
            Run-Project ("project{0:D2}$suffix" -f $num)
        } else { Run-Project $arg }
    } else { Run-Project }
}

Set-Alias useproj Use-Project
Set-Alias newproj New-Project

function lsproj { 
    Get-ChildItem $Base -Directory -Name | Where-Object { $_ -ne "project00" } | Sort-Object 
}

function editproj {
    param([string]$name)
    if (-not $name) {
        if (Test-Path $CurrentFile) { $name = (Get-Content -Raw $CurrentFile).Trim() }
        else { throw "No current project set." }
    }
    $projectPath = Join-Path $Base $name
    if (!(Test-Path $projectPath)) { throw "Project '$name' doesn't exist." }
    $code = Get-Command code -ErrorAction SilentlyContinue
    if ($code) { & $code $projectPath } else { Start-Process $projectPath }
}

# Create p01-p99 shortcuts
1..99 | ForEach-Object { 
    $nn = "{0:D2}" -f $_
    Set-Item "Function:\p$nn" ([ScriptBlock]::Create("Run-Project 'project$nn'"))
}

# Lazy-load p001-p999
if (-not $ExecutionContext.InvokeCommand.PreCommandLookupAction) {
    $ExecutionContext.InvokeCommand.PreCommandLookupAction = {
        param($CommandName, $CommandLookupEventArgs)
        if ($CommandName -match '^p(\d{3})$' -and [int]$matches[1] -le 999) {
            $nn = "{0:D3}" -f [int]$matches[1]
            $sb = [ScriptBlock]::Create("Run-Project 'project$nn'")
            Set-Item "Function:\p$nn" $sb
            $CommandLookupEventArgs.CommandScriptBlock = $sb
        }
    }
}

function p { param([string]$n) if ($n) { runproj $n } else { Run-Project } }

function Clear-ProjectCache { 
    $script:ValidatedProjects.Clear()
    Write-Host "Project validation cache cleared" -ForegroundColor Yellow 
}

# Show which project is current
function whichproj { 
    if (Test-Path $CurrentFile) { (Get-Content -Raw $CurrentFile).Trim() } else { '(none)' } 
}

# Quick new+use in one go
function mkuse { 
    param([string]$name) 
    New-Project $name
    Use-Project $name 
}

# Quick reload: . $PROFILE

# ═══════════════════════════════════════════════════════════════════════════════
# 🎯 Quick Reference:
#   mkuse myproject     → Create + switch to project  
#   p03                 → Run project03
#   runproj 13a         → Run project13a
#   whichproj           → Show current project
#   editproj            → Open current project in VS Code
#   lsproj              → List all projects
# ═══════════════════════════════════════════════════════════════════════════════