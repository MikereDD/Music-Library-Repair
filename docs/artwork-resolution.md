# Artwork Resolution

## Resolution order

The intended preference order is:

```text
Existing trustworthy embedded artwork
→ Local album artwork
→ Exact MusicBrainz release + Cover Art Archive front image
→ User-supplied external image
→ Explicit COVER MISSING state
```

## Embedded recovery

If at least one track contains usable embedded artwork, v0.6 can extract it, validate/convert it, cache it, and reuse it consistently across the album.

## Online lookup

v0.6 searches MusicBrainz for release candidates and requires the user to select an exact release.

The selected release MBID is then used for a Cover Art Archive lookup.

The plan records:

- cover source
- selected MusicBrainz release ID
- cached image path

## Important rule

A merely similar cover is not a successful resolution.

Different editions, countries, reissues, vinyl pressings, deluxe versions, and CD/DVD packages can have different artwork or media layouts. Ambiguity must remain visible.

## Known v0.6 UX issue

If the selected exact MusicBrainz release has no Cover Art Archive front image, the current resolver returns to the album flow.

A future revision should allow the user to remain in the candidate-selection flow and try another exact release without restarting the whole cover action.

## Future improvements

- show release media breakdown
- stronger ranking by date/country/media/track count
- display barcode/label/catalog number where useful
- preview downloaded art before final acceptance
- optional secondary authoritative art providers
