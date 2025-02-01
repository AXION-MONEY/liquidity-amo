#!/bin/bash
npx prettier --config .prettierrc --write "test/**/*.ts" "scripts/**/*.ts" "hardhat.config.ts"
npx prettier --write "contracts/**/*.sol"
