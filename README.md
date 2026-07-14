# interactive-txt-search

Interactive PowerShell search for a **case-sensitive word** inside `.txt` files across local/removable drives.

It scans common user folders first (`Desktop`, `Documents`, `Downloads`, `OneDrive`, etc.), then continues through the rest of each eligible drive while skipping common system folders.

## Usage

Run as script:

```powershell
.\interactive-txt-search.ps1
.\interactive-txt-search.ps1 -Word "invoice"
.\interactive-txt-search.ps1 -Word "invoice" -DriveLetter C
```

Run via installed module command:

```powershell
Import-Module InteractiveTxtSearch
Invoke-InteractiveTxtSearch -Word "invoice" -DriveLetter C
```

## Interactive options on each match

- `C` Confirm and stop at this file
- `D` Dismiss this file and continue
- `F` Dismiss this folder and all descendants
- `P` Dismiss parent folder and all descendants
- `G` Dismiss grandparent folder and all descendants
- `O` Open the file
- `Q` Quit search
