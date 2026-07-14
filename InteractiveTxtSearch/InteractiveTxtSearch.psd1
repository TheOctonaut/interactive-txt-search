@{
    RootModule = 'InteractiveTxtSearch.psm1'
    ModuleVersion = '1.0.0'
    GUID = '5eb2e57b-913d-4e7d-bff6-6f76d729f3c8'
    Author = 'TheOctonaut'
    CompanyName = 'Community'
    Copyright = '(c) TheOctonaut. All rights reserved.'
    Description = 'Interactive search for case-sensitive words in .txt files across drives.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('Invoke-InteractiveTxtSearch')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('search', 'interactive', 'txt')
            ProjectUri = 'https://github.com/TheOctonaut/interactive-txt-search'
        }
    }
}
