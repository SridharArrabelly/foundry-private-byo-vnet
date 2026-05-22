// The Foundry project exposes `properties.internalId` as a 32-char unhyphenated
// string. Some downstream RBAC conditions (Storage Blob Data Owner scope
// condition for `*-azureml-agent` containers) require the hyphenated GUID form.
// This module reformats it.

@description('Project internalId (32 hex chars, no hyphens)')
param projectWorkspaceId string

var part1 = substring(projectWorkspaceId, 0, 8)
var part2 = substring(projectWorkspaceId, 8, 4)
var part3 = substring(projectWorkspaceId, 12, 4)
var part4 = substring(projectWorkspaceId, 16, 4)
var part5 = substring(projectWorkspaceId, 20, 12)

output projectWorkspaceIdGuid string = '${part1}-${part2}-${part3}-${part4}-${part5}'
