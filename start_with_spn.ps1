# EntraId App/ AzureAD App/ ServicePrincipal(SPN) should have
# - Access to DevOps
# - 'Administrator' Permission on the DevOps AgentPool

function Print-Header ($header) {
  Write-Host "`n${header}`n" -ForegroundColor Cyan
}

# Function to get access token using Service Principal
# scope: 499b84ac-1321-427f-aa17-267ca6975798 is DevOps scope variable. ref: https://learn.microsoft.com/en-us/azure/devops/organizations/accounts/manage-personal-access-tokens-via-api?view=azure-devops#configure-a-quickstart-application
function Get-AccessToken {
  param (
    [string] $clientId,
    [string] $secret,
    [string] $tenantId
  )
  $authString = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($clientId):$($secret)"))
  $requestBody = @{
    grant_type    = 'client_credentials'
    client_id     = $clientId
    client_secret = $secret
    scope         = "499b84ac-1321-427f-aa17-267ca6975798/.default"
    tenant        = $tenantId
  }

  $tokenUrl = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"
  $response = Invoke-RestMethod -Uri $tokenUrl -Method Post -Headers @{Authorization = "Basic $authString" } -Body $requestBody -ContentType "application/x-www-form-urlencoded"

  if ($response.error) {
    Write-Error "Error getting access token: $($response.error_description)"
    exit 1
  }

  return $response.access_token
}

# Validate Inputs
if (-not (Test-Path Env:AZP_URL)) {
  Write-Error "error: missing AZP_URL environment variable"
  exit 1
}

if (-not (Test-Path Env:AZP_SPN_ID)) {
  Write-Error "error: missing AZP_SPN_ID environment variable"
  exit 1
}

if (-not (Test-Path Env:AZP_SPN_SECRET)) {
  Write-Error "error: missing AZP_SPN_SECRET environment variable"
  exit 1
}

if (-not (Test-Path Env:AZP_SPN_TENANT)) {
  Write-Error "error: missing AZP_SPN_TENANT environment variable"
  exit 1
}

Print-Header "1. Setting up work directory..."
if ((Test-Path Env:AZP_WORK) -and -not (Test-Path $Env:AZP_WORK)) {
  New-Item $Env:AZP_WORK -ItemType directory | Out-Null
}

New-Item "\azp\agent" -ItemType directory | Out-Null

Set-Location agent

#Remove-Item Env:AZP_SPN_SECRET
# Let the agent ignore the token env variables
#$Env:VSO_AGENT_IGNORE = "AZP_SPN_SECRET"
    
Print-Header "1. Determining matching Azure Pipelines agent..."
##<OPEN> Code for getting Agent from DevOps
#Write-Host "Getting Package URL"
#Print-Header "Getting Access Token"
#$accessToken = Get-AccessToken -ClientId $env:AZP_SPN_ID -Secret $env:AZP_SPN_SECRET -TenantId $env:AZP_SPN_TENANT
#Write-Host "Access Token Acquired"
#
#if (-not (Test-Path Env:AZP_TOKEN_FILE)) {  
#  $Env:AZP_TOKEN_FILE = "\azp\.token"
#  $accessToken | Out-File -FilePath $Env:AZP_TOKEN_FILE
#}
#
#$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$(Get-Content ${Env:AZP_TOKEN_FILE})"))
#$package = Invoke-RestMethod -Headers @{Authorization=("Basic $base64AuthInfo")} "$(${Env:AZP_URL})/_apis/distributedtask/packages/agent?platform=win-x64&`$top=1"
#$packageUrl = $package[0].Value.downloadUrl
# Write-Host "Package URL recived"
##</CLOSE>

# NOTE: WARNING: the Agent download URL has been hardcoded here.
# The REST API For DevOps only supports PAT token auth. period.
# To get latest agent URL, navigate to: "https://dev.azure.com/<ORGANIZATION_NAME>/_apis/distributedtask/packages/agent?platform=win-x64&%60%24top=1"
# Can also refer to the releses in GitHub by Microsoft: https://github.com/microsoft/azure-pipelines-agent/releases
Write-Host "Using HardCoded Package URL"
$packageUrl = "https://vstsagentpackage.azureedge.net/agent/3.246.0/vsts-agent-win-x64-3.246.0.zip"
  
Print-Header "2. Downloading and installing Azure Pipelines agent..."
  
$wc = New-Object System.Net.WebClient
$wc.DownloadFile($packageUrl, "$(Get-Location)\agent.zip") 
  
Expand-Archive -Path "agent.zip" -DestinationPath "\azp\agent"

try {
  Print-Header "3. Configuring Azure Pipelines agent..."  
  # .\config.cmd --unattended --agent "$(if (Test-Path Env:AZP_AGENT_NAME) { ${Env:AZP_AGENT_NAME} } else { hostname })" --url "$(${Env:AZP_URL})" --auth PAT --token "$accessToken" --pool "$(if (Test-Path Env:AZP_POOL) { ${Env:AZP_POOL} } else { 'Default' })" --work "$(if (Test-Path Env:AZP_WORK) { ${Env:AZP_WORK} } else { '_work' })" --replace
  .\config.cmd --unattended --agent "$(if (Test-Path Env:AZP_AGENT_NAME) { ${Env:AZP_AGENT_NAME} } else { hostname })" --url "$(${Env:AZP_URL})" --auth SP --clientID "${Env:AZP_SPN_ID}" --clientSecret " ${Env:AZP_SPN_SECRET}" --tenantId  "${Env:AZP_SPN_TENANT}" --pool "$(if (Test-Path Env:AZP_POOL) { ${Env:AZP_POOL} } else { 'Default' })" --work "$(if (Test-Path Env:AZP_WORK) { ${Env:AZP_WORK} } else { '_work' })" --replace

  Print-Header "4. Running Azure Pipelines agent..."  
  .\run.cmd
}
finally {
  Print-Header "Cleanup. Removing Azure Pipelines agent..."  
  .\config.cmd remove --unattended --auth PAT --token "$accessToken"
}