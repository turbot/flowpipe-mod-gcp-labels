mod "gcp_labels" {
  title         = "GCP Labels"
  description   = "Run pipelines to detect and correct GCP labels which are missing, prohibited or otherwise unexpected."
  color         = "#ea4335"
  documentation = file("./README.md")
  icon          = "/images/mods/turbot/gcp-labels.svg"
  categories    = ["gcp", "public cloud", "standard", "tags"]
  opengraph {
    title       = "GCP Labels Mod for Flowpipe"
    description = "Run pipelines to detect and correct GCP labels which are missing, prohibited or otherwise unexpected."
    image       = "/images/mods/turbot/gcp-labels-social-graphic.png"
  }
  require {
    mod "github.com/turbot/flowpipe-mod-detect-correct" {
      version = "v1.0.0-rc.0"
    }
    mod "github.com/turbot/flowpipe-mod-gcp" {
      version = "v1.0.0-rc.0"
    }
  }
}
