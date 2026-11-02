# Contributing

This repository holds the feed software side of the ADS-B Exchange feeder image: the script
that installs and updates readsb, mlat-client and tar1090 (`update-adsbx.sh`), the files
copied over the system on every update (`skeleton/`), the boot configuration templates
(`boot-configs/`) and the helper scripts the web UI runs from its copy of this repository.
Feeders fetch updates from it directly over the network, so the branch layout is part of
how it works.

## How a feeder updates

"Update Feeder" in the web UI fetches `update-adsbx.sh` from the `main` branch of this
repository and runs it, then updates the web UI from
[adsbx-webconfig](https://github.com/ADSBexchange/adsbx-webconfig).

`update-adsbx.sh` on `main` does not update the feeder itself. It selects the release
branch that matches the device, fetches that branch's `update-adsbx.sh` and runs it:

| `VERSION_CODENAME` (`/etc/os-release`) | `NetworkManager.service` | Branch |
|---|---|---|
| `buster`, `bullseye` | not enabled | `release/8.x` |
| `bookworm` | enabled | `release/9.x` |

Any other combination stops with a message and leaves the installed software unchanged.
The release branch's script clones the same branch for `skeleton/` and `boot-configs/`.

Devices therefore always fetch `main`, and the code they end up running always comes from
a release branch.

## Branches

| Branch | Purpose |
|---|---|
| `main` | Integration. Changes merged here are not run on devices until they are promoted to a release branch, with one exception: the selection block at the top of `update-adsbx.sh` is fetched by every device on every update, so a change to it is live as soon as it is merged. Keep it small. |
| `release/9.x` | Feed software for the 9.x images (bookworm, 64-bit). Promoted from `main`. |
| `release/8.x` | Feed software for the 8.0 and 8.2 images (buster and bullseye, 32-bit). Promoted from `main`. |

Both release branches are fast-forwards of `main`; the script handles the differences
between the images itself. They are promoted separately so that a change can reach one
line before the other, after it has been tested on that line's images.

Release branches are never renamed, deleted or force-pushed. Devices depend on the names.

## Development flow

1. Branch from `main` and open a pull request against `main`.
2. Test the branch on the published images it affects. To run a checkout's script directly,
   bypassing the release-branch selection:

       sudo ADSBX_UPDATE_DISPATCH=no ADSBX_UPDATE_BRANCH=<branch> bash update-adsbx.sh

   `ADSBX_UPDATE_BRANCH` names the branch the script clones for `skeleton/` and
   `boot-configs/`; it defaults to `main`.

3. Merge. The change is on `main` but not yet on any device.
4. Promote: fast-forward the release branch to `main` and tag it.

       git checkout release/9.x && git merge --ff-only main
       git tag 9.x-$(date +%Y.%m.%d) && git push origin release/9.x --tags

   Devices run the new code the next time Update is pressed. Promote `release/8.x` the
   same way once the change has been tested on the 8.0 and 8.2 images.

Tags record what each release branch contained on a given day; a second promotion on the
same day gets a `-2`, `-3`, … suffix. Devices follow the branch tip, not the tag.

## `ADSBX_UPDATE_DISPATCH` and `ADSBX_UPDATE_BRANCH`

`update-adsbx.sh` reads both. When `ADSBX_UPDATE_DISPATCH` is `no`, the selection block
is skipped and the script runs as is. The selection block sets it, together with
`ADSBX_UPDATE_BRANCH`, when it hands off to the release branch, so a release branch's
script never selects again.

## Image builds

The image builder clones this repository for the web UI's helper scripts and runs the web
UI installer, which fetches `update-adsbx.sh` the same way a device does, so a new image
receives the release branch matching its OS.
