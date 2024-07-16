mod "gcp_labels" {
  title         = "GCP Labels"
  description   = "Run pipelines to detect and correct GCP labels which are missing, prohibited or otherwise unexpected."
  color         = "#FF9900"
  documentation = file("./README.md")
  icon          = "/images/mods/turbot/gcp-labels.svg"
  categories    = ["gcp", "labels", "public cloud"]
  opengraph {
    title       = "GCP Labels Mod for Flowpipe"
    description = "Run pipelines to detect and correct GCP labels which are missing, prohibited or otherwise unexpected."
    image       = "/images/mods/turbot/gcp-labels-social-graphic.png"
  }
  require {
    mod "github.com/turbot/flowpipe-mod-detect-correct" {
      version = "*"
    }
    mod "github.com/turbot/flowpipe-mod-gcp" {
      version = "v0.3.0-rc.0"
    }
  }
}