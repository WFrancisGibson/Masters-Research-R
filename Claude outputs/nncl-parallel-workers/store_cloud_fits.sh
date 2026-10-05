#!/usr/bin/env bash
## stores the age_numeric fits of the cloud run on this computer: fetches the
## branch (default age-numeric-laptop-fits) and writes its fit files to
## data/processed/ and its networks to models/nncl_synthetic_age_numeric/,
## without switching the branch of this checkout (both folders are not in
## git here); afterwards check_cloud_fits.R checks every fit against the
## laptop's cells; usage: store_cloud_fits.sh [branch] [folder, default: the
## project]
set -euo pipefail
cd "$(dirname "$0")/../.."
branch="${1:-age-numeric-laptop-fits}"
target="${2:-.}"
git fetch origin "+refs/heads/$branch:refs/remotes/origin/$branch"
echo "fit files on origin/$branch: $(git ls-tree -r --name-only \
  "origin/$branch" -- data/processed | grep -c 'age_numeric_fit_.*[.]rds$')"
folders=(data/processed)
patterns=('data/processed/nncl_synthetic_age_numeric_fit_*.rds')
if git cat-file -e "origin/$branch:models/nncl_synthetic_age_numeric" \
  2> /dev/null; then
  folders+=(models/nncl_synthetic_age_numeric)
  patterns+=('models/nncl_synthetic_age_numeric/*')
fi
mkdir -p "$target"
git archive "origin/$branch" "${folders[@]}" |
  tar -x -C "$target" --wildcards "${patterns[@]}"
echo "stored: $(find "$target/data/processed" -maxdepth 1 \
  -name 'nncl_synthetic_age_numeric_fit_*.rds' | wc -l) fit files," \
  "$(find "$target/models/nncl_synthetic_age_numeric" -type f 2> /dev/null |
    wc -l) networks"
