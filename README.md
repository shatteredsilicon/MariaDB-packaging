# MariaDB RPM packaging

This repository builds the Shattered Silicon MariaDB fork as RPMs with Jenkins,
`rpmbuild`, Mock, and the `shatteredsilicon` Jenkins shared library.

## Repository layout

```text
mariadb-packaging/
├── Jenkinsfile.build
├── README.md
└── rpmbuild
    ├── SOURCES
    │   ├── 0001-Allow-building-with-flto-flag.patch
    │   └── prep-mariadb.sh
    └── SPECS
        └── MariaDB.spec
```

## Jenkins parameters

- `UPSTREAM_BRANCH`: branch in `shatteredsilicon/mariadb-server`. It is used only
  when `UPSTREAM_TAG` is empty. Branch-only builds are always build-only and are
  never published, even when `PUSH_TO_SS_MISC` is checked.
- `UPSTREAM_TAG`: tag in `shatteredsilicon/mariadb-server`, for example
  `mariadb-10.4.34`. When both branch and tag are supplied, the tag wins. The
  pipeline extracts `10.4.34` from the tag and updates both `mariadb_version` and
  `Version` in the working copy of `MariaDB.spec`.
- `EPEL`: target release `7`, `8`, `9`, or `10`. The pipeline builds x86_64 only.
- `PUSH_TO_SS_MISC`: disabled by default. When enabled for a tag build, both
  source and binary RPMs are sent through the shared-library package-signer
  workflow. When disabled, nothing is pushed.
- `THREAD_TS`: optional Slack parent thread timestamp, matching the other RPM
  packaging pipelines.

At least one of `UPSTREAM_BRANCH` and `UPSTREAM_TAG` must be supplied.

## Build targets

Each Jenkins invocation builds exactly one EL release in one Mock target:

| EPEL | Mock target | compiler ISA baseline |
| --- | --- | --- |
| 7 | `oraclelinux-7-x86_64` | x86-64-v1 (`-march=x86-64`) |
| 8 | `alma+epel-8-x86_64` | x86-64-v1 (`-march=x86-64`) |
| 9 | `alma+epel-9-x86_64` | x86-64-v2 |
| 10 | `alma+epel-10-x86_64` | x86-64-v3 |

The RPM architecture remains `x86_64`; the ISA baseline is enforced through
compiler flags in `MariaDB.spec`.

## Source selection

`rpmbuild/SOURCES/prep-mariadb.sh` receives three values from Jenkins:

```text
prep-mariadb.sh <branch|tag> <upstream-ref> <package-version>
```

The script downloads the requested `shatteredsilicon/mariadb-server` archive,
normalizes its top-level directory to the name expected by the spec, and
fetches the pinned MariaDB Connector/C and wolfSSL source archives.

For a tag build, Jenkins updates the working spec version before running the
script. For a branch-only build, the repository's current `mariadb_version` is
kept intentionally so arbitrary development branch names do not become RPM
versions. The source branch is still printed in the Jenkins build summary.

## Publishing rules

Publishing uses `rpm.publishViaSigner(...)` from the shared library. The signer
configuration credential ID is:

```text
packagesigner-mysql.conf
```

The effective publication rule is:

```text
publish = PUSH_TO_SS_MISC && source_is_tag
```

Therefore:

- branch + unchecked: build only
- branch + checked: build only
- tag + unchecked: build only
- tag + checked: publish through SS misc package signer

Build-only runs archive the generated RPMs in Jenkins so they can be downloaded
without publishing them to a package repository.

## Shared-library compatibility

No shared-library change is required. The pipeline uses the existing public
operations:

- `ci.validateRequiredParameters`
- `ci.validateBuildNode`
- `ci.prepareWorkspace`
- `ci.archiveDiagnostics`
- `ci.cleanup`
- `rpm.resolveTarget`
- `rpm.updateSpec`
- `rpm.mockBuild`
- `rpm.publishViaSigner`

Keeping MariaDB-specific policy in this repository avoids changing behavior for
Golang or the other packaging pipelines that already consume the shared
library.
