# Runtime provenance

The Herden Host runtime began from an unmodified checkout of
[`herdrdev/herdr`](https://github.com/herdrdev/herdr) at commit
`702aa1e45527509bec73dad9b8d443f449c0379b` on 7 September 2026. That exact
upstream commit and its complete ancestry are connected to Herden's history as
a merge parent.

The runtime was last synchronized to upstream commit
`425c86179791cd32e2d4ce0ae7f269940b4b0663` (Herdr 0.9.0 plus subsequent
mainline commits) on 10 September 2026. Upstream is merged with Git's subtree
strategy so its repository root maps only to Herden's `runtime/` directory.

It was imported directly from that public upstream repository. It was not
copied from the customized `3loc/herdr` fork, so that fork's private Notes and
Vim-keyboard changes are not present here.

The upstream runtime is licensed under the Apache License 2.0. Its complete
license text remains at [LICENSE](LICENSE). Herden's changes to the runtime are
maintained in this repository with the upstream copyright and attribution
intact.
