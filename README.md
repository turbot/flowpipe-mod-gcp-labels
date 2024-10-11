# GCP Labels mod for Flowpipe

Pipelines to detect and correct GCP resource label keys and values based on a provided ruleset.

## Documentation

- **[Hub →](https://hub.flowpipe.io/mods/turbot/gcp_labels)**

## Getting Started

### Requirements

Docker daemon must be installed and running. Please see [Install Docker Engine](https://docs.docker.com/engine/install/) for more information.

### Installation

Download and install [Flowpipe](https://flowpipe.io/downloads) and [Steampipe](https://steampipe.io/downloads). Or use Brew:

```sh
brew install turbot/tap/flowpipe
brew install turbot/tap/steampipe
```

Install the GCP plugin with [Steampipe](https://steampipe.io):

```sh
steampipe plugin install gcp
```

Steampipe will automatically use your default GCP credentials. Optionally, you can [setup multiple subscriptions](https://hub.steampipe.io/plugins/turbot/gcp#multi-subscription-connections) or [configure specific GCP credentials](https://hub.steampipe.io/plugins/turbot/gcp#configuring-gcp-credentials).

Create a [`connection_import`](https://flowpipe.io/docs/reference/config-files/connection_import) resource to import your Steampipe GCP connections:

```sh
vi ~/.flowpipe/config/gcp.fpc
```

```hcl
connection_import "gcp" {
  source      = "~/.steampipe/config/gcp.spc"
  connections = ["*"]
}
```

For more information on connections in Flowpipe, please see [Managing Connections](https://flowpipe.io/docs/run/connections).

Clone the mod:

```sh
mkdir gcp-labels
cd gcp-labels
git clone git@github.com:turbot/flowpipe-mod-gcp-labels.git
```

Install the dependencies:

```sh
flowpipe mod install
```

### Configuration

To start using this mod, you may need to configure some [input variables](https://flowpipe.io/docs/build/mod-variables#input-variables).

The simplest way to do this is to copy the example file `flowipe.fpvars.example` to `flowipe.fpvars`, and then update the values as needed. Alternatively, you can pass the variables directly via the command line or environment variables. For more details on these methods, see [passing input variables](https://flowpipe.io/docs/build/mod-variables#passing-input-variables).

```sh
cp flowipe.fpvars.example flowipe.fpvars
vi flowipe.fpvars
```

Whilst most [variables](https://hub.flowpipe.io/mods/turbot/gcp_labels/variables) are set with sensible defaults, you will need to specify your own labelging rules either as a [base ruleset](#configuring-label-rules), [resource-specific ruleset](#resource-specific-label-rules) or a combination of both.

### Configuring Label Rules

The `base_label_rules` variable is an object defined as below. It allows you to specify how labels should be managed on your resources. Let's break down each attribute and how you can configure it for specific use cases.

```hcl
variable "base_label_rules" {
  type = object({
    add           = optional(map(string))
    remove        = optional(list(string))
    remove_except = optional(list(string))
    update_keys   = optional(map(list(string)))
    update_values = optional(map(map(list(string))))
  })
}
```

#### Add: Ensuring Resources Have Mandatory Labels

If you require all your resources to have a set of predefined labels, you can use the `add` attribute to apply these labels to resources that currently do not have the desired labels, along with a default value.

Let's say we want to ensure every resource has the `environment` and `owner` labels. We could write this rule as:

```hcl
base_label_rules = {
  add = {
    environment = "unknown"
    owner       = "turbie"
  }
}
```

Here, the map key is the label you want to ensure exists on your resources, and the value is the default value to apply.

#### Remove: Ensuring Resources Don't Have Prohibited Labels 

Over time, labels can accumulate on your resources for various reasons. You can use the `remove` attribute to clean up labels that are no longer wanted or allowed from your resources.

If we wanted to ensure that we didn't include `password`, `secret` or `key` labels on our resources, we could write this rule as:

```hcl
base_label_rules = {
  remove = ["password", "secret", "key"]
}
```

However, the above will only cater to exact matches on those strings. This means we may miss labels like `Password` or `ssh_key` as these labels are in a different casing or contain extraneous characters. To achieve better matching we can use patterns along with [supported operators](#supported-operators) in the format `operator:pattern`.

This would allow us to write rules which match more realistic circumstances and remove labels that contain `password`, begin with `secret`, or end with `key` regardless of the casing.

```hcl
base_label_rules = {
  remove = ["~*:password", "ilike:secret%", "~*:key$"]
}
```

This allows us to remove any labels which match any of the defined patterns.

#### Remove Except: Ensuring Resources Only Have Permitted Labels

Another approach to cleaning up your labels is to ensure that you only keep those that are desired or permitted and remove all others. You can use the `remove_except` attribute to define a list of patterns for retaining matching labels, while all other labels are removed.

Since this is the inverse behavior of `remove`, it's best to use one or the other to avoid conflicts. Both follow the same `operator:pattern` matching behavior.

Lets say we want to ensure our resources **only** have the following labels:
- `environment`
- `owner`
- `cost_center`
- Any that are prefixed with our company name `turbot`

We can write this rule as:

```hcl
base_label_rules = {
  remove_except = ["environment", "owner", "cost_center", "~:^turbot"]
}
```

Any labels which do not match one of the above patterns will be removed from the resources.

#### Update Keys: Ensuring Label Keys Are Standardized

Over time your labelging standards may change, or you may have variants of the same label that you wish to standardize. You can use the `update_keys` attribute to reconcile labels to a standardized set.

Previously, we may have used shorthand labels like `env` or `cc` which we want to reconcile to our new standard `environment` and `cost_center`. We may also have encountered common spelling errors such as `enviroment` or `cost_centre`. To standardize these labels, we can write the rule as:

```hcl
base_label_rules = {
  update_keys = {
    environment = ["env", "ilike:enviro%"]
    cost_center = ["~*:^cc$", "~*:^cost_cent(er|re)$", "~*:^costcent(er|re)$"]
  }
}
```

Behind the scenes, this works by creating a new label with the value of existing matched label and then removing the existing matched label.

#### Update Values: Ensuring Label Values Are Standardized

Just like keys, you may want to standardize the values over time or correct common typos. You can use the `update_values` attribute to reconcile values to expected standards.

This works in a similar way to `update_keys` but has an extra layer of nesting to group the updates on a per-key basis. The outer map key is the label key, the inner map key is the new value, and the patterns are used for matching the existing values.

Previously, we may have used shorthand or aliases for label values that we now want to standardize. For instance:
- For the `environment` label, any previous shorthand or aliases should be standardized to the full names.
- For the `cost_center` label, any values containing non-numeric characters should be replaced by a default cost center.
- For the `owner` label, any resources previously owned by _nathan_ or _Dave_ should now be owned by _bob_.

Let's write these rules as follows:

```hcl
base_label_rules = {
  update_values = {
    environment = {
      production        = ["~*:^prod"]
      test              = ["~*:^test", "~*:^uat$"]
      quality_assurance = ["~*:^qa$", "ilike:%qual%"]
      development       = ["~*:^dev"]
    }
    cost_center = {
      "0123456789" = ["~:[^0-9]"]
    }
    owner = {
      bob = ["~*:^nathan$", "ilike:Dave"]
    }
  }
}
```

Additionally, for a given key we can specify a default to use for the labels value when no other patterns match using a special `else:` operator. This is especially useful when you want to ensure that all values are updated to a standard without knowing all potential matches.

Let's say that we want any `environment` with a value not matching our patterns for `production`, `test` or `quality_assurance` to default to `development`. We could rewrite our rule as below:

```hcl
base_label_rules = {
  update_values = {
    environment = {
      production        = ["~*:^prod"]
      test              = ["~*:^test", "~*:^uat$"]
      quality_assurance = ["~*:^qa$", "ilike:%qual%"]
      development       = ["else:"]
    }
    cost_center = {
      "0123456789" = ["~:[^0-9]"]
    }
    owner = {
      bob = ["~*:^nathan$", "ilike:Dave"]
    }
  }
}
```

> Note: Whilst it is possible to have multiple `else:` patterns declared for any given label, only the one with the first alphabetically sorted value (inner map key) will be used.

In this configuration:

- The `environment` label values like `prod`, `qa`, and `uat` will be standardized to `production`, `quality_assurance`, and `test`, respectively. Any unmatched values will default to `development`.
- The `cost_center` label values that contain non-numeric characters will be replaced with `0123456789`.
- The `owner` label values `Nathan` and `Dave` will be changed to `bob`.

This approach ensures that all your label values are consistently updated, even when new or unexpected values are encountered.

#### Complete Label Rules

Now that you understand each of the attributes available in the `base_label_rules` object individually, you can combine them to create a complex ruleset for managing your resource labels. By leveraging multiple attributes together you can achieve sophisticated labelging strategies.

> Note: Using `remove` / `remove_except`
>
> Ideally, you should use either the `remove` or the `remove_except` attribute, but not both simultaneously. This ensures clarity in your label removal logic and avoids potential conflicts.
>
> - `remove`: Use this to specify patterns of labels you want to explicitly remove.
> - `remove_except`: Use this to specify patterns of labels you want to retain, removing all others.

When using a combination of attributes to build a complex ruleset, they will be executed in the following order to ensure logical application of the rules:

1. `update_keys`: Start by updating any incorrect keys to the new expected values.
2. `add`: Add missing mandatory labels with a default value. This is done after updating the keys to ensure that if update has the same label, the value isn't overwritten with the default but kept.
3. `remove`/`remove_except`: Remove any labels no longer required based on the patterns provided and old labels which have been updated.
4. `update_values`: Finally once the labels have been established, the values will be reconciled as desired.

Lets combine some of the above examples to create a complex ruleset.

```hcl
base_label_rules = {
  update_keys = {
    environment = ["env", "ilike:enviro%"]
    cost_center = ["cc", "~*:^cost_cent(er|re)$", "~*:^costcent(er|re)$"]
  }
  add = {
    environment = "unknown"
    owner       = "turbie"
    cost_center = "0123456789"
  }
  remove_except = [
    "environment", 
    "owner", 
    "cost_center", 
    "~:^turbot"
  ]
  update_values = {
    environment = {
      production        = ["~*:^prod"]
      test              = ["~*:^test", "~*:^uat$"]
      development       = ["~*:^dev"]
      quality_assurance = ["~*:^qa$", "ilike:%quality%"]
    }
    cost_center = {
      "0123456789" = ["~:[^0-9]"]
    }
    owner = {
      bob = ["~*:^nathan$", "ilike:Dave"]
    }
  }
}
```

This ensures that:
- Firstly, the keys are updated, so we can safely perform the next rules on those keys.
- Secondly, any missing required labels are added.
- Thirdly, any labels that are no longer required are removed.
- Finally, the values are updated as required.

#### Resource-Specific Label Rules

You have three options for defining label rules:

1. Only provide `base_label_rules`: Apply the same rules to every resource.
2. Omit `base_label_rules` and only provide resource-specific rules (e.g. `storage_buckets_label_rules`): Allow for custom rules per resource.
3. Provide both `base_label_rules` and resource-specific rules: Merge the rules to create a comprehensive ruleset.

When merging the `base_label_rules` with resource-specific rules, the following behaviors apply:

- **Maps** (e.g., `add`, `update_keys`, `update_values`): The maps from the resource-specific rules will be merged with the corresponding maps in the `base_label_rules`. If a key exists in both the base rules and the resource-specific rules, the value from the resource-specific rules will take precedence.
- **Lists** (e.g., `remove`, `remove_except`): The lists from both the base and resource-specific rules will be merged/concatenated and then deduplicated to ensure that all unique entries from both lists are included.

Let's say you have base_label_rules defined as follows:

```hcl
base_label_rules = {
  add = {
    environment = "unknown"
    cost_center = "0123456789"
    owner       = "turbie"
  }
  remove = ["~*:password", "ilike:secret%"]
  remove_except = []
  update_keys = {
    environment = ["env", "ilike:enviro%"]
    cost_center = ["cc", "~*:^cost_cent(er|re)$", "~*:^costcent(er|re)$"]
  }
  update_values = {
    environment = {
      production        = ["~*:^prod"]
      test              = ["~*:^test", "~*:^uat$"]
      development       = ["~*:^dev"]
      quality_assurance = ["~*:^qa$", "ilike:%quality%"]
    }
    cost_center = {
      "0123456789" = ["~:[^0-9]"]
    }
    owner = {
      bob = ["~*:^nathan$", "ilike:Dave"]
    }
  }
}
```

And you want to apply additional rules to storage buckets:

```hcl
storage_buckets_label_rules = {
  add = {
    resource_type = "bucket"
  }
  remove = ["ilike:secret%", "~*:key$"]
  remove_except = []
  update_keys = {
    environment = ["~*:^env"]
    owner       = ["~*:^owner$", "~*:manager$"]
  }
  update_values = {
    owner = {
      bob = ["~*:^dave$"]
    }
  }
}
```

When merged, the resulting label rules for storage buckets will be:

```hcl
{
  add = {
    environment   = "unknown"
    cost_center   = "0123456789"
    owner         = "turbie"
    resource_type = "bucket"
  }
  remove = ["~*:password", "ilike:secret%", "~*:key$"]
  remove_except = []
  update_keys = {
    environment = ["~*:^env"]
    cost_center = ["cc", "~*:^cost_cent(er|re)$", "~*:^costcent(er|re)$"]
    owner       = ["~*:^owner$", "~*:manager$"]
  }
  update_values = {
    environment = {
      production        = ["~*:^prod"]
      test              = ["~*:^test", "~*:^uat$"]
      development       = ["~*:^dev"]
      quality_assurance = ["~*:^qa$", "ilike:%quality%"]
    }
    cost_center = {
      "0123456789" = ["~:[^0-9]"]
    }
    owner = {
      bob = ["~*:^dave$"]
    }
  }
}
```

In this example:

- The `add` map includes entries from both `base_label_rules` and `storage_buckets_label_rules`.
- The `remove` list is a concatenation of entries from both lists, ensuring no duplicates (`"ilike:secret%"` appears only once).
- The `remove_except` list remains empty as specified in both rules.
- The `update_keys` map merges entries, with the resource-specific rules for environment and owner overriding the base rules entirely.
- The `update_values` map shows that the resource-specific rule for `owner` overrides the base rule for the same key.

By providing resource-specific label rules, you can customize and extend the base labelging strategy to meet the unique requirements of individual resources, ensuring flexibility and consistency in your label management.

#### Supported Operators

The below table shows the currently supported operators for pattern-matching.

| Operator | Purpose |
| -------- | ------- |
| `=`      | Case-sensitive exact match |
| `like`   | Case-sensitive pattern matching, where `%` indicates zero or more characters and `_` indicates a single character. |
| `ilike`  | Case-insensitive pattern matching, where `%` indicates zero or more characters and `_` indicates a single character. |
| `~`      | Case-sensitive pattern matching using `regex` patterns. | 
| `~*`     | Case-insensitive pattern matching using `regex` patterns. | 
| `else:`  | _Special Operator_ only supported in `update_values` to indicate that this value should be used as replacement value if no other pattern is matched. The whole value must be an _exact match_ of `else:` with no trailing information. |

If you attempt to use an operator *not* in the table above, the string will be processed as an exact match.
For example,  `!~:^bob` wouldn't match anything that doesn't begin with `bob`; instead, it would only match if the key/value is exactly `!~:^bob`.

### Running Pipelines

This mod contains a few different types of pipelines:
- `detect_and_correct`: these are the core pipelines intended for use, they will utilise [Steampipe](https://steampipe.io) queries to determine amendments to your labels based on the provided ruleset(s).
- `correct` / `correct_one`: these pipelines are designed to be fed from the `detect_and_correct` pipelines, albeit they've been separated out to allow you to utilise your own detections if desired, this is an advanced use-case however, thus won't be covered in this documentation.
- Other `utility` type pipelines such as `add_and_remove_resource_labels`, these are designed to be used by other pipelines and should only be called directly if you've read and understood the functionality.

Let's begin by looking at how to run a `detect_and_correct` pipeline, assuming you've already followed the [installation instructions](#installation) and [configured label rules](#configuring-label-rules) as required


Firstly, we need to ensure that [Steampipe](https://steampipe.io) is running in [service mode](https://steampipe.io/docs/managing/service).

```sh
steampipe service start
```

The pipeline we want to run will be `detect_and_correct_<resource_type>_with_incorrect_labels`, we can find those available by running the following command:

```sh
flowpipe pipeline list | grep "detect_and_correct"
```

Then run your chosen pipeline, for example if we wish to remediate labels on our `storage buckets`:
```sh
flowpipe pipeline run detect_and_correct_storage_buckets_with_incorrect_labels --var-file flowipe.fpvars
```

This will then run the pipeline and depending on your configured running mode; perform the relevant action(s), there are 3 running modes:
- Wizard
- Notify
- Automatic

#### Wizard
This is the `default` running mode, allowing for a hands-on approach to approving changes to resource labels by prompting for [input](https://flowpipe.io/docs/build/input) for each resource detected violating the provided ruleset.

Whilst the out of the box default is to run the workflow directly in the terminal. You can use Flowpipe [server](https://flowpipe.io/docs/run/server) and [external integrations](https://flowpipe.io/docs/build/input) to prompt in `http`, `slack`, `teams`, etc.

#### Notify
This mode as the name implies is used purely to report detections via notifications either directly to your terminal when running in client mode or via another configured [notifier](https://flowpipe.io/docs/reference/config-files/notifier) when running in server mode for each resource that violated a labeling rule along with the suggested remedial action.

To run in `notify` mode, you will need to set the `approvers` variable to an empty list `[]` and ensure the`incorrect_labels_default_action` variable is set to `notify`, either in your fpvars file

```hcl
# flowipe.fpvars
approvers = []
incorrect_labels_default_action = "notify"
base_label_rules = ... # omitted for brevity
```

or pass the `approvers` and `default_action` arguments on the command-line.

```sh
flowpipe pipeline run detect_and_correct_storage_buckets_with_incorrect_labels --var-file flowipe.fpvars --arg='default_action=notify' --arg='approvers=[]'
```

#### Automatic
This behavior allows for a hands-off approach to remediating (or ignoring) your ruleset violations.

To run in `automatic` mode, you will need to set the `approvers` variable to an empty list `[]` and the `incorrect_labels_default_action` variable to either `skip` or `apply` in your fpvars file

```hcl
# flowipe.fpvars
approvers = []
incorrect_labels_default_action = "apply"
base_label_rules = ... # omitted for brevity
```

or pass the `default_action` argument on the command-line.

```sh
flowpipe pipeline run detect_and_correct_storage_buckets_with_incorrect_labels --var-file flowipe.fpvars --arg='default_action=apply'
```

To further enhance this approach, you can enable the pipelines corresponding [query trigger](#running-query-triggers) to run completely hands-off.

### Running Query Triggers

> Note: Query triggers require Flowpipe running in [server](https://flowpipe.io/docs/run/server) mode.

Each `detect_and_correct` pipeline comes with a corresponding [Query Trigger](https://flowpipe.io/docs/flowpipe-hcl/trigger/query), these are _disabled_ by default allowing for you to _enable_ and _schedule_ them as desired.

Let's begin by looking at how to set-up a Query Trigger to automatically resolve labelging violations with our storage buckets.

Firsty, we need to update our `flowipe.fpvars` file to add or update the following variables - if we want to run our remediation `hourly` and automatically `apply` the corrections:

```hcl
# flowipe.fpvars

storage_buckets_with_incorrect_labels_trigger_enabled  = true
storage_buckets_with_incorrect_labels_trigger_schedule = "1h"
incorrect_labels_default_action                        = "apply"

base_label_rules = ... # omitted for brevity
```

Now we'll need to start up our Flowpipe server:

```sh
flowpipe server --var-file=flowipe.fpvars
```

This will activate every hour and detect storage buckets with labelging violations and apply the corrections without further interaction!

#### Detection Differences: Query Trigger vs Pipeline

When running the `detect_and_correct` paths, there is a key difference in the detections returned when using a query trigger vs calling the pipeline.

This is due to the query trigger caching the result set, therefore once a resource has been detected, if it is skipped it will not be returned in future detections until the query trigger cache is cleared or the resource is removed by a run of the query trigger where the result is ok.

## Open Source & Contributing

This repository is published under the [Apache 2.0 license](https://www.apache.org/licenses/LICENSE-2.0). Please see our [code of conduct](https://github.com/turbot/.github/blob/main/CODE_OF_CONDUCT.md). We look forward to collaborating with you!

[Flowpipe](https://flowpipe.io) and [Steampipe](https://steampipe.io) are products produced from this open source software, exclusively by [Turbot HQ, Inc](https://turbot.com). They are distributed under our commercial terms. Others are allowed to make their own distribution of the software, but cannot use any of the Turbot trademarks, cloud services, etc. You can learn more in our [Open Source FAQ](https://turbot.com/open-source).

## Get Involved

**[Join #flowpipe on Slack →](https://turbot.com/community/join)**

Want to help but don't know where to start? Pick up one of the `help wanted` issues:

- [Flowpipe](https://github.com/turbot/flowpipe/labels/help%20wanted)
- [GCP Labels Mod](https://github.com/turbot/flowpipe-mod-gcp-labels/labels/help%20wanted)
