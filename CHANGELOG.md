## v0.1.0 [2024-07-24]

_What's new?_

- Detect and correct misconfigured labels across 8 GCP resource types.
- Comprehensive label management:
  - **Ensure resources have mandatory labels:**
    - Automatically add predefined labels like `environment` and `owner` if they are missing.
  - **Remove prohibited labels:**
    - Clean up labels such as `password`, `secret`, and `key` that are no longer allowed.
  - **Standardize label keys:**
    - Reconcile shorthand or misspelled label keys to standardized keys like `environment` and `cost_center`.
  - **Standardize label values:**
    - Update label values to conform to expected standards, ensuring consistency.

For detailed usage information and a full list of pipelines, please see [GCP Labels Mod](https://hub.flowpipe.io/mods/turbot/gcp_labels).