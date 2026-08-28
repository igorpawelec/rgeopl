# Inspect and prune the download cache

Inspect and prune the download cache

## Usage

``` r
cache_info(group = NULL)

cache_clear(
  group = NULL,
  older_than = NULL,
  meta = FALSE,
  confirm = interactive()
)
```

## Arguments

- group:

  Restrict to one group (for example \`"dem"\`, \`"ortho"\`,
  \`"pointcloud"\`, \`"bdl"\`). \`NULL\` means all groups.

- older_than:

  Drop entries downloaded more than this many days ago. \`NULL\` means
  no age limit.

- meta:

  Also clear the cached index responses.

- confirm:

  Ask before deleting. Set to \`FALSE\` in scripts.

## Value

\`cache_info()\` a data frame, one row per cached file, with a summary
printed. \`cache_clear()\` returns the number of files removed,
invisibly.

## Examples

``` r
if (FALSE) { # \dontrun{
cache_info()
cache_clear(group = "ortho", older_than = 90, confirm = FALSE)
} # }
```
