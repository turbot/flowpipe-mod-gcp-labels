locals {
  redis_common_tags = merge(local.gcp_labels_common_tags, {
    service = "GCP/Redis"
  })
}