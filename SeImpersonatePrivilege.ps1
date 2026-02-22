<#
.SYNOPSIS
    ADCS Certificate Request and Export Tool using native commands
 
.DESCRIPTION
    Requests a certificate from a specified ADCS CA using a given template,
    then exports the certificate including the private key.
 
.PARAMETER CAName
    The ADCS Certificate Authority in the format "hostname\CAName" e.g. "PVM-ADCS-01.sme.int\sme-LDNPDC1SRV-CA"
 
.PARAMETER TemplateName
    The certificate template to request, e.g. "ComputerV2"
 
.PARAMETER CertSubject
    The subject name for the certificate request (defaults to current machine name)
 
.PARAMETER ExportPath
    Local path to save the exported PFX certificate file (default: $env:TEMP)
 
.PARAMETER ExportPassword
    Password to protect the exported PFX file (default: "Password123!")
 
.EXAMPLE
    .\ADCSRequestExport.ps1 -CAName "PVM-ADCS-01.sme.int\sme-LDNPDC1SRV-CA" -TemplateName "ComputerV2"
 
#>
 
param(
    [Parameter(Mandatory=$true)]
    [string]$CAName,
 
    [Parameter(Mandatory=$true)]
    [string]$TemplateName,
 
    [string]$CertSubject = "CN=$env:COMPUTERNAME",
 
    [string]$ExportPath = "$env:TEMP",
 
    [string]$ExportPassword = "Password123!"
)
 
# Create INF request file content
$infContent = @"
[Version]
Signature="\$Windows NT\$"
 
[NewRequest]
Subject = "$CertSubject"
KeySpec = 1
KeyLength = 2048
Exportable = TRUE
MachineKeySet = TRUE
SMIME = FALSE
PrivateKeyArchive = FALSE
UserProtected = FALSE
UseExistingKeySet = FALSE
ProviderName = "Microsoft RSA SChannel Cryptographic Provider"
ProviderType = 12
RequestType = PKCS10
KeyUsage = 0xa0
 
[EnhancedKeyUsageExtension]
OID=1.3.6.1.5.5.7.3.2 ; Client Authentication
"@
 
# Write INF file
$infFile = Join-Path -Path $ExportPath -ChildPath "cert_request.inf"
$infContent | Out-File -FilePath $infFile -Encoding ascii
 
# Paths for request and response
$reqFile = Join-Path -Path $ExportPath -ChildPath "cert_request.req"
$certFile = Join-Path -Path $ExportPath -ChildPath "cert_response.cer"
 
Write-Host "[*] Requesting certificate from CA $CAName using template $TemplateName..."
 
# Submit certificate request
$submitArgs = @(
    "-submit",
    "-config", $CAName,
    "-attrib", "CertificateTemplate:$TemplateName",
    $infFile,
    $certFile
)
 
# Run certreq command
$certreqOutput = certreq @submitArgs 2>&1
if ($certreqOutput -match "RequestId:") {
    Write-Host "[+] Certificate request submitted successfully."
} else {
    Write-Error "[!] Certificate request failed:`n$certreqOutput"
    exit 1
}
 
# Import the certificate to LocalMachine\My store
Write-Host "[*] Importing certificate to LocalMachine\My store..."
Import-Certificate -FilePath $certFile -CertStoreLocation Cert:\LocalMachine\My | Out-Null
 
Start-Sleep -Seconds 3
 
# Find the imported certificate by subject
$cert = Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object { $_.Subject -eq $CertSubject } | Sort-Object NotAfter -Descending | Select-Object -First 1
 
if (-not $cert) {
    Write-Error "[!] Could not find the imported certificate."
    exit 1
}
 
Write-Host "[*] Found certificate: $($cert.Thumbprint)"
 
# Export certificate with private key to PFX
$pfxPath = Join-Path -Path $ExportPath -ChildPath "$($env:COMPUTERNAME)_$($TemplateName).pfx"
$securePwd = ConvertTo-SecureString -String $ExportPassword -Force -AsPlainText
 
Write-Host "[*] Exporting certificate with private key to $pfxPath..."
Export-PfxCertificate -Cert $cert.PSPath -FilePath $pfxPath -Password $securePwd -Force
 
Write-Host "[+] Certificate exported successfully."
Write-Host "[*] PFX Path: $pfxPath"
Write-Host "[*] Use this certificate for authentication or ticket requests."
