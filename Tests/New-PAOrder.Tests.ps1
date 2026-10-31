Describe "New-PAOrder" {

    BeforeAll {
        # copy a fake config root to the test drive
        Get-ChildItem "$PSScriptRoot\TestFiles\ConfigRoot\" | Copy-Item -Dest 'TestDrive:\' -Recurse
        $env:POSHACME_HOME = 'TestDrive:\'
        $modulePath = Join-Path $PSScriptRoot '..\Posh-ACME\Posh-ACME.psd1'
        Import-Module $modulePath -Force

        # ShouldContinue can't be mocked, so run New-PAOrder in a runspace with no
        # host, where a confirmation prompt throws instead of waiting for input.
        function Invoke-NewPAOrderNoHost([string[]]$Domain) {
            $ps = [powershell]::Create().AddScript({
                param($ModulePath, $ConfigRoot, $Domain)
                $env:POSHACME_HOME = $ConfigRoot
                Import-Module $ModulePath
                # stop before anything is sent to the server
                & (Get-Module Posh-ACME) { function script:Invoke-ACME { throw 'Invoke-ACME called' } }
                try { New-PAOrder $Domain } catch { $_.Exception.Message }
            }).AddArgument($modulePath).AddArgument($TestDrive).AddArgument($Domain)
            $ps.Invoke()
            $ps.Dispose()
        }

        function Set-OrderState($Status, $RenewAfter) {
            $orderFile = Join-Path $TestDrive 'srvr1\acct1\example.com\order.json'
            $order = Get-Content $orderFile -Raw | ConvertFrom-Json
            $order.status = $Status
            $order.RenewAfter = $RenewAfter
            $order | ConvertTo-Json -Depth 5 | Out-File $orderFile
        }
    }

    It "Asks before overwriting an identical order that is <Desc>" -TestCases @(
        @{ Desc = 'still in progress';   Status = 'ready'; RenewAfter = $null }
        @{ Desc = 'not due for renewal'; Status = 'valid'; RenewAfter = '2099-01-01T00:00:00Z' }
    ) {
        Set-OrderState $Status $RenewAfter
        Invoke-NewPAOrderNoHost 'example.com' | Should -BeLike '*prompts the user*'
    }

    It "Does not ask when the domains are different" {
        Set-OrderState 'ready' $null
        Invoke-NewPAOrderNoHost 'example.com','www.example.com' | Should -Be 'Invoke-ACME called'
    }
}
