locals {
  resource_specific_pipelines = {
    gcp_storage_bucket = {
      add    = gcp.pipeline.add_labels_to_storage_bucket
      remove = gcp.pipeline.remove_labels_from_storage_bucket
      config = {id_key = "bucket_name", pass_zone = false}
    }
  }
}

pipeline "add_and_remove_resource_labels" {
  param "id" {
    type        = string
    description = "The ID of the resource."
  }

  param "project" {
    type        = string
    description = "The project of the resource."
  }

  param "cred" {
    type        = string
    description = "The credential to use when attempting to correct the resource."
  }

  param "type" {
    type        = string
    description = "The type of the resources to correct."
  }

  param "zone" {
    type        = string
    description = "The zone of the resource."
    default     = ""
  }

  param "remove" {
    type        = list(string)
    description = "The labels to remove from the resource."
  }

  param "upsert" {
    type        = map(string)
    description = "The labels to add or update on the resource."
  }

  step "transform" "upsert_config" {
    if    = length(param.upsert) > 0
    value = {
      pipeline = local.resource_specific_pipelines[param.type].add
      args     = merge({
        cred        = param.cred
        project_id  = param.project
        labels      = param.upsert
        "${local.resource_specific_pipelines[param.type].config.id_key}" = param.id
      },
      local.resource_specific_pipelines[param.type].config.pass_zone ? { zone = param.zone } : {})
    } 
  }

  step "pipeline" "upsert" {
    if    = length(param.upsert) > 0
    pipeline = step.transform.upsert_config.value.pipeline
    args     = step.transform.upsert_config.value.args
  }

  step "transform" "remove_config" {
    if    = length(param.remove) > 0
    value = {
      pipeline = local.resource_specific_pipelines[param.type].remove
      args     = merge({
        cred        = param.cred
        project_id  = param.project
        labels      = param.remove
        "${local.resource_specific_pipelines[param.type].config.id_key}" = param.id
      },
      local.resource_specific_pipelines[param.type].config.pass_zone ? { zone = param.zone } : {})
    } 
  }

  step "pipeline" "remove" {
    if    = length(param.remove) > 0
    pipeline = step.transform.remove_config.value.pipeline
    args     = step.transform.remove_config.value.args
  }
}