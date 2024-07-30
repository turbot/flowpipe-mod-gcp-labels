trigger "query" "detect_and_correct_artifact_registry_repositories_with_incorrect_labels" {
  title         = "Detect & correct Artifact registry repositories with incorrect labels"
  description   = "Detects Artifact registry repositories with incorrect labels and optionally attempts to correct them."
  tags          = local.artifact_registry_common_tags

  enabled  = var.artifact_registry_repositories_with_incorrect_labels_trigger_enabled
  schedule = var.artifact_registry_repositories_with_incorrect_labels_trigger_schedule
  database = var.database
  sql      = local.artifact_registry_repositories_with_incorrect_labels_query

  capture "insert" {
    pipeline = pipeline.correct_resources_with_incorrect_labels
    args = {
      items         = self.inserted_rows
      resource_type = "gcp_compute_disk"
    }
  }
}

pipeline "detect_and_correct_artifact_registry_repositories_with_incorrect_labels" {
  title         = "Detect & correct Artifact registry repositories with incorrect labels"
  description   = "Detects Artifact registry repositories with incorrect labels and optionally attempts to correct them."
  tags          = merge(local.artifact_registry_common_tags, { type = "featured" })

  param "database" {
    type        = string
    description = local.description_database
    default     = var.database
  }

  param "notifier" {
    type        = string
    description = local.description_notifier
    default     = var.notifier
  }

  param "notification_level" {
    type        = string
    description = local.description_notifier_level
    default     = var.notification_level
  }

  param "approvers" {
    type        = list(string)
    description = local.description_approvers
    default     = var.approvers
  }

  param "default_action" {
    type        = string
    description = local.description_default_action
    default     = var.incorrect_labels_default_action
  }

  step "query" "detect" {
    database = param.database
    sql      = local.artifact_registry_repositories_with_incorrect_labels_query
  }

  step "pipeline" "correct" {
    pipeline = pipeline.correct_resources_with_incorrect_labels
    args = {
      items              = step.query.detect.rows
      resource_type      = "gcp_compute_disk"
      notifier           = param.notifier
      notification_level = param.notification_level
      approvers          = param.approvers
      default_action     = param.default_action
    }
  }
}

variable "artifact_registry_repositories_label_rules" {
  type = object({
    add           = optional(map(string))
    remove        = optional(list(string))
    remove_except = optional(list(string))
    update_keys   = optional(map(list(string)))
    update_values = optional(map(map(list(string))))
  })
  description = "Resource specific label rules"
  default     = null
}

variable "artifact_registry_repositories_with_incorrect_labels_trigger_enabled" {
  type        = bool
  default     = false
  description = "If true, the trigger is enabled."
}

variable "artifact_registry_repositories_with_incorrect_labels_trigger_schedule" {
  type        = string
  default     = "15m"
  description = "The schedule on which to run the trigger if enabled."
}

locals {
  artifact_registry_repositories_label_rules = {
    add           = merge(local.base_label_rules.add, try(var.artifact_registry_repositories_label_rules.add, {})) 
    remove        = distinct(concat(local.base_label_rules.remove , try(var.artifact_registry_repositories_label_rules.remove, [])))
    remove_except = distinct(concat(local.base_label_rules.remove_except , try(var.artifact_registry_repositories_label_rules.remove_except, [])))
    update_keys   = merge(local.base_label_rules.update_keys, try(var.artifact_registry_repositories_label_rules.update_keys, {}))
    update_values = merge(local.base_label_rules.update_values, try(var.artifact_registry_repositories_label_rules.update_values, {}))
  }
}

locals {
  artifact_registry_repositories_update_keys_override   = join("\n", flatten([for key, patterns in local.artifact_registry_repositories_label_rules.update_keys : [for pattern in patterns : format("      when key %s '%s' then '%s'", (length(split(":", pattern)) > 1 && contains(local.operators, element(split(":", pattern), 0)) ? element(split(":", pattern), 0) : "="), (length(split(":", pattern)) > 1 && contains(local.operators, element(split(":", pattern), 0)) ? join(":", slice(split(":", pattern), 1, length(split(":", pattern)))) : pattern), key)]]))
  artifact_registry_repositories_remove_override        = join("\n", length(local.artifact_registry_repositories_label_rules.remove) == 0 ? ["      when new_key like '%' then false"] : [for pattern in local.artifact_registry_repositories_label_rules.remove : format("      when new_key %s '%s' then true", (length(split(":", pattern)) > 1 && contains(local.operators, element(split(":", pattern), 0)) ? element(split(":", pattern), 0) : "="), (length(split(":", pattern)) > 1 && contains(local.operators, element(split(":", pattern), 0)) ? join(":", slice(split(":", pattern), 1, length(split(":", pattern)))) : pattern))])
  artifact_registry_repositories_remove_except_override = join("\n", length(local.artifact_registry_repositories_label_rules.remove_except) == 0 ? ["      when new_key like '%' then true"] : flatten([[for key in keys(merge(local.artifact_registry_repositories_label_rules.add, local.artifact_registry_repositories_label_rules.update_keys)) : format("      when new_key = '%s' then true", key)], [for pattern in local.artifact_registry_repositories_label_rules.remove_except : format("      when new_key %s '%s' then true", (length(split(":", pattern)) > 1 && contains(local.operators, element(split(":", pattern), 0)) ? element(split(":", pattern), 0) : "="), (length(split(":", pattern)) > 1 && contains(local.operators, element(split(":", pattern), 0)) ? join(":", slice(split(":", pattern), 1, length(split(":", pattern)))) : pattern))]]))
  artifact_registry_repositories_add_override           = join(",\n", length(keys(local.artifact_registry_repositories_label_rules.add)) == 0 ? ["      (null, null)"] : [for key, value in local.artifact_registry_repositories_label_rules.add : format("      ('%s', '%s')", key, value)])
  artifact_registry_repositories_update_values_override = join("\n", flatten([for key in sort(keys(local.artifact_registry_repositories_label_rules.update_values)) : [flatten([for new_value, patterns in local.artifact_registry_repositories_label_rules.update_values[key] : [contains(patterns, "else:") ? [] : [for pattern in patterns : format("      when new_key = '%s' and value %s '%s' then '%s'", key, (length(split(": ", pattern)) > 1 && contains(local.operators, element(split(": ", pattern), 0)) ? element(split(": ", pattern), 0) : "="), (length(split(": ", pattern)) > 1 && contains(local.operators, element(split(": ", pattern), 0)) ? join(": ", slice(split(": ", pattern), 1, length(split(": ", pattern)))) : pattern), new_value)]]]), contains(flatten([for p in values(local.artifact_registry_repositories_label_rules.update_values[key]) : p]), "else:") ? [format("      when new_key = '%s' then '%s'", key, [for new_value, patterns in local.artifact_registry_repositories_label_rules.update_values[key] : new_value if contains(patterns, "else:")][0])] : []]]))
}

locals {
  artifact_registry_repositories_with_incorrect_labels_query = replace(
    replace(
      replace(
        replace(
          replace(
            replace(
              replace(
                replace(
                  replace(
                    local.labels_query_template,
                    "__TITLE__", "coalesce(name, title)"
                  ),
                  "__TABLE_NAME__", "gcp_compute_disk"
                ),
                "__ID__", "id"
              ),
              "__ZONE__", "zone"
            ),
            "__UPDATE_KEYS_OVERRIDE__", local.artifact_registry_repositories_update_keys_override
          ),
          "__REMOVE_OVERRIDE__", local.artifact_registry_repositories_remove_override
        ),
        "__REMOVE_EXCEPT_OVERRIDE__", local.artifact_registry_repositories_remove_except_override
      ),
      "__ADD_OVERRIDE__", local.artifact_registry_repositories_add_override
    ),
    "__UPDATE_VALUES_OVERRIDE__", local.artifact_registry_repositories_update_values_override
  )
}
