pipeline "correct_resources_with_incorrect_labels" {
  title       = "Correct resources with incorrect labels"
  description = "Corrects resources with incorrect labels."

  param "items" {
    type = list(object({
      title   = string
      id      = string
      project = string
      zone    = string
      conn    = string
      remove  = list(string)
      upsert  = map(string)
    }))
    description = "The resources with incorrect labels."
  }

  param "resource_type" {
    type        = string
    description = "The type of the resources to correct."
  }

  param "notifier" {
    type        = notifier
    description = local.description_notifier
    default     = var.notifier
  }

  param "notification_level" {
    type        = string
    description = local.description_notifier_level
    default     = var.notification_level
    enum        = local.notification_level_enum
  }

  param "approvers" {
    type        = list(notifier)
    description = local.description_approvers
    default     = var.approvers
  }

  param "default_action" {
    type        = string
    description = local.description_default_action
    default     = var.incorrect_labels_default_action
    enum        = local.incorrect_labels_default_action_enum
  }

  step "pipeline" "correct_one" {
    for_each        = { for item in param.items : item.id => item }
    max_concurrency = var.max_concurrency
    pipeline        = pipeline.correct_one_resource_with_incorrect_labels
    args = {
      title              = each.value.title
      id                 = each.value.id
      zone               = each.value.zone
      project            = each.value.project
      conn               = connection.gcp[each.value.conn]
      remove             = each.value.remove
      upsert             = each.value.upsert
      resource_type      = param.resource_type
      notifier           = param.notifier
      notification_level = param.notification_level
      approvers          = param.approvers
      default_action     = param.default_action
    }
  }
}

pipeline "correct_one_resource_with_incorrect_labels" {
  title       = "Correct one resource with incorrect labels"
  description = "Corrects a single resource with incorrect labels."

  param "title" {
    type        = string
    description = "The title of the resource."
  }

  param "id" {
    type        = string
    description = "The ID of the resource."
  }

  param "zone" {
    type        = string
    description = "The zone of the resource."
  }

  param "project" {
    type        = string
    description = "The project of the resource."
  }

  param "conn" {
    type        = connection.gcp
    description = local.description_connection
  }

  param "remove" {
    type        = list(string)
    description = "The labels to remove from the resource."
  }

  param "upsert" {
    type        = map(string)
    description = "The labels to add or update on the resource."
  }

  param "resource_type" {
    type        = string
    description = "The type of the resources to correct."
  }

  param "notifier" {
    type        = notifier
    description = local.description_notifier
    default     = var.notifier
  }

  param "notification_level" {
    type        = string
    description = local.description_notifier_level
    default     = var.notification_level
    enum        = local.notification_level_enum
  }

  param "approvers" {
    type        = list(notifier)
    description = local.description_approvers
    default     = var.approvers
  }

  param "default_action" {
    type        = string
    description = local.description_default_action
    default     = var.incorrect_labels_default_action
    enum        = local.incorrect_labels_default_action_enum
  }

  step "transform" "remove_keys_display" {
    value = length(param.remove) > 0 ? format(" Labels that will be removed: %s.", join(", ", param.remove)) : ""
  }

  step "transform" "upsert_keys_display" {
    value = length(param.upsert) > 0 ? format(" Labels that will be added or updated: %s.", join(", ", [for key, value in param.upsert : format("%s=%s", key, value)])) : ""
  }

  step "transform" "name_display" {
    value = format("%s (%s/%s/%s)", param.title, param.id, param.project, param.zone)
  }

  step "pipeline" "correction" {
    pipeline = detect_correct.pipeline.correction_handler
    args = {
      notifier           = param.notifier
      notification_level = param.notification_level
      approvers          = param.approvers
      detect_msg         = format("Detected %s with incorrect labels.%s%s", step.transform.name_display.value, step.transform.upsert_keys_display.value, step.transform.remove_keys_display.value)
      default_action     = param.default_action
      enabled_actions    = ["skip", "apply"]
      actions = {
        "skip" = {
          label        = "Skip"
          value        = "skip"
          style        = local.style_info
          pipeline_ref = detect_correct.pipeline.optional_message
          pipeline_args = {
            notifier = param.notifier
            send     = param.notification_level == local.level_verbose
            text     = "Skipped ${param.title} (${param.id}/${param.project}) with incorrect labels."
          }
          success_msg = ""
          error_msg   = ""
        }
        "apply" = {
          label        = "Apply"
          value        = "apply"
          style        = local.style_ok
          pipeline_ref = pipeline.add_and_remove_resource_labels
          pipeline_args = {
            conn    = param.conn
            zone    = param.zone
            id      = param.id
            project = param.project
            type    = param.resource_type
            upsert  = param.upsert
            remove  = param.remove
          }
          success_msg = "Applied changes to labels on ${param.title}."
          error_msg   = "Error applying changes to labels on ${param.title}."
        }
      }
    }
  }
}
