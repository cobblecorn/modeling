#!/usr/bin/env bash
# Builds everything and type-checks the runtime scripts against Roblox's API.
# Needs: lune, luau-lsp and luau-lsp's Roblox definitions file
#   (https://github.com/JohnnyMorganz/luau-lsp/blob/main/scripts/globalTypes.d.luau)
set -euo pipefail
cd "$(dirname "$0")/.."
LUNE=${LUNE:-lune}
LUAU_LSP=${LUAU_LSP:-luau-lsp}
DEFS=${ROBLOX_DEFS:-globalTypes.d.luau}

"$LUNE" run src/build.luau --sourcemap
out=$("$LUAU_LSP" analyze --definitions="$DEFS" --sourcemap=sourcemap.json --formatter=plain \
	src/runtime/WeaponCore/*.luau src/runtime/weapons/*.luau src/runtime/WeaponRigger.luau src/runtime/enemies/*.luau 2>&1 || true)
# the shared modules are reported once per tool; show each problem once
problems=$(printf '%s\n' "$out" | sed -E 's# \[game[^]]*\]##' | grep -E '\.luau:[0-9]+' | sort -u || true)
if [ -n "$problems" ]; then
	printf '%s\n' "$problems"
	exit 1
fi
echo "type check: clean"
"$LUNE" run tools/verify.luau
