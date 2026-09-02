$ErrorActionPreference = "Stop"

$vulkanVersion = $env:VULKAN_SDK_VERSION
if ([string]::IsNullOrWhiteSpace($vulkanVersion)) {
    throw "VULKAN_SDK_VERSION is not set"
}

$installerUrl = "https://sdk.lunarg.com/sdk/download/$vulkanVersion/windows/VulkanSDK-$vulkanVersion-Installer.exe"
$installerPath = "$env:TEMP\VulkanSDK-Installer.exe"

Write-Host "Downloading Vulkan SDK $vulkanVersion..."
Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath

Write-Host "Installing Vulkan SDK..."
$installer = Start-Process -FilePath $installerPath -ArgumentList "--accept-licenses --default-answer --confirm-command install" -Wait -PassThru
if ($installer.ExitCode -ne 0) {
    throw "Vulkan SDK installer failed with exit code $($installer.ExitCode)"
}

$vulkanPath = "C:\VulkanSDK\$vulkanVersion"
if (-not (Test-Path -LiteralPath "$vulkanPath\Bin")) {
    throw "Vulkan SDK was not installed at $vulkanPath"
}

echo "VULKAN_SDK=$vulkanPath" >> $env:GITHUB_ENV
echo "$vulkanPath\Bin" >> $env:GITHUB_PATH
