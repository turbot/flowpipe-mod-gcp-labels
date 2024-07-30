trigger "query" "detect_and_correct_dns_managed_zones_with_incorrect_labels" {
  title         = "Detect & correct Cloud DNS services with incorrect labels"
  description   = "Detects Cloud DNS services with incorrect labels and optionally attempts to correct them."
  tags          = local.storage_common_tags

  enabled  = var.dns_managed_zones_with_incorrect_labels_trigger_enabled
  schedule = var.dns_managed_zones_with_incorrect_labels_trigger_schedule
  database = var.database
  sql      = local.dns_managed_zones_with_incorrect_labels_query

  capture "insert" {
    pipeline = pipeline.correct_resources_with_incorrect_labels
    args = {
      items         = self.inserted_rows
      resource_type = "gcp_dns_managed_zone"
    }
  }
}

pipeline "detect_and_correct_dns_managed_zones_with_incorrect_labels" {
  title         = "Detect & correct Cloud DNS services with incorrect labels"
  description   = "Detects Cloud DNS services with incorrect labels and optionally attempts to correct them."
  tags          = merge(local.storage_common_tags, { type = "featured" })

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
    sql      = local.dns_managed_zones_with_incorrect_labels_query
  }

  step "pipeline" "correct" {
    pipeline = pipeline.correct_resources_with_incorrect_labels
    args = {
      items              = step.query.detect.rows
      resource_type      = "gcp_dns_managed_zone"
      notifier           = param.notifier
      notification_level = param.notification_level
      approvers          = param.approvers
      default_action     = param.default_action
    }
  }
}

variable "dns_managed_zones_label_rules" {
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

variable "dns_managed_zones_with_incorrect_labels_trigger_enabled" {
  type        = bool
  default     = false
  description = "If true, the trigger is enabled."
}

variable "dns_managed_zones_with_incorrect_labels_trigger_schedule" {
  type        = string
  default     = "15m"
  description = "The schedule on which to run the trigger if enabled."
}

locals {
  dns_managed_zones_label_rules = {
    add           = merge(local.base_label_rules.add, try(var.dns_managed_zones_label_rules.add, {})) 
    remove        = distinct(concat(local.base_label_rules.remove , try(var.dns_managed_zones_label_rules.remove, [])))
    remove_except = distinct(concat(local.base_label_rules.remove_except , try(var.dns_managed_zones_label_rules.remove_except, [])))
    update_keys   = merge(local.base_label_rules.update_keys, try(var.dns_managed_zones_label_rules.update_keys, {}))
    update_values = merge(local.base_label_rules.update_values, try(var.dns_managed_zones_label_rules.update_values, {}))
  }
}

locals {
  dns_managed_zones_update_keys_override   = join("\n", flatten([for key, patterns in local.dns_managed_zones_label_rules.update_keys : [for pattern in patterns : format("      when key %s '%s' then '%s'", (length(split(":", pattern)) > 1 && contains(local.operators, element(split(":", pattern), 0)) ? element(split(":", pattern), 0) : "="), (length(split(":", pattern)) > 1 && contains(local.operators, element(split(":", pattern), 0)) ? join(":", slice(split(":", pattern), 1, length(split(":", pattern)))) : pattern), key)]]))
  dns_managed_zones_remove_override        = join("\n", length(local.dns_managed_zones_label_rules.remove) == 0 ? ["      when new_key like '%' then false"] : [for pattern in local.dns_managed_zones_label_rules.remove : format("      when new_key %s '%s' then true", (length(split(":", pattern)) > 1 && contains(local.operators, element(split(":", pattern), 0)) ? element(split(":", pattern), 0) : "="), (length(split(":", pattern)) > 1 && contains(local.operators, element(split(":", pattern), 0)) ? join(":", slice(split(":", pattern), 1, length(split(":", pattern)))) : pattern))])
  dns_managed_zones_remove_except_override = join("\n", length(local.dns_managed_zones_label_rules.remove_except) == 0 ? ["      when new_key like '%' then true"] : flatten([[for key in keys(merge(local.dns_managed_zones_label_rules.add, local.dns_managed_zones_label_rules.update_keys)) : format("      when new_key = '%s' then true", key)], [for pattern in local.dns_managed_zones_label_rules.remove_except : format("      when new_key %s '%s' then true", (length(split(":", pattern)) > 1 && contains(local.operators, element(split(":", pattern), 0)) ? element(split(":", pattern), 0) : "="), (length(split(":", pattern)) > 1 && contains(local.operators, element(split(":", pattern), 0)) ? join(":", slice(split(":", pattern), 1, length(split(":", pattern)))) : pattern))]]))
  dns_managed_zones_add_override           = join(",\n", length(keys(local.dns_managed_zones_label_rules.add)) == 0 ? ["      (null, null)"] : [for key, value in local.dns_managed_zones_label_rules.add : format("      ('%s', '%s')", key, value)])
  dns_managed_zones_update_values_override = join("\n", flatten([for key in sort(keys(local.dns_managed_zones_label_rules.update_values)) : [flatten([for new_value, patterns in local.dns_managed_zones_label_rules.update_values[key] : [contains(patterns, "else:") ? [] : [for pattern in patterns : format("      when new_key = '%s' and value %s '%s' then '%s'", key, (length(split(": ", pattern)) > 1 && contains(local.operators, element(split(": ", pattern), 0)) ? element(split(": ", pattern), 0) : "="), (length(split(": ", pattern)) > 1 && contains(local.operators, element(split(": ", pattern), 0)) ? join(": ", slice(split(": ", pattern), 1, length(split(": ", pattern)))) : pattern), new_value)]]]), contains(flatten([for p in values(local.dns_managed_zones_label_rules.update_values[key]) : p]), "else:") ? [format("      when new_key = '%s' then '%s'", key, [for new_value, patterns in local.dns_managed_zones_label_rules.update_values[key] : new_value if contains(patterns, "else:")][0])] : []]]))
}

locals {
  dns_managed_zones_with_incorrect_labels_query = replace(
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
                  "__TABLE_NAME__", "gcp_dns_managed_zone"
                ),
                "__ID__", "id"
              ),
              "__ZONE__", "location"
            ),
            "__UPDATE_KEYS_OVERRIDE__", local.dns_managed_zones_update_keys_override
          ),
          "__REMOVE_OVERRIDE__", local.dns_managed_zones_remove_override
        ),
        "__REMOVE_EXCEPT_OVERRIDE__", local.dns_managed_zones_remove_except_override
      ),
      "__ADD_OVERRIDE__", local.dns_managed_zones_add_override
    ),
    "__UPDATE_VALUES_OVERRIDE__", local.dns_managed_zones_update_values_override
  )
}
