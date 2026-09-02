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
Start-Process -FilePath $installerPath -ArgumentList "--accept-licenses --default-answer --confirm-command install" -Wait

$vulkanPath = "C:\VulkanSDK\$vulkanVersion"
echo "VULKAN_SDK=$vulkanPath" >> $env:GITHUB_ENV
echo "$vulkanPath\Bin" >> $env:GITHUB_PATH
