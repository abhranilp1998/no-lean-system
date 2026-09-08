param([string]$BaseRef = 'origin/main')

$ErrorActionPreference = 'Stop'

function Invoke-ReviewCheck {
    param([string]$Program, [string[]]$Arguments)
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Review check failed: $Program $($Arguments -join ' ')"
    }
}

Invoke-ReviewCheck 'git' @('diff', '--check')
Invoke-ReviewCheck 'dart' @('format', '--output=none', '--set-exit-if-changed', 'lib', 'test', 'tool')
Invoke-ReviewCheck 'dart' @('analyze', '--fatal-infos')
Invoke-ReviewCheck 'flutter' @('test')
Invoke-ReviewCheck 'flutter' @('build', 'apk', '--debug')
Invoke-ReviewCheck 'dart' @('tool/release_version.dart', 'check', "--base-ref=$BaseRef")
Write-Output 'Automated review checks passed. Record device validation and review the final diff before merging.'
