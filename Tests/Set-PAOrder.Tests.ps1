Describe "Set-PAOrder" {

    BeforeAll {
        # copy a fake config root to the test drive
        Get-ChildItem "$PSScriptRoot\TestFiles\ConfigRoot\" | Copy-Item -Dest 'TestDrive:\' -Recurse
        $env:POSHACME_HOME = 'TestDrive:\'
        Import-Module (Join-Path $PSScriptRoot '..\Posh-ACME\Posh-ACME.psd1') -Force
    }

    Context "Changing Profile" {

        BeforeAll {
            InModuleScope Posh-ACME { Import-PAConfig }
            Mock -ModuleName Posh-ACME Get-PAProfile {
                'profile1','profile2','profile3','profile4' | ForEach-Object { [pscustomobject]@{ Profile = $_ } }
            }
            Mock -ModuleName Posh-ACME Get-PACertificate { [pscustomobject]@{ Subject = 'CN=example.com' } }
            Mock -ModuleName Posh-ACME Export-PACertFiles {}
        }

        It "Doesn't re-export the cert files by itself" {
            Set-PAOrder -Name 'example.com' -Profile 'profile1'
            Should -Invoke Export-PACertFiles -ModuleName Posh-ACME -Times 0 -Exactly
        }

        It "Doesn't prevent re-exporting the cert files for <Setting>" -TestCases @(
            @{ Setting = 'FriendlyName';   Params = @{ FriendlyName = 'new friendly name'; Profile = 'profile2' } }
            @{ Setting = 'PfxPass';        Params = @{ PfxPass = 'newpass';                Profile = 'profile3' } }
            @{ Setting = 'PreferredChain'; Params = @{ PreferredChain = 'Some Root CA';    Profile = 'profile4' } }
        ) {
            Set-PAOrder -Name 'example.com' @Params
            Should -Invoke Export-PACertFiles -ModuleName Posh-ACME -Times 1 -Exactly
        }
    }

    Context "Changing CSR" {

        BeforeAll {
            InModuleScope Posh-ACME { Import-PAConfig }

            # turn the altname order into one that was created from a CSR
            $oldCsr = "$PSScriptRoot\TestFiles\rsa-2048-noCN-singleSAN.csr"
            $newCsr = "$PSScriptRoot\TestFiles\ec-256-wildcardCN-multiSANs.csr"
            $orderFolder = Join-Path $TestDrive 'srvr1\acct1\altname'
            $oldB64 = InModuleScope Posh-ACME -Parameters @{ Path = $oldCsr } { param($Path) (Get-CsrDetails $Path).Base64Url }
            $newB64 = InModuleScope Posh-ACME -Parameters @{ Path = $newCsr } { param($Path) (Get-CsrDetails $Path).Base64Url }
            $order = Get-Content "$orderFolder\order.json" -Raw | ConvertFrom-Json
            $order | Add-Member 'CSRBase64Url' $oldB64 -Force
            $order | ConvertTo-Json -Depth 5 | Out-File "$orderFolder\order.json"
            Copy-Item $oldCsr "$orderFolder\request.csr"

            function Get-SavedCsr {
                InModuleScope Posh-ACME -Parameters @{ Path = "$orderFolder\request.csr" } { param($Path) (Get-CsrDetails $Path).Base64Url }
            }
        }

        It "Refuses an order that wasn't created from a CSR" {
            Set-PAOrder -Name 'example.com' -CSRPath $newCsr -NoSwitch -EA SilentlyContinue -EV err
            $err | Should -BeLike '*not created from a CSR*'
            (Get-PAOrder -Name 'example.com').CSRBase64Url | Should -BeNullOrEmpty
            Join-Path $TestDrive 'srvr1\acct1\example.com\request.csr' | Should -Not -Exist
        }

        It "Changes nothing when the CSR can't be parsed" {
            # make it the current order so the in-memory copy is checked too
            Set-PAOrder -Name 'altname'
            Set-PAOrder -CSRPath "$PSScriptRoot\TestFiles\invalid.csr" -FriendlyName 'changed' -EA SilentlyContinue -EV err
            $err | Should -Not -BeNullOrEmpty
            $order = Get-PAOrder
            $order.Name | Should -Be 'altname'
            $order.CSRBase64Url | Should -Be $oldB64
            $order.FriendlyName | Should -Not -Be 'changed'
            Get-SavedCsr | Should -Be $oldB64
        }

        It "Replaces the CSR in the order and request.csr" {
            Set-PAOrder -Name 'altname' -CSRPath $newCsr -NoSwitch
            (Get-PAOrder -Name 'altname').CSRBase64Url | Should -Be $newB64
            Get-SavedCsr | Should -Be $newB64
        }

        It "Doesn't save anything when the CSR is the same" {
            Mock -ModuleName Posh-ACME Update-PAOrder {}
            Set-PAOrder -Name 'altname' -CSRPath "$orderFolder\request.csr" -NoSwitch
            Should -Invoke Update-PAOrder -ModuleName Posh-ACME -Times 0 -Exactly
        }
    }
}
