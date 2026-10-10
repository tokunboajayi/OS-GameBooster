Describe "GameBooster Script Validation" {
    Context "File Integrity" {
        It "Should have GameBooster.ps1 in the root directory" {
            $path = Join-Path $PSScriptRoot "..\GameBooster.ps1"
            Test-Path $path | Should -Be $true
        }
    }
}
