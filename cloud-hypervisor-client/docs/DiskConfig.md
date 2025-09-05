# DiskConfig

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**path** | **String** |  | 
**readonly** | Option<**bool**> |  | [optional][default to false]
**direct** | Option<**bool**> |  | [optional][default to false]
**iommu** | Option<**bool**> |  | [optional][default to false]
**num_queues** | Option<**i32**> |  | [optional][default to 1]
**queue_size** | Option<**i32**> |  | [optional][default to 128]
**vhost_user** | Option<**bool**> |  | [optional][default to false]
**vhost_socket** | Option<**String**> |  | [optional]
**rate_limiter_config** | Option<[**models::RateLimiterConfig**](RateLimiterConfig.md)> |  | [optional]
**pci_segment** | Option<**i32**> |  | [optional]
**id** | Option<**String**> |  | [optional]
**serial** | Option<**String**> |  | [optional]
**rate_limit_group** | Option<**String**> |  | [optional]
**queue_affinity** | Option<[**Vec<models::VirtQueueAffinity>**](VirtQueueAffinity.md)> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


