param(
    [string]$Word,
    [string]$DriveLetter
)

Set-StrictMode -Version Latest

$excludedFolderNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
@(
    'Windows',
    'System',
    'System32',
    'System Volume Information',
    '$Recycle.Bin',
    'Recovery',
    'Program Files',
    'Program Files (x86)',
    'ProgramData',
    'PerfLogs',
    'MSOCache'
) | ForEach-Object { [void]$excludedFolderNames.Add($_) }

$dismissedDirectories = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

function Test-IsExcludedPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $segments = $Path.TrimEnd('\') -split '\\'
    foreach ($segment in $segments) {
        if ($excludedFolderNames.Contains($segment)) {
            return $true
        }
    }

    return $false
}

function Test-IsUnderDismissedDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $normalizedPath = $Path.TrimEnd('\')
    foreach ($dismissedDirectory in $dismissedDirectories) {
        if ($normalizedPath.Equals($dismissedDirectory, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }

        if ($normalizedPath.StartsWith($dismissedDirectory + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    return $false
}

function Get-AncestorDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 10)]
        [int]$Levels
    )

    $current = $Path.TrimEnd('\')
    for ($level = 0; $level -lt $Levels; $level++) {
        $parent = Split-Path -Path $current -Parent
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $current) {
            return $null
        }

        $current = $parent.TrimEnd('\')
    }

    return $current
}

function Add-WorkItem {
    param(
       [AllowEmptyCollection()]
        [Parameter(Mandatory = $true)]
        [System.Collections.Generic.List[pscustomobject]]$WorkItems,
 
       [AllowEmptyCollection()]
        [Parameter(Mandatory = $true)]
        [System.Collections.Generic.HashSet[string]]$SeenPaths,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [bool]$Recurse
    )

    if (-not (Test-Path -LiteralPath $Path -ErrorAction SilentlyContinue)) {
        return
    }

    if (Test-IsExcludedPath -Path $Path) {
        return
    }

    $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue).Path
    if (-not $resolved) {
        return
    }

    if ($SeenPaths.Add($resolved)) {
        $WorkItems.Add([pscustomobject]@{
                Path    = $resolved
                Recurse = $Recurse
            })
    }
}

function Get-SearchWorkItems {
    $workItems = [System.Collections.Generic.List[pscustomobject]]::new()
    $seenPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $drives = Get-CimInstance Win32_LogicalDisk -ErrorAction Stop |
    Where-Object { $_.DriveType -in 2, 3 } |
    Sort-Object -Property DeviceID

    if (-not [string]::IsNullOrWhiteSpace($DriveLetter)) {
        $normalizedDriveLetter = $DriveLetter.Trim().TrimEnd(':').ToUpperInvariant()
        $drives = $drives | Where-Object { $_.DeviceID -eq ($normalizedDriveLetter + ':') }

        if (-not $drives) {
            Write-Host ("Drive '{0}' was not found or is not a supported local/removable drive." -f $DriveLetter) -ForegroundColor Yellow
            exit 1
        }
    }

    foreach ($drive in $drives) {
        $root = '{0}\' -f $drive.DeviceID
        $usersRoot = Join-Path -Path $root -ChildPath 'Users'

        if (Test-Path -LiteralPath $usersRoot) {
            $profiles = Get-ChildItem -LiteralPath $usersRoot -Directory -Force -ErrorAction SilentlyContinue
            foreach ($profile in $profiles) {
                foreach ($folderName in @('Desktop', 'Documents', 'Downloads', 'OneDrive', 'Pictures', 'Videos', 'Music')) {
                    Add-WorkItem -WorkItems $workItems -SeenPaths $seenPaths -Path (Join-Path -Path $profile.FullName -ChildPath $folderName) -Recurse $true
                }

                Get-ChildItem -LiteralPath $profile.FullName -Directory -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like 'OneDrive*' } |
                ForEach-Object {
                    Add-WorkItem -WorkItems $workItems -SeenPaths $seenPaths -Path $_.FullName -Recurse $true
                }
            }
        }

        Add-WorkItem -WorkItems $workItems -SeenPaths $seenPaths -Path $root -Recurse $false

        $topLevelDirs = Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue
        foreach ($topLevelDir in $topLevelDirs) {
            Add-WorkItem -WorkItems $workItems -SeenPaths $seenPaths -Path $topLevelDir.FullName -Recurse $true
        }
    }

    return $workItems
}

function Get-TxtFilesPruned {
    param(
        [Parameter(Mandatory = $true)]
        [string]$StartPath,

        [Parameter(Mandatory = $true)]
        [bool]$Recurse
    )

    if (Test-IsUnderDismissedDirectory -Path $StartPath) {
        return
    }

    if (-not $Recurse) {
        Get-ChildItem -LiteralPath $StartPath -File -Filter '*.txt' -Force -ErrorAction SilentlyContinue
        return
    }

    $stack = [System.Collections.Generic.Stack[string]]::new()
    $stack.Push($StartPath)

    while ($stack.Count -gt 0) {
        $currentPath = $stack.Pop()

        if (Test-IsExcludedPath -Path $currentPath) {
            continue
        }

        if (Test-IsUnderDismissedDirectory -Path $currentPath) {
            continue
        }

        Get-ChildItem -LiteralPath $currentPath -File -Filter '*.txt' -Force -ErrorAction SilentlyContinue

        $childDirs = Get-ChildItem -LiteralPath $currentPath -Directory -Force -ErrorAction SilentlyContinue
        foreach ($childDir in $childDirs) {
            if ($childDir.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                continue
            }

            if (Test-IsExcludedPath -Path $childDir.FullName) {
                continue
            }

            if (Test-IsUnderDismissedDirectory -Path $childDir.FullName) {
                continue
            }

            $stack.Push($childDir.FullName)
        }
    }
}

function Prompt-MatchDecision {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    while ($true) {
        $choice = (Read-Host '[C] Confirm it, [D] Dismiss file, [F] Dismiss folder, [P] Dismiss parent folder, [G] Dismiss grandparent folder, [O] Open file, [Q] Quit search').Trim().ToUpperInvariant()
        switch ($choice) {
            'C' { return 'confirm' }
            'D' { return 'dismiss' }
            'F' { return 'dismiss_directory' }
            'P' { return 'dismiss_parent_directory' }
            'G' { return 'dismiss_grandparent_directory' }
            'O' {
                try {
                    Invoke-Item -LiteralPath $FilePath -ErrorAction Stop
                }
                catch {
                    Write-Warning ("Could not open file: {0}" -f $_.Exception.Message)
                }
            }
            'Q' { return 'quit' }
            default { Write-Host 'Please enter C, D, F, P, G, O, or Q.' -ForegroundColor Yellow }
        }
    }
}

if ([string]::IsNullOrWhiteSpace($Word)) {
    $Word = Read-Host 'Enter the word to search for (case-sensitive)'
}

if ([string]::IsNullOrWhiteSpace($Word)) {
    Write-Host 'No word entered. Stopping.'
    exit 1
}

if ([string]::IsNullOrWhiteSpace($DriveLetter)) {
    $DriveLetter = Read-Host 'Optional drive letter to limit the search (for example C or D). Leave blank to search all eligible drives'
}

$workItems = Get-SearchWorkItems
if ($workItems.Count -eq 0) {
    Write-Host 'No searchable drives or folders were found.'
    exit 1
}

Write-Host ("Searching for '{0}' in .txt files (case-sensitive)..." -f $Word) -ForegroundColor Cyan
Write-Host 'Priority order: common user folders first, then the rest of each drive.' -ForegroundColor DarkCyan
Write-Host ''

$workIndex = 0
foreach ($workItem in $workItems) {
    $workIndex++
    Write-Host ("[{0}/{1}] Scanning: {2}" -f $workIndex, $workItems.Count, $workItem.Path) -ForegroundColor DarkGray

    Get-TxtFilesPruned -StartPath $workItem.Path -Recurse $workItem.Recurse |
    ForEach-Object {
        $filePath = $_.FullName
        $fileDirectory = Split-Path -Path $filePath -Parent

        if (Test-IsUnderDismissedDirectory -Path $fileDirectory) {
            return
        }

        $isMatch = Select-String -LiteralPath $filePath -Pattern $Word -CaseSensitive -SimpleMatch -Quiet -ErrorAction SilentlyContinue

        if (-not $isMatch) {
            return
        }

        Write-Host ''
        Write-Host ("FOUND: {0}" -f $filePath) -ForegroundColor Green

        $decision = Prompt-MatchDecision -FilePath $filePath
        switch ($decision) {
            'confirm' {
                Write-Host ("Confirmed. Stopping search at: {0}" -f $filePath) -ForegroundColor Green
                exit 0
            }
            'quit' {
                Write-Host 'Search stopped by user.' -ForegroundColor Yellow
                exit 2
            }
            'dismiss_directory' {
                [void]$dismissedDirectories.Add($fileDirectory.TrimEnd('\'))
                Write-Host ("Folder dismissed. Skipping: {0}" -f $fileDirectory) -ForegroundColor DarkYellow
            }
            'dismiss_parent_directory' {
                $parentDirectory = Get-AncestorDirectory -Path $fileDirectory -Levels 1
                if ($null -eq $parentDirectory) {
                    Write-Host ("No parent folder available above: {0}" -f $fileDirectory) -ForegroundColor Yellow
                }
                else {
                    [void]$dismissedDirectories.Add($parentDirectory)
                    Write-Host ("Parent folder dismissed. Skipping: {0}" -f $parentDirectory) -ForegroundColor DarkYellow
                }
            }
            'dismiss_grandparent_directory' {
                $grandparentDirectory = Get-AncestorDirectory -Path $fileDirectory -Levels 2
                if ($null -eq $grandparentDirectory) {
                    Write-Host ("No grandparent folder available above: {0}" -f $fileDirectory) -ForegroundColor Yellow
                }
                else {
                    [void]$dismissedDirectories.Add($grandparentDirectory)
                    Write-Host ("Grandparent folder dismissed. Skipping: {0}" -f $grandparentDirectory) -ForegroundColor DarkYellow
                }
            }
            default {
                Write-Host 'Dismissed. Continuing search...' -ForegroundColor DarkYellow
            }
        }
    }
}

Write-Host ''
Write-Host 'Finished scanning all eligible drives and folders. No confirmed match.' -ForegroundColor Yellow
exit 3
