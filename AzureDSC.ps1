#region Log in and Configure Storage Account
    Add-AzureAccount

    $Subscription = (Get-AzureSubscription).where({$PSItem.SubscriptionName -eq 'LastWordInNerd'}) 
    Select-AzureSubscription -SubscriptionName $Subscription.SubscriptionName -Default

    Set-AzureSubscription -SubscriptionName $Subscription.SubscriptionName -CurrentStorageAccountName ((Get-AzureStorageAccount).where({$PSItem.StorageAccountName -eq 'lwindscdemostoracct'})).Label -PassThru

#endregion

#region Get the target Azure VM

    $AzureSMVM = Get-AzureVM -ServiceName 'lwinclassicdemo' -Name 'asmdscdemo'

#endregion

#Publish the configuration
Publish-AzureVMDscConfiguration -ConfigurationPath C:\Scripts\Configs\DPDeployAzure.ps1 -Force

#Deploy the configuration
Set-AzureVMDscExtension -ConfigurationName DSCCoreDistributionPoint -VM $AzureSMVM -ConfigurationArchive 'DPDeployAzure.ps1.zip' -Version '2.17' | Update-AzureVM


#Monitor the Configuration
(Get-AzureVMDscExtension -VM $AzureSMVM)
Get-AzureVmDscExtensionStatus -VM $AzureSMVM
Get-AzureVmDscExtensionStatus -VM $AzureSMVM | Select-Object -ExpandProperty DscConfigurationLog