# MemoryConfig

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**size** | **i64** |  | 
**hotplug_size** | Option<**i64**> |  | [optional]
**hotplugged_size** | Option<**i64**> |  | [optional]
**mergeable** | Option<**bool**> |  | [optional][default to false]
**hotplug_method** | Option<**String**> |  | [optional][default to Acpi]
**shared** | Option<**bool**> |  | [optional][default to false]
**hugepages** | Option<**bool**> |  | [optional][default to false]
**hugepage_size** | Option<**i64**> |  | [optional]
**prefault** | Option<**bool**> |  | [optional][default to false]
**thp** | Option<**bool**> |  | [optional][default to true]
**zones** | Option<[**Vec<models::MemoryZoneConfig>**](MemoryZoneConfig.md)> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


