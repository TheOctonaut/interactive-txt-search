Set-StrictMode -Version Latest

function Invoke-InteractiveTxtSearch {
    [CmdletBinding()]
    param(
        [string]$Word,
        [string]$DriveLetter
    )

    $scriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'interactive-txt-search.ps1'
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        throw "Script not found at '$scriptPath'."
    }

    $arguments = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $scriptPath
    )

    if ($PSBoundParameters.ContainsKey('Word')) {
        $arguments += @('-Word', $Word)
    }

    if ($PSBoundParameters.ContainsKey('DriveLetter')) {
        $arguments += @('-DriveLetter', $DriveLetter)
    }

    & powershell.exe @arguments | Out-Host
    return $LASTEXITCODE
}

Export-ModuleMember -Function Invoke-InteractiveTxtSearch
