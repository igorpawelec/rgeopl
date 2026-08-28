# Cache location

The cache lives in the directory given by
\`getOption("rgeopl.cache_dir")\`, falling back to a per-user cache
directory. Set the option (in your \`.Rprofile\`, or per session) to put
it somewhere with room to spare, which you will want as soon as you
start pulling point clouds.

## Usage

``` r
cache_dir(create = TRUE)

cache_set_dir(path)
```

## Arguments

- create:

  Create the directory if it does not exist.

- path:

  Directory to use as the cache root.

## Value

The cache root, invisibly for \`cache_set_dir()\`.

## Examples

``` r
if (FALSE) { # \dontrun{
cache_set_dir("D:/geodata/cache")
cache_dir()
} # }
```
