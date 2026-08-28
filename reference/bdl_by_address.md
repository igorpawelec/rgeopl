# Find a forest unit by its address

The forest address is the natural key for anything in the State Forests,
and a truncated one names a whole level: \`"04"\` is a regional
directorate, \`"04-02"\` a forest inspectorate, \`"04-02-2-11"\` a
forest range. Give as much of it as you have and the matching level
comes back.

## Usage

``` r
bdl_by_address(adr, quiet = FALSE)
```

## Arguments

- adr:

  A forest address, whole or truncated. See details for what each length
  means.

- quiet:

  Suppress progress messages.

## Value

An \`sf\` data frame in EPSG:2180, as from \[bdl_unit()\].

## Details

Padding does not matter. Both the service's own fixed-width form
(\`"09-01-2-10-187 -f -00"\`) and the way people write it
(\`"09-01-2-10-187-f"\`) are accepted.

The number of components decides what is returned:

- \`"04"\`:

  the regional directorate (RDLP)

- \`"04-02"\`:

  the forest inspectorate (nadlesnictwo)

- \`"04-02-2"\`:

  every forest range in that sub-district (obreb)

- \`"04-02-2-11"\`:

  the forest range (lesnictwo)

- \`"04-02-2-11-123"\`:

  every subarea in that compartment (oddzial)

- \`"04-02-2-11-123-a"\`:

  the single subarea (wydzielenie)

Below the forest range there is no index to query directly, so the range
is resolved first and its subareas are then filtered locally. That keeps
the request bounded: a range holds hundreds of subareas, a regional
directorate hundreds of thousands.

## See also

\[bdl_unit()\] to search by name instead.

## Examples

``` r
if (FALSE) { # \dontrun{
bdl_by_address("04-02")            # Bircza forest inspectorate
bdl_by_address("04-02-2-11")       # Turnica forest range
bdl_by_address("04-02-2-11-123-a") # one subarea
} # }
```
