## v0.2.0 [2024-08-21]

_What's new?_

- Added `detect_and_correct_sql_database_instances_with_incorrect_labels` pipleine for SQL Database Instance. ([#6](https://github.com/turbot/flowpipe-mod-gcp-labels/pull/6))
- Added default values for `base_label_rules`. ([#7](https://github.com/turbot/flowpipe-mod-gcp-labels/pull/7))

## v0.1.0 [2024-07-24]

_What's new?_

- Detect and correct misconfigured labels across 8 GCP resource types.
- Automatically add mandatory labels (e.g. `env`, `owner`).
- Clean up prohibited labels (e.g. `secret`, `key`).
- Reconcile shorthand or misspelled label keys to standardized keys (e.g. `cc` to `cost_center`).
- Update label values to conform to expected standards, ensuring consistency (e.g. `Prod` to `prod`).

For detailed usage information and a full list of pipelines, please see [GCP Labels Mod](https://hub.flowpipe.io/mods/turbot/gcp_labels).
