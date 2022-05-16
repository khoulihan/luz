# Luz

Displays information about electricity rate bands, including the current rate and time until the next rate. This is intended for use with Energía in Spain, where the rate changes throughout the day, but bands for any supplier can be defined in a `json` file.

```
Usage:
  luz [--chart] [--add-hours=<hours>] [--bands=<file>]
  luz edit [--bands=<file>]
  luz (-h | --help)
  luz --version

Options:
  -h --help             Show this screen.
  --version             Show version.
  --chart               Show a chart of today's rate bands.
  --add-hours=<hours>   Add the specified number of hours to the current time
  --bands=<file>        Read the band information from a file other than the default
```

The `edit` command is not yet implemented.
