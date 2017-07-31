#region ConnectToAzure

    Login-AzureRmAccount

#endregion

#region SelectSubscription

    (Get-AzureRmSubscription).where({$PSItem.SubscriptionName -eq 'LastWordInNerd'}) | Set-AzureRMContext

#endregion

$baseName = 'lwinazdsc'

#region SelectResourceGroup
    
    $TargetResourceGroup = (Get-AzureRmResourceGroup).where({$PSItem.ResourceGroupName -eq $baseName})
    #$TargetResourceGroup = New-AzureRmResourceGroup -Name 'armdscdemo1' -Location 'eastus'
    $TargetResourceGroup

#endregion

#region CreateAzureDSCResgroup
    
    $AzureDSCTag = New-AzureRmTag -Name 'dscphxa' -Value 'dscdemo'
    $AzureDSCTag
    #$TargetResourceGroup = New-AzureRmResourceGroup -Name 'lwindscdemo' -Location 'westus' -Tag @{'Name' = $AzureDSCTag.Values[0].Name} -Force
    #$TargetResourceGroup = Get-AzureRmResourceGroup -Name lwindscdemo
    
#endregion

#region AzureAutomationAccount

    New-AzureRmAutomationAccount -ResourceGroupName $TargetResourceGroup.ResourceGroupName -Name $AzureDSCTag.Values[0].Name -Location 'eastus2' -Plan Free -Tags @{'Name' = $AzureDSCTag.Name}
    $AzureAutoAcct = Get-AzureRmAutomationAccount -ResourceGroupName $TargetResourceGroup.ResourceGroupName -Name $TargetResourceGroup[0].ResourceGroupName
    $AzureAutoAcct

#endregion

#region ZipDSCModules

    Set-Location C:\Users\willa\Desktop\ConceptualizeAzure\ZippedModules
    $Modules = Get-ChildItem -Filter '*.zip'
    
    ForEach ($Mod in $Modules){

        Compress-Archive -Path $Mod.PSPath -DestinationPath ((Get-Location).Path + '\' + $Mod.Name + '.zip') -Force

    }

#endregion

#region CreateBlobStore

    $ModuleStor = New-AzureRmStorageAccount -ResourceGroupName $TargetResourceGroup.ResourceGroupName -Name ($baseName + 'modules') -Location $TargetResourceGroup.Location -SkuName Standard_LRS -Verbose
    #$ModuleStor = Get-AzureRmStorageAccount -ResourceGroupName $TargetResourceGroup.ResourceGroupName -Name 'lwindscmodulestorage'
    $ModuleStor
#endregion


#region ImportDSCModules
    
    Add-AzureAccount

    #Set Azure Storage Context
    $Subscription = ((Get-AzureSubscription).where({$PSItem.SubscriptionName -eq 'LastWordInNerd'})) 
    Select-AzureSubscription -SubscriptionName $Subscription.SubscriptionName -Current
    $StorKey = (Get-AzureRmStorageAccountKey -ResourceGroupName $ModuleStor.ResourceGroupName -Name $ModuleStor.StorageAccountName).where({$PSItem.KeyName -eq 'key1'})
    $StorContext = New-AzureStorageContext -StorageAccountName $ModuleStor.StorageAccountName -StorageAccountKey $StorKey.Value
    $Container = New-AzureStorageContainer -Name ($baseName + 'dscmods') -Permission Blob -Context $StorContext
    #$Container = Get-AzureStorageContainer -Name 'lwindscmodules' -Context $StorContext

    #Get-AzureStorageBlobContent 
    $ModuleArchive = Get-ChildItem -Filter "*.zip"
    
    ForEach ($Mod in $ModuleArchive){
        
        $Blob = Set-AzureStorageBlobContent -Context $StorContext -Container $Container.Name -File $Mod.FullName
        
        New-AzureRmAutomationModule -ResourceGroupName $ModuleStor.ResourceGroupName -AutomationAccountName $AzureAutoAcct.AutomationAccountName -Name ($Mod.Name).Replace('.zip','') -ContentLink $Blob.ICloudBlob.Uri.AbsoluteUri -Verbose

    }

     

#endregion

#region ImportDSCConfiguration

    Import-AzureRmAutomationDscConfiguration -SourcePath C:\Users\willa\Desktop\ConceptualizeAzure\Configuration\DemoConfiguration.ps1 -Description 'DSC Demo Configuration' -AutomationAccountName $AzureAutoAcct.AutomationAccountName -ResourceGroupName $TargetResourceGroup.ResourceGroupName -Published -Verbose
    

#endregion

#region CompileTheConfiguration
    $cred = Get-AzureRmAutomationCredential -Name 'lwinadmin' -ResourceGroupName $AzureAutoAcct.ResourceGroupName -AutomationAccountName $AzureAutoAcct.AutomationAccountName
    
    $Parameters = @{

        'DomainName' = 'lwin.local'
        'AdminCreds' = $cred
    }
    

    $DSCComp = Start-AzureRmAutomationDscCompilationJob -AutomationAccountName $AzureAutoAcct.AutomationAccountName -ConfigurationName DemoConfiguration -ResourceGroupName $TargetResourceGroup.ResourceGroupName -Verbose -Parameters $Parameters
    Get-AzureRmAutomationDscCompilationJob -Id $DSCComp.Id -ResourceGroupName $TargetResourceGroup.ResourceGroupName -AutomationAccountName $AzureAutoAcct.AutomationAccountName
    $DSCCompOutput = Get-AzureRmAutomationDscCompilationJobOutput -Id $DSCComp.Id -ResourceGroupName $TargetResourceGroup.ResourceGroupName -AutomationAccountName $AzureAutoAcct.AutomationAccountName
    $DSCCompOutput.summary


#endregion

#region RegisterTarget

    $VM = Get-AzureRmVM -ResourceGroupName $TargetResourceGroup.resourceGroupName -Name 'lwindsctgt2'
    $VM
    
    
    $Registration = $AzureAutoAcct | Get-AzureRmAutomationRegistrationInfo
    $Registration

    $PrivateConfiguration = @{
            RegistrationKey = $Registration.PrimaryKey
        }
    

    Register-AzureRmAutomationDscNode -AzureVMName $VM.Name -AutomationAccountName $AzureAutoAcct.AutomationAccountName -ResourceGroupName $AzureAutoAcct.ResourceGroupName -AzureVMResourceGroup $VM.ResourceGroupName -AzureVMLocation $VM.Location -RebootNodeIfNeeded $true
    Set-AzureRmVMExtension -ExtensionType DSC -ResourceGroupName $VM.ResourceGroupName -VMName $VM.Name -Name 'Microsoft.PowerShell.DSC' -Publisher 'Microsoft.PowerShell' -ProtectedSettings $PrivateConfiguration

#endregion

#region DeployConfiguration
    
    $VMNodeInfo = Get-AzureRmAutomationDscNode -ResourceGroupName $AzureAutoAcct.ResourceGroupName -AutomationAccountName $AzureAutoAcct.AutomationAccountName
    
    $Configs = Get-AzureRmAutomationDscNodeConfiguration -AutomationAccountName $AzureAutoAcct.AutomationAccountName -ResourceGroupName $AzureAutoAcct.ResourceGroupName
    
    Set-AzureRmAutomationDscNode -AutomationAccountName $AzureAutoAcct.AutomationAccountName -NodeConfigurationName ($Configs.ConfigurationName | Select-Object -First 1 ) -ResourceGroupName $AzureAutoAcct.ResourceGroupName -Id $VMNodeInfo.Id


    (Get-AzureRmVMDscExtensionStatus -ResourceGroupName $VM.ResourceGroupName -VMName $VM.Name).DscConfigurationLog
#endregion
