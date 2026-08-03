#!/usr/bin/env -S nix shell nixpkgs#nodejs -c node

import { updateBun } from "./bun.mjs";
import { updateDeno } from "./deno.mjs";
import { updateNode } from "./node.mjs";

await updateNode();
await updateBun();
await updateDeno();
