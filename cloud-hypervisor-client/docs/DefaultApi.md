# \DefaultApi

All URIs are relative to *http://localhost/api/v1*

Method | HTTP request | Description
------------- | ------------- | -------------
[**boot_vm**](DefaultApi.md#boot_vm) | **Put** /vm.boot | Boot the previously created VM instance.
[**create_vm**](DefaultApi.md#create_vm) | **Put** /vm.create | Create the cloud-hypervisor Virtual Machine (VM) instance. The instance is not booted, only created.
[**delete_vm**](DefaultApi.md#delete_vm) | **Put** /vm.delete | Delete the cloud-hypervisor Virtual Machine (VM) instance.
[**pause_vm**](DefaultApi.md#pause_vm) | **Put** /vm.pause | Pause a previously booted VM instance.
[**power_button_vm**](DefaultApi.md#power_button_vm) | **Put** /vm.power-button | Trigger a power button in the VM
[**reboot_vm**](DefaultApi.md#reboot_vm) | **Put** /vm.reboot | Reboot the VM instance.
[**resume_vm**](DefaultApi.md#resume_vm) | **Put** /vm.resume | Resume a previously paused VM instance.
[**shutdown_vm**](DefaultApi.md#shutdown_vm) | **Put** /vm.shutdown | Shut the VM instance down.
[**shutdown_vmm**](DefaultApi.md#shutdown_vmm) | **Put** /vmm.shutdown | Shuts the cloud-hypervisor VMM.
[**vm_add_device_put**](DefaultApi.md#vm_add_device_put) | **Put** /vm.add-device | Add a new device to the VM
[**vm_add_disk_put**](DefaultApi.md#vm_add_disk_put) | **Put** /vm.add-disk | Add a new disk to the VM
[**vm_add_fs_put**](DefaultApi.md#vm_add_fs_put) | **Put** /vm.add-fs | Add a new virtio-fs device to the VM
[**vm_add_net_put**](DefaultApi.md#vm_add_net_put) | **Put** /vm.add-net | Add a new network device to the VM
[**vm_add_pmem_put**](DefaultApi.md#vm_add_pmem_put) | **Put** /vm.add-pmem | Add a new pmem device to the VM
[**vm_add_user_device_put**](DefaultApi.md#vm_add_user_device_put) | **Put** /vm.add-user-device | Add a new userspace device to the VM
[**vm_add_vdpa_put**](DefaultApi.md#vm_add_vdpa_put) | **Put** /vm.add-vdpa | Add a new vDPA device to the VM
[**vm_add_vsock_put**](DefaultApi.md#vm_add_vsock_put) | **Put** /vm.add-vsock | Add a new vsock device to the VM
[**vm_coredump_put**](DefaultApi.md#vm_coredump_put) | **Put** /vm.coredump | Takes a VM coredump.
[**vm_counters_get**](DefaultApi.md#vm_counters_get) | **Get** /vm.counters | Get counters from the VM
[**vm_info_get**](DefaultApi.md#vm_info_get) | **Get** /vm.info | Returns general information about the cloud-hypervisor Virtual Machine (VM) instance.
[**vm_receive_migration_put**](DefaultApi.md#vm_receive_migration_put) | **Put** /vm.receive-migration | Receive a VM migration from URL
[**vm_remove_device_put**](DefaultApi.md#vm_remove_device_put) | **Put** /vm.remove-device | Remove a device from the VM
[**vm_resize_put**](DefaultApi.md#vm_resize_put) | **Put** /vm.resize | Resize the VM
[**vm_resize_zone_put**](DefaultApi.md#vm_resize_zone_put) | **Put** /vm.resize-zone | Resize a memory zone
[**vm_restore_put**](DefaultApi.md#vm_restore_put) | **Put** /vm.restore | Restore a VM from a snapshot.
[**vm_send_migration_put**](DefaultApi.md#vm_send_migration_put) | **Put** /vm.send-migration | Send a VM migration to URL
[**vm_snapshot_put**](DefaultApi.md#vm_snapshot_put) | **Put** /vm.snapshot | Returns a VM snapshot.
[**vmm_nmi_put**](DefaultApi.md#vmm_nmi_put) | **Put** /vmm.nmi | Inject an NMI.
[**vmm_ping_get**](DefaultApi.md#vmm_ping_get) | **Get** /vmm.ping | Ping the VMM to check for API server availability



## boot_vm

> boot_vm()
Boot the previously created VM instance.

### Parameters

This endpoint does not need any parameter.

### Return type

 (empty response body)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## create_vm

> create_vm(vm_config)
Create the cloud-hypervisor Virtual Machine (VM) instance. The instance is not booted, only created.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**vm_config** | [**VmConfig**](VmConfig.md) | The VM configuration | [required] |

### Return type

 (empty response body)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## delete_vm

> delete_vm()
Delete the cloud-hypervisor Virtual Machine (VM) instance.

### Parameters

This endpoint does not need any parameter.

### Return type

 (empty response body)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## pause_vm

> pause_vm()
Pause a previously booted VM instance.

### Parameters

This endpoint does not need any parameter.

### Return type

 (empty response body)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## power_button_vm

> power_button_vm()
Trigger a power button in the VM

### Parameters

This endpoint does not need any parameter.

### Return type

 (empty response body)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## reboot_vm

> reboot_vm()
Reboot the VM instance.

### Parameters

This endpoint does not need any parameter.

### Return type

 (empty response body)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## resume_vm

> resume_vm()
Resume a previously paused VM instance.

### Parameters

This endpoint does not need any parameter.

### Return type

 (empty response body)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## shutdown_vm

> shutdown_vm()
Shut the VM instance down.

### Parameters

This endpoint does not need any parameter.

### Return type

 (empty response body)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## shutdown_vmm

> shutdown_vmm()
Shuts the cloud-hypervisor VMM.

### Parameters

This endpoint does not need any parameter.

### Return type

 (empty response body)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## vm_add_device_put

> models::PciDeviceInfo vm_add_device_put(device_config)
Add a new device to the VM

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**device_config** | [**DeviceConfig**](DeviceConfig.md) | The path of the new device | [required] |

### Return type

[**models::PciDeviceInfo**](PciDeviceInfo.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## vm_add_disk_put

> models::PciDeviceInfo vm_add_disk_put(disk_config)
Add a new disk to the VM

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**disk_config** | [**DiskConfig**](DiskConfig.md) | The details of the new disk | [required] |

### Return type

[**models::PciDeviceInfo**](PciDeviceInfo.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## vm_add_fs_put

> models::PciDeviceInfo vm_add_fs_put(fs_config)
Add a new virtio-fs device to the VM

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**fs_config** | [**FsConfig**](FsConfig.md) | The details of the new virtio-fs | [required] |

### Return type

[**models::PciDeviceInfo**](PciDeviceInfo.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## vm_add_net_put

> models::PciDeviceInfo vm_add_net_put(net_config)
Add a new network device to the VM

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**net_config** | [**NetConfig**](NetConfig.md) | The details of the new network device | [required] |

### Return type

[**models::PciDeviceInfo**](PciDeviceInfo.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## vm_add_pmem_put

> models::PciDeviceInfo vm_add_pmem_put(pmem_config)
Add a new pmem device to the VM

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**pmem_config** | [**PmemConfig**](PmemConfig.md) | The details of the new pmem device | [required] |

### Return type

[**models::PciDeviceInfo**](PciDeviceInfo.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## vm_add_user_device_put

> models::PciDeviceInfo vm_add_user_device_put(vm_add_user_device)
Add a new userspace device to the VM

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**vm_add_user_device** | [**VmAddUserDevice**](VmAddUserDevice.md) | The path of the new device | [required] |

### Return type

[**models::PciDeviceInfo**](PciDeviceInfo.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## vm_add_vdpa_put

> models::PciDeviceInfo vm_add_vdpa_put(vdpa_config)
Add a new vDPA device to the VM

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**vdpa_config** | [**VdpaConfig**](VdpaConfig.md) | The details of the new vDPA device | [required] |

### Return type

[**models::PciDeviceInfo**](PciDeviceInfo.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## vm_add_vsock_put

> models::PciDeviceInfo vm_add_vsock_put(vsock_config)
Add a new vsock device to the VM

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**vsock_config** | [**VsockConfig**](VsockConfig.md) | The details of the new vsock device | [required] |

### Return type

[**models::PciDeviceInfo**](PciDeviceInfo.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## vm_coredump_put

> vm_coredump_put(vm_coredump_data)
Takes a VM coredump.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**vm_coredump_data** | [**VmCoredumpData**](VmCoredumpData.md) | The coredump configuration | [required] |

### Return type

 (empty response body)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## vm_counters_get

> std::collections::HashMap<String, std::collections::HashMap<String, i64>> vm_counters_get()
Get counters from the VM

### Parameters

This endpoint does not need any parameter.

### Return type

[**std::collections::HashMap<String, std::collections::HashMap<String, i64>>**](std::collections::HashMap.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## vm_info_get

> models::VmInfo vm_info_get()
Returns general information about the cloud-hypervisor Virtual Machine (VM) instance.

### Parameters

This endpoint does not need any parameter.

### Return type

[**models::VmInfo**](VmInfo.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## vm_receive_migration_put

> vm_receive_migration_put(receive_migration_data)
Receive a VM migration from URL

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**receive_migration_data** | [**ReceiveMigrationData**](ReceiveMigrationData.md) | The URL for the reception of migration state | [required] |

### Return type

 (empty response body)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## vm_remove_device_put

> vm_remove_device_put(vm_remove_device)
Remove a device from the VM

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**vm_remove_device** | [**VmRemoveDevice**](VmRemoveDevice.md) | The identifier of the device | [required] |

### Return type

 (empty response body)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## vm_resize_put

> vm_resize_put(vm_resize)
Resize the VM

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**vm_resize** | [**VmResize**](VmResize.md) | The target size for the VM | [required] |

### Return type

 (empty response body)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## vm_resize_zone_put

> vm_resize_zone_put(vm_resize_zone)
Resize a memory zone

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**vm_resize_zone** | [**VmResizeZone**](VmResizeZone.md) | The target size for the memory zone | [required] |

### Return type

 (empty response body)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## vm_restore_put

> vm_restore_put(restore_config)
Restore a VM from a snapshot.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**restore_config** | [**RestoreConfig**](RestoreConfig.md) | The restore configuration | [required] |

### Return type

 (empty response body)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## vm_send_migration_put

> vm_send_migration_put(send_migration_data)
Send a VM migration to URL

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**send_migration_data** | [**SendMigrationData**](SendMigrationData.md) | The URL for sending the migration state | [required] |

### Return type

 (empty response body)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## vm_snapshot_put

> vm_snapshot_put(vm_snapshot_config)
Returns a VM snapshot.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**vm_snapshot_config** | [**VmSnapshotConfig**](VmSnapshotConfig.md) | The snapshot configuration | [required] |

### Return type

 (empty response body)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## vmm_nmi_put

> vmm_nmi_put()
Inject an NMI.

### Parameters

This endpoint does not need any parameter.

### Return type

 (empty response body)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## vmm_ping_get

> models::VmmPingResponse vmm_ping_get()
Ping the VMM to check for API server availability

### Parameters

This endpoint does not need any parameter.

### Return type

[**models::VmmPingResponse**](VmmPingResponse.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

