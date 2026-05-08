#!/usr/bin/env bash
# brand-lint.sh — Qtonic Quantum brand & content discipline.
# Hardened against false negatives flagged in QC + Runtime audits.
set -euo pipefail
ROOT="${1:-.}"
violations=0

# Cache/build directories to exclude
EXCLUDE_PATTERN='(/.pytest_cache/|/.mypy_cache/|/.ruff_cache/|/__pycache__/|/node_modules/|/dist/|/build/|/.git/|/.tox/|/.venv/|/venv/)'

set +o pipefail
files_scanned=$(find "$ROOT" -type f \( -name '*.md' -o -name '*.txt' -o -name '*.rst' \) 2>/dev/null | grep -Ev "$EXCLUDE_PATTERN" | wc -l)
set -o pipefail

if [ "$files_scanned" -eq 0 ]; then
  echo "brand-lint: ERROR — no content files (*.md/*.txt/*.rst) found under $ROOT"
  exit 2
fi

# Rule 1: bare 'Qtonic' — token-aware via Python (handles same-line bare+correct usage)
bare_qtonic=$(python3 - "$ROOT" "$EXCLUDE_PATTERN" <<'PYEOF'
import re, sys, glob
root = sys.argv[1]
exclude = sys.argv[2]
hits = []
for path_glob in (f"{root}/**/*.md", f"{root}/**/*.txt", f"{root}/**/*.rst"):
    for f in glob.glob(path_glob, recursive=True):
        if re.search(exclude, f):
            continue
        try:
            with open(f) as fh:
                for n, line in enumerate(fh, 1):
                    for m in re.finditer(r"\bQtonic\b", line):
                        end = m.end()
                        following = line[end:end+9]
                        if following.startswith(" Quantum"):
                            continue
                        broader = line[max(0, m.start()-1):m.end()+15].lower()
                        if "qtonicquantum" in broader:
                            continue
                        hits.append(f"{f}:{n}: {line.rstrip()}")
        except (OSError, UnicodeDecodeError):
            continue
print("\n".join(hits))
PYEOF
)
if [ -n "$bare_qtonic" ]; then
  echo "$bare_qtonic"
  echo "BRAND-VIOLATION: bare 'Qtonic' without 'Quantum'"
  violations=$((violations+1))
fi

# Rule 2: AI-marketing
if grep -rEn -i --include='*.md' '\bAI[- ](powered|driven|enabled|first|native)\b' "$ROOT" 2>/dev/null \
   | grep -Ev "$EXCLUDE_PATTERN"; then
  echo "BRAND-VIOLATION: 'AI-(powered|driven|enabled|first|native)' — use 'Intelligence Model'"
  violations=$((violations+1))
fi

# Rule 3: forbidden brand terms
for term in "advisory board" "simulation"; do
  if grep -rin --include='*.md' "$term" "$ROOT" 2>/dev/null \
     | grep -Ev "$EXCLUDE_PATTERN"; then
    echo "BRAND-VIOLATION: '$term' (use 'Leadership team' / 'demonstration')"
    violations=$((violations+1))
  fi
done

# Rule 4: cost / eng-day / time-estimate language
if grep -rEn -i --include='*.md' '\b(eng-?day|person-?day|man-?day)\b' "$ROOT" 2>/dev/null \
   | grep -Ev "$EXCLUDE_PATTERN"; then
  echo "BRAND-VIOLATION: cost/effort language in public artifact"
  violations=$((violations+1))
fi
if grep -rEn -i --include='*.md' '[0-9]+ ?(day|hour|minute)s? to (build|ship|complete|implement)' "$ROOT" 2>/dev/null \
   | grep -Ev "$EXCLUDE_PATTERN"; then
  echo "BRAND-VIOLATION: time-to-build claim in public artifact"
  violations=$((violations+1))
fi

# Rule 5: pricing — CORRECTLY escaped (was over-escaped, never fired)
if grep -rEn --include='*.md' '\$[0-9]+(,[0-9]{3})*(\.[0-9]{2})?(/[a-z]+)?' "$ROOT" 2>/dev/null \
   | grep -Ev "$EXCLUDE_PATTERN" \
   | grep -v 'shields.io' | grep -v 'badge'; then
  echo "BRAND-VIOLATION: pricing in public artifact"
  violations=$((violations+1))
fi
if grep -rEn --include='*.md' '\b[0-9]+ ?USD\b' "$ROOT" 2>/dev/null \
   | grep -Ev "$EXCLUDE_PATTERN"; then
  echo "BRAND-VIOLATION: pricing (USD) in public artifact"
  violations=$((violations+1))
fi

# Rule 6: every README.md (recursively) must carry the canonical phrase
canonical="leading quantum risk and vulnerability intelligence tools and services"
while IFS= read -r readme; do
  echo "$readme" | grep -Eq "$EXCLUDE_PATTERN" && continue
  if ! grep -qF "$canonical" "$readme"; then
    echo "BRAND-VIOLATION: $readme missing canonical phrase"
    violations=$((violations+1))
  fi
done < <(find "$ROOT" -maxdepth 4 -type f -name 'README.md' 2>/dev/null)

# Rule 7: every README.md (recursively) must carry the approved footer CTA
expected_footer="From Qtonic Quantum — leading quantum risk and vulnerability intelligence tools and services. Visit https://qtonicquantum.com."
while IFS= read -r readme; do
  echo "$readme" | grep -Eq "$EXCLUDE_PATTERN" && continue
  if ! grep -qF "$expected_footer" "$readme"; then
    echo "BRAND-VIOLATION: $readme missing approved footer CTA"
    violations=$((violations+1))
  fi
done < <(find "$ROOT" -maxdepth 4 -type f -name 'README.md' 2>/dev/null)

if [ "$violations" -eq 0 ]; then
  echo "brand-lint: PASS ($files_scanned content files scanned)"
  exit 0
fi
echo "brand-lint: $violations VIOLATION(S) over $files_scanned content files"
exit 1
