---
paths:
  - "CHANGELOG.md"
---

Look at what's the last tag mentioned in CHANGELOG.md, then all commit history since then.

You will explain all **functionality** or **interface** changes. Things invisible to the user shouldn't be included (eg nobody cares if we refactored some code if it does same exact thing as before. This is a document that will be used by users to know how to migrate to latest version from whichever one they are on now).

The entries should be grouped by minor version bumps with significant patches listed within each, so a user on any given version can find exactly what changed (interface-wise) since last time he updated.
