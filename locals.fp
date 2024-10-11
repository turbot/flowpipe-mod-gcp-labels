locals {
  gcp_labels_common_tags = {
    category = "labels"
    plugin   = "gcp"
    service  = "GCP"
  }
}

// Consts
locals {
  level_verbose = "verbose"
  level_info    = "info"
  level_error   = "error"
  style_ok      = "ok"
  style_info    = "info"
  style_alert   = "alert"
}

// Common Texts
locals {
  description_database         = "Database connection string."
  description_approvers        = "List of notifiers to be used for obtaining action/approval decisions."
  description_connection       = "Name of the GCP connection to be used for any authenticated actions."
  description_max_concurrency  = "The maximum concurrency to use for responding to detection items."
  description_notifier         = "The name of the notifier to use for sending notification messages."
  description_notifier_level   = "The verbosity level of notification messages to send. Valid options are 'verbose', 'info', 'error'."
  description_default_action   = "The default action to use for the detected item, used if no input is provided."
  description_enabled_actions  = "The list of enabled actions to provide to approvers for selection."
  description_trigger_enabled  = "If true, the trigger is enabled."
  description_trigger_schedule = "The schedule on which to run the trigger if enabled."
}

// Pipeline References
locals {
  pipeline_optional_message    = detect_correct.pipeline.optional_message
}

locals {
  base_label_rules = {
    add           = try(var.base_label_rules.add, {})
    remove        = try(var.base_label_rules.remove, [])
    remove_except = try(var.base_label_rules.remove_except, [])
    update_keys   = try(var.base_label_rules.update_keys, {})
    update_values = try(var.base_label_rules.update_values, {})
  }
}

locals {
  operators = ["~", "~*", "like", "ilike", "="]
  labels_query_template = <<-EOF
with original_labels as (
  select
    __TITLE__ as title,
    __ID__ as id,
    project,
    sp_connection_name as conn,
    __ZONE__ as zone,
    coalesce(labels, '{}'::jsonb) as labels,
    l.key,
    l.value
  from
    __TABLE_NAME__
  left join
    jsonb_each_text(labels) as l(key,value) on true
),
updated_labels as (
  select
    id,
    key as old_key,
    case
      when false then key
__UPDATE_KEYS_OVERRIDE__
      else key
    end as new_key,
    value
  from
    original_labels
),
required_labels as (
  select
    r.id,
    null as old_key,
    a.key as new_key,
    a.value
  from
    (select distinct __ID__ as id from __TABLE_NAME__) r
  cross join (
    values
__ADD_OVERRIDE__
  ) as a(key, value)
  where not exists (
    select 1 from updated_labels ul where ul.id = r.id and ul.new_key = a.key
  )
),
all_labels as (
  select id, old_key, new_key, value from updated_labels
  union all
  select id, old_key, new_key, value from required_labels where new_key is not null
),
allowed_labels as (
  select distinct
    id,
    new_key
  from (
    select
      id,
      new_key,
      case
__REMOVE_EXCEPT_OVERRIDE__
        else false
      end as allowed
    from all_labels
  ) a
  where allowed = true
),
remove_labels as (
  select distinct id, key from (
    select
      id,
      new_key as key,
      case
__REMOVE_OVERRIDE__
        else false
      end   as remove
    from all_labels) r
    where remove = true
  union
  select id, old_key as key from all_labels where old_key is not null and old_key != new_key
  union
  select id, new_key as key from all_labels a where not exists (select 1 from allowed_labels al where al.id = a.id and al.new_key = a.new_key)
),
updated_values as (
  select
    id,
    new_key,
    value as old_value,
    case
      when false then value
__UPDATE_VALUES_OVERRIDE__
      else value
    end as updated_value
  from
    all_labels
)
select * from (
  select
    l.title,
    l.id::text,
    l.project,
    l.zone,
    l.conn,
    coalesce((select jsonb_agg(key) from remove_labels rl where rl.id = l.id and key is not null), '[]'::jsonb) as remove,
    coalesce((select jsonb_object_agg(al.new_key, al.value) from all_labels al where al.id = l.id and al.new_key != coalesce(al.old_key, '') and not exists (
      select 1 from remove_labels rl where rl.id = al.id and rl.key = al.new_key
    )), '{}'::jsonb) || coalesce((select jsonb_object_agg(uv.new_key, uv.updated_value) from updated_values uv where uv.id = l.id and uv.updated_value != uv.old_value and not exists (
      select 1 from remove_labels rl where rl.id = uv.id and rl.key = uv.new_key
    )), '{}'::jsonb) as upsert
  from
    original_labels l
  group by l.title, l.id, l.project, l.zone, l.conn
) result
where remove != '[]'::jsonb or upsert != '{}'::jsonb;
  EOF
}
