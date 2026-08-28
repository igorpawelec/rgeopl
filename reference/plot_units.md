# Draw forest units, with context

A quick look at whatever a lookup returned, so you can see where it is
before doing anything with it. Draws the units filled and labelled, over
an optional context layer in grey.

## Usage

``` r
plot_units(
  x,
  label = NULL,
  context = NULL,
  fill = "#a8d5ba",
  border = "#3f7f5f",
  main = NULL,
  ...
)
```

## Arguments

- x:

  Units to draw: anything from \[bdl_unit()\], \[bdl_by_address()\],
  \[bdl_subareas()\] and friends, or any \`sf\` object.

- label:

  Column to label the units with. \`NULL\` picks the most specific name
  or code the table carries; \`NA\` labels nothing, which is what you
  want for hundreds of subareas.

- context:

  An \`sf\` layer drawn underneath in grey, typically the unit one level
  up. Also sets the extent, so the units are shown in place rather than
  filling the frame.

- fill, border:

  Colours for the units.

- main:

  Title. \`NULL\` builds one from the object.

- ...:

  Passed to \[graphics::plot()\].

## Value

\`x\`, invisibly.

## Examples

``` r
if (FALSE) { # \dontrun{
bircza <- bdl_unit(inspectorate = "Bircza")
plot_units(bdl_ranges(bircza), context = bircza)

turnica <- bdl_by_address("04-02-2-11")
plot_units(turnica, context = bircza)
} # }
```
