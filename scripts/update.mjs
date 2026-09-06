#!/usr/bin/env -S nix shell nixpkgs#nodejs -c node

import { updateBun } from "./bun.mjs";
import { updateDeno } from "./deno.mjs";
import { updateNode } from "./node.mjs";
import { updatePnpm } from "./pnpm.mjs";
import { updateYarn } from "./yarn.mjs";

await updateNode();
await updateBun();
await updateDeno();
await updatePnpm();
await updateYarn();
