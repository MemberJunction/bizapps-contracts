# Repository setup — branches, defaults, and services

## 1. Create the repository

1. Create a new GitHub repository from this template (or clone + re-init).
2. Push the initial commit to `main`.
3. Create `next` from `main` and **make `next` the default branch**
   (GitHub → Settings → General → Default branch). All feature PRs target
   `next`; `main` is only touched by release PRs.

```sh
git checkout -b next
git push -u origin next
# then set next as default in GitHub settings
```

## 2. Why two branches?

- **`next`** — integration. Feature work merges here; CI (`build.yml`,
  `changes.yml`) gates every PR. Changesets accumulate here between releases.
- **`main`** — release. A push to `main` triggers `publish.yml`, which
  versions, builds, publishes to npm, tags, and merges back into `next`.

Full flow: [branching.md](branching.md) and [publishing.md](publishing.md).

## 3. Branch protection (convention, not enforcement)

`main` intentionally stays **unprotected**: the publish workflow pushes its
version-bump commit back to `main` with the default `GITHUB_TOKEN`. The
"changes only flow `next` → `main`" rule is discipline, enforced by convention
and review. Protect `next` with required status checks if you want a hard gate
on feature PRs.

## 4. Services to connect

| Service | What to set up | Doc |
|---|---|---|
| npm | Org/scope for your packages; publish `0.0.0` placeholders; configure **Trusted Publisher** per package | [publishing.md](publishing.md) |
| GitHub Actions | Ships enabled; workflows live in `.github/workflows/` | [publishing.md](publishing.md) |
| GitHub Releases | The publish workflow tags `vX.Y.Z`; `mj app install` resolves versions from these tags | [publishing.md](publishing.md) |

## 5. Local prerequisites

Node ≥ 18, npm ≥ 10. A SQL Server database is only needed once you develop
schema/metadata against a MemberJunction instance — see
[linking-to-mj.md](linking-to-mj.md) for exactly when.
