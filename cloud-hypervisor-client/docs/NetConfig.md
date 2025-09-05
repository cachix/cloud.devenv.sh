# NetConfig

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**tap** | Option<**String**> |  | [optional]
**ip** | Option<**String**> |  | [optional][default to 192.168.249.1]
**mask** | Option<**String**> |  | [optional][default to 255.255.255.0]
**mac** | Option<**String**> |  | [optional]
**host_mac** | Option<**String**> |  | [optional]
**mtu** | Option<**i32**> |  | [optional]
**iommu** | Option<**bool**> |  | [optional][default to false]
**num_queues** | Option<**i32**> |  | [optional][default to 2]
**queue_size** | Option<**i32**> |  | [optional][default to 256]
**vhost_user** | Option<**bool**> |  | [optional][default to false]
**vhost_socket** | Option<**String**> |  | [optional]
**vhost_mode** | Option<**String**> |  | [optional][default to Client]
**id** | Option<**String**> |  | [optional]
**pci_segment** | Option<**i32**> |  | [optional]
**rate_limiter_config** | Option<[**models::RateLimiterConfig**](RateLimiterConfig.md)> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


