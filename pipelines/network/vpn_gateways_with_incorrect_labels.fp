trigger "query" "detect_and_correct_vpn_gateways_with_incorrect_labels" {
  title         = "Detect & correct VPN gateways with incorrect labels"
  description   = "Detects VPN gateways with incorrect labels and optionally attempts to correct them."
  tags          = local.network_common_tags

  enabled  = var.vpn_gateways_with_incorrect_labels_trigger_enabled
  schedule = var.vpn_gateways_with_incorrect_labels_trigger_schedule
  database = var.database
  sql      = local.vpn_gateways_with_incorrect_labels_query

  capture "insert" {
    pipeline = pipeline.correct_resources_with_incorrect_labels
    args = {
      items         = self.inserted_rows
      resource_type = "gcp_compute_ha_vpn_gateway"
    }
  }
}

pipeline "detect_and_correct_vpn_gateways_with_incorrect_labels" {
  title         = "Detect & correct VPN gateways with incorrect labels"
  description   = "Detects VPN gateways with incorrect labels and optionally attempts to correct them."
  tags          = merge(local.network_common_tags, { type = "featured" })

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
    sql      = local.vpn_gateways_with_incorrect_labels_query
  }

  step "pipeline" "correct" {
    pipeline = pipeline.correct_resources_with_incorrect_labels
    args = {
      items              = step.query.detect.rows
      resource_type      = "gcp_compute_ha_vpn_gateway"
      notifier           = param.notifier
      notification_level = param.notification_level
      approvers          = param.approvers
      default_action     = param.default_action
    }
  }
}

variable "vpn_gateways_label_rules" {
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

variable "vpn_gateways_with_incorrect_labels_trigger_enabled" {
  type        = bool
  default     = false
  description = "If true, the trigger is enabled."
}

variable "vpn_gateways_with_incorrect_labels_trigger_schedule" {
  type        = string
  default     = "15m"
  description = "The schedule on which to run the trigger if enabled."
}

locals {
  vpn_gateways_label_rules = {
    add           = merge(local.base_label_rules.add, try(var.vpn_gateways_label_rules.add, {})) 
    remove        = distinct(concat(local.base_label_rules.remove , try(var.vpn_gateways_label_rules.remove, [])))
    remove_except = distinct(concat(local.base_label_rules.remove_except , try(var.vpn_gateways_label_rules.remove_except, [])))
    update_keys   = merge(local.base_label_rules.update_keys, try(var.vpn_gateways_label_rules.update_keys, {}))
    update_values = merge(local.base_label_rules.update_values, try(var.vpn_gateways_label_rules.update_values, {}))
  }
}

locals {
  vpn_gateways_update_keys_override   = join("\n", flatten([for key, patterns in local.vpn_gateways_label_rules.update_keys : [for pattern in patterns : format("      when key %s '%s' then '%s'", (length(split(":", pattern)) > 1 && contains(local.operators, element(split(":", pattern), 0)) ? element(split(":", pattern), 0) : "="), (length(split(":", pattern)) > 1 && contains(local.operators, element(split(":", pattern), 0)) ? join(":", slice(split(":", pattern), 1, length(split(":", pattern)))) : pattern), key)]]))
  vpn_gateways_remove_override        = join("\n", length(local.vpn_gateways_label_rules.remove) == 0 ? ["      when new_key like '%' then false"] : [for pattern in local.vpn_gateways_label_rules.remove : format("      when new_key %s '%s' then true", (length(split(":", pattern)) > 1 && contains(local.operators, element(split(":", pattern), 0)) ? element(split(":", pattern), 0) : "="), (length(split(":", pattern)) > 1 && contains(local.operators, element(split(":", pattern), 0)) ? join(":", slice(split(":", pattern), 1, length(split(":", pattern)))) : pattern))])
  vpn_gateways_remove_except_override = join("\n", length(local.vpn_gateways_label_rules.remove_except) == 0 ? ["      when new_key like '%' then true"] : flatten([[for key in keys(merge(local.vpn_gateways_label_rules.add, local.vpn_gateways_label_rules.update_keys)) : format("      when new_key = '%s' then true", key)], [for pattern in local.vpn_gateways_label_rules.remove_except : format("      when new_key %s '%s' then true", (length(split(":", pattern)) > 1 && contains(local.operators, element(split(":", pattern), 0)) ? element(split(":", pattern), 0) : "="), (length(split(":", pattern)) > 1 && contains(local.operators, element(split(":", pattern), 0)) ? join(":", slice(split(":", pattern), 1, length(split(":", pattern)))) : pattern))]]))
  vpn_gateways_add_override           = join(",\n", length(keys(local.vpn_gateways_label_rules.add)) == 0 ? ["      (null, null)"] : [for key, value in local.vpn_gateways_label_rules.add : format("      ('%s', '%s')", key, value)])
  vpn_gateways_update_values_override = join("\n", flatten([for key in sort(keys(local.vpn_gateways_label_rules.update_values)) : [flatten([for new_value, patterns in local.vpn_gateways_label_rules.update_values[key] : [contains(patterns, "else:") ? [] : [for pattern in patterns : format("      when new_key = '%s' and value %s '%s' then '%s'", key, (length(split(": ", pattern)) > 1 && contains(local.operators, element(split(": ", pattern), 0)) ? element(split(": ", pattern), 0) : "="), (length(split(": ", pattern)) > 1 && contains(local.operators, element(split(": ", pattern), 0)) ? join(": ", slice(split(": ", pattern), 1, length(split(": ", pattern)))) : pattern), new_value)]]]), contains(flatten([for p in values(local.vpn_gateways_label_rules.update_values[key]) : p]), "else:") ? [format("      when new_key = '%s' then '%s'", key, [for new_value, patterns in local.vpn_gateways_label_rules.update_values[key] : new_value if contains(patterns, "else:")][0])] : []]]))
}

locals {
  vpn_gateways_with_incorrect_labels_query = replace(
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
                  "__TABLE_NAME__", "gcp_compute_ha_vpn_gateway"
                ),
                "__ID__", "id"
              ),
              "__ZONE__", "''"
            ),
            "__UPDATE_KEYS_OVERRIDE__", local.vpn_gateways_update_keys_override
          ),
          "__REMOVE_OVERRIDE__", local.vpn_gateways_remove_override
        ),
        "__REMOVE_EXCEPT_OVERRIDE__", local.vpn_gateways_remove_except_override
      ),
      "__ADD_OVERRIDE__", local.vpn_gateways_add_override
    ),
    "__UPDATE_VALUES_OVERRIDE__", local.vpn_gateways_update_values_override
  )
}
